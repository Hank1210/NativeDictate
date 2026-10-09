import Foundation
import OSLog

@MainActor
final class LivePreviewCoordinator {
    private let provider: any LivePreviewProviding
    private let updateInterval: Duration
    private let stallThreshold: TimeInterval
    private var sessionID: UUID?
    private var channel: LivePreviewBufferChannel?
    private var presentationTask: Task<Void, Never>?
    private var diagnosticsTask: Task<Void, Never>?
    private var diagnostics: LivePreviewDiagnostics?
    private var pendingText: String?
    private var characterLimit = 150

    var stateDidChange: (@MainActor (LivePreviewState) -> Void)?
    private(set) var state: LivePreviewState = .disabled {
        didSet {
            guard state != oldValue else { return }
            stateDidChange?(state)
        }
    }

    init(
        provider: any LivePreviewProviding,
        updateInterval: Duration = .milliseconds(120),
        stallThreshold: TimeInterval = 2
    ) {
        self.provider = provider
        self.updateInterval = updateInterval
        self.stallThreshold = stallThreshold
    }

    func start(
        configuration: LivePreviewConfiguration
    ) throws -> @Sendable (LivePreviewAudioBuffer) -> Void {
        cancel()
        let id = UUID()
        let channel = LivePreviewBufferChannel(limit: 8)
        let diagnostics = LivePreviewDiagnostics(stallThreshold: stallThreshold)
        sessionID = id
        self.channel = channel
        self.diagnostics = diagnostics
        characterLimit = min(max(configuration.characterLimit, 50), 800)
        state = .waiting
        NativeDictateLogger.audio.info(
            "Live Preview diagnostics started: locale=\(configuration.localeIdentifier, privacy: .public), characterLimit=\(self.characterLimit, privacy: .public)"
        )
        startDiagnosticsMonitor(diagnostics, channel: channel)

        do {
            try provider.start(
                buffers: channel.stream,
                localeIdentifier: configuration.localeIdentifier
            ) { [weak self] event in
                self?.handle(event, sessionID: id)
            }
        } catch {
            diagnosticsTask?.cancel()
            diagnosticsTask = nil
            sessionID = nil
            self.channel = nil
            self.diagnostics = nil
            channel.finish()
            diagnostics.logFinished(reason: "start-failed")
            state = .unavailable(error.localizedDescription)
            throw error
        }

        return { [diagnostics] buffer in
            diagnostics.recordAudioBuffer()
            channel.yield(buffer)
        }
    }

    func updateCharacterLimit(_ limit: Int) {
        characterLimit = min(max(limit, 50), 800)
        guard let pendingText else { return }
        self.pendingText = String(pendingText.suffix(characterLimit))
    }

    func finish() {
        presentationTask?.cancel()
        presentationTask = nil
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        pendingText = nil
        channel?.finish()
        channel = nil
        sessionID = nil
        provider.finish()
        diagnostics?.logFinished(reason: "finish")
        diagnostics = nil
        state = .disabled
    }

    func cancel() {
        presentationTask?.cancel()
        presentationTask = nil
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        pendingText = nil
        channel?.finish()
        channel = nil
        sessionID = nil
        provider.cancel()
        diagnostics?.logFinished(reason: "cancel")
        diagnostics = nil
        state = .disabled
    }

    private func handle(_ event: LivePreviewEvent, sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        switch event {
        case let .partial(text), let .finalSegment(text):
            diagnostics?.recordPreviewEvent(kind: event.diagnosticKind, textLength: text.count)
            schedulePresentation(text)
        case let .unavailable(message):
            stopPreview(with: .unavailable(message))
        case let .failed(message):
            stopPreview(with: .failed(message))
        case .finished:
            break
        }
    }

    private func schedulePresentation(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingText = String(trimmed.suffix(characterLimit))
        guard presentationTask == nil else { return }
        presentationTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: updateInterval)
                guard !Task.isCancelled else { return }
                guard let text = pendingText else {
                    presentationTask = nil
                    return
                }
                pendingText = nil
                state = .active(text)
            }
        }
    }

    private func stopPreview(with finalState: LivePreviewState) {
        presentationTask?.cancel()
        presentationTask = nil
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        pendingText = nil
        channel?.finish()
        channel = nil
        sessionID = nil
        provider.cancel()
        diagnostics?.logFinished(reason: finalState.diagnosticReason)
        diagnostics = nil
        state = finalState
    }

    private func startDiagnosticsMonitor(
        _ diagnostics: LivePreviewDiagnostics,
        channel: LivePreviewBufferChannel
    ) {
        diagnosticsTask?.cancel()
        diagnosticsTask = Task { [diagnostics, channel] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                diagnostics.updateDroppedBufferCount(channel.droppedBufferCount)
                diagnostics.logStallIfNeeded()
            }
        }
    }

    deinit {
        presentationTask?.cancel()
        diagnosticsTask?.cancel()
    }
}

private extension LivePreviewEvent {
    var diagnosticKind: String {
        switch self {
        case .partial:
            "partial"
        case .finalSegment:
            "final"
        case .unavailable:
            "unavailable"
        case .failed:
            "failed"
        case .finished:
            "finished"
        }
    }
}

private extension LivePreviewState {
    var diagnosticReason: String {
        switch self {
        case .disabled:
            "disabled"
        case .waiting:
            "waiting"
        case .active:
            "active"
        case .unavailable:
            "unavailable"
        case .failed:
            "failed"
        }
    }
}

nonisolated private final class LivePreviewDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private let stallThreshold: TimeInterval
    private let startedAt = Date()
    private var lastAudioAt: Date?
    private var lastPreviewAt: Date?
    private var lastStallLogAt: Date?
    private var audioBufferCount = 0
    private var previewEventCount = 0
    private var droppedBufferCount = 0

    init(stallThreshold: TimeInterval) {
        self.stallThreshold = stallThreshold
    }

    func recordAudioBuffer(now: Date = Date()) {
        lock.withLock {
            audioBufferCount += 1
            lastAudioAt = now
        }
    }

    func recordPreviewEvent(kind: String, textLength: Int, now: Date = Date()) {
        let snapshot = lock.withLock {
            previewEventCount += 1
            let previousPreviewAt = lastPreviewAt
            lastPreviewAt = now
            return (
                eventCount: previewEventCount,
                secondsSinceStart: now.timeIntervalSince(startedAt),
                secondsSincePreviousPreview: previousPreviewAt.map { now.timeIntervalSince($0) },
                audioBufferCount: audioBufferCount,
                droppedBufferCount: droppedBufferCount
            )
        }

        if let gap = snapshot.secondsSincePreviousPreview {
            NativeDictateLogger.audio.info(
                "Live Preview event: kind=\(kind, privacy: .public), count=\(snapshot.eventCount, privacy: .public), textLength=\(textLength, privacy: .public), gap=\(gap, format: .fixed(precision: 3), privacy: .public)s, audioBuffers=\(snapshot.audioBufferCount, privacy: .public), droppedBuffers=\(snapshot.droppedBufferCount, privacy: .public)"
            )
        } else {
            NativeDictateLogger.audio.info(
                "Live Preview first event: kind=\(kind, privacy: .public), textLength=\(textLength, privacy: .public), after=\(snapshot.secondsSinceStart, format: .fixed(precision: 3), privacy: .public)s, audioBuffers=\(snapshot.audioBufferCount, privacy: .public), droppedBuffers=\(snapshot.droppedBufferCount, privacy: .public)"
            )
        }
    }

    func updateDroppedBufferCount(_ count: Int) {
        lock.withLock { droppedBufferCount = count }
    }

    func logStallIfNeeded(now: Date = Date()) {
        let snapshot = lock.withLock {
            guard audioBufferCount > 0, let lastAudioAt else { return nil as StallSnapshot? }
            let reference = lastPreviewAt ?? startedAt
            let secondsWithoutPreview = now.timeIntervalSince(reference)
            guard secondsWithoutPreview >= stallThreshold else { return nil }
            guard lastAudioAt >= reference else { return nil }
            if let lastStallLogAt, now.timeIntervalSince(lastStallLogAt) < stallThreshold {
                return nil
            }
            self.lastStallLogAt = now
            return StallSnapshot(
                secondsWithoutPreview: secondsWithoutPreview,
                audioBufferCount: audioBufferCount,
                previewEventCount: previewEventCount,
                droppedBufferCount: droppedBufferCount
            )
        }
        guard let snapshot else { return }
        NativeDictateLogger.audio.notice(
            "Live Preview stalled: no provisional text for \(snapshot.secondsWithoutPreview, format: .fixed(precision: 2), privacy: .public)s while audio continues; audioBuffers=\(snapshot.audioBufferCount, privacy: .public), previewEvents=\(snapshot.previewEventCount, privacy: .public), droppedBuffers=\(snapshot.droppedBufferCount, privacy: .public)"
        )
    }

    func logFinished(reason: String, now: Date = Date()) {
        let snapshot = lock.withLock {
            (
                duration: now.timeIntervalSince(startedAt),
                audioBufferCount: audioBufferCount,
                previewEventCount: previewEventCount,
                droppedBufferCount: droppedBufferCount
            )
        }
        NativeDictateLogger.audio.info(
            "Live Preview diagnostics finished: reason=\(reason, privacy: .public), duration=\(snapshot.duration, format: .fixed(precision: 3), privacy: .public)s, audioBuffers=\(snapshot.audioBufferCount, privacy: .public), previewEvents=\(snapshot.previewEventCount, privacy: .public), droppedBuffers=\(snapshot.droppedBufferCount, privacy: .public)"
        )
    }

    private struct StallSnapshot {
        var secondsWithoutPreview: TimeInterval
        var audioBufferCount: Int
        var previewEventCount: Int
        var droppedBufferCount: Int
    }
}
