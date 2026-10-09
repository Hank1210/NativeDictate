import AppKit
import Combine
import OSLog
import SwiftUI

enum OverlayStatus: Equatable {
    case recording
    case finalizing
    case processing
    case inserting
    case longForm(String)
    case success(message: String)
    case error(String)

    var title: String {
        switch self {
        case .recording: "Recording"
        case .finalizing: "Finalizing…"
        case .processing: "Processing"
        case .inserting: "Inserting…"
        case let .longForm(message): message
        case .success: "Inserted"
        case .error: "Dictation failed"
        }
    }

    var symbolName: String {
        switch self {
        case .recording: "mic.fill"
        case .finalizing: "ellipsis.circle"
        case .processing: "ellipsis"
        case .inserting: "text.cursor"
        case .longForm: "waveform.badge.magnifyingglass"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }
}

nonisolated struct OverlayPreviewPresentation: Equatable, Sendable {
    let heading: String
    let statusMessage: String?
    let showsActivityIndicator: Bool

    static func resolve(
        source: RecordingAudioSource,
        state: LivePreviewState
    ) -> Self {
        if source == .systemAudio {
            return Self(
                heading: "SYSTEM AUDIO",
                statusMessage: "Live Preview is unavailable for System Audio. The transcript is created after recording stops.",
                showsActivityIndicator: false
            )
        }
        if source == .mixed {
            return Self(
                heading: "MEETING CAPTURE",
                statusMessage: "Microphone and System Audio are being saved as separate original tracks.",
                showsActivityIndicator: false
            )
        }

        return switch state {
        case .disabled:
            Self(
                heading: "LIVE PREVIEW",
                statusMessage: "Preview is off",
                showsActivityIndicator: false
            )
        case .waiting, .active:
            Self(
                heading: "LIVE PREVIEW",
                statusMessage: nil,
                showsActivityIndicator: true
            )
        case let .unavailable(message), let .failed(message):
            Self(
                heading: "PREVIEW STATUS",
                statusMessage: message,
                showsActivityIndicator: false
            )
        }
    }

    static func visibleText(_ text: String, for size: OverlaySize) -> String {
        switch size {
        case .compact:
            ""
        case .standard:
            text
        case .expanded:
            text
        }
    }
}

@MainActor
protocol RecordingOverlayPresenting: AnyObject {
    func show(status: OverlayStatus, level: Float, reposition: Bool)
    func updateLevel(_ level: Float)
    func updateMeetingLevels(microphone: Float, systemAudio: Float)
    func updateMeetingWarnings(_ warnings: [MixedRecordingWarning])
    func updatePreview(_ state: LivePreviewState)
    func updateSource(_ source: RecordingAudioSource)
    func configure(size: OverlaySize, position: OverlayPosition)
    func hide()
}

extension RecordingOverlayPresenting {
    func show(status: OverlayStatus, level: Float = 0, reposition: Bool = false) {
        show(status: status, level: level, reposition: reposition)
    }

    func updateSource(_ source: RecordingAudioSource) {}

    func updateMeetingLevels(microphone: Float, systemAudio: Float) {}

    func updateMeetingWarnings(_ warnings: [MixedRecordingWarning]) {}
}

@MainActor
private final class RecordingOverlayModel: ObservableObject {
    @Published var status: OverlayStatus = .recording
    @Published var level: Float = 0
    @Published var microphoneLevel: Float = 0
    @Published var systemAudioLevel: Float = 0
    @Published var meetingWarnings: [MixedRecordingWarning] = []
    @Published var previewState: LivePreviewState = .disabled
    @Published var size: OverlaySize = .standard
    @Published var source: RecordingAudioSource = .microphone

    var usesSingleRowLayout: Bool {
        size == .compact || status != .recording
    }

    var contentSize: CGSize {
        let configuredSize: CGSize = switch size {
        case .compact: CGSize(width: 320, height: 60)
        case .standard: CGSize(width: 420, height: 136)
        case .expanded: CGSize(width: 500, height: 236)
        }
        if status == .recording, source == .mixed, !meetingWarnings.isEmpty,
           size == .standard {
            return CGSize(width: configuredSize.width, height: 166)
        }
        guard status != .recording else { return configuredSize }
        if case .error = status {
            return CGSize(width: min(configuredSize.width, 390), height: 76)
        }
        return CGSize(width: min(configuredSize.width, 390), height: 60)
    }
}

@MainActor
final class RecordingOverlayController: RecordingOverlayPresenting {
    private let model = RecordingOverlayModel()
    private var panel: NonActivatingPanel?
    private var successHideTimer: DispatchSourceTimer?
    private var successHideDeadline: Date?
    private var presentationGeneration: UInt64 = 0
    private var overlayPosition: OverlayPosition = .bottomTrailing
    private var currentScreen: NSScreen?
    private static let successHideQueue = DispatchQueue(
        label: "de.mcc.NativeDictate.success-overlay-hide",
        qos: .userInitiated
    )

    func show(status: OverlayStatus, level: Float = 0, reposition: Bool = false) {
        expireOverdueSuccessOverlayIfNeeded()
        presentationGeneration &+= 1
        let generation = presentationGeneration
        cancelSuccessHideTimer()
        model.status = status
        model.level = level
        let panel = panel ?? makePanel()
        resize(panel)
        if reposition || !panel.isVisible {
            let screen = screenContainingMouse()
            currentScreen = screen
            position(panel, on: screen)
        }
        panel.orderFrontRegardless()
        if case .success = status {
            scheduleSuccessHide(generation: generation, after: 0.35)
            NativeDictateLogger.app.notice("Inserted overlay shown; auto-hide scheduled")
        }
    }

    func updateLevel(_ level: Float) {
        expireOverdueSuccessOverlayIfNeeded()
        model.level = level
    }

    func updateMeetingLevels(microphone: Float, systemAudio: Float) {
        expireOverdueSuccessOverlayIfNeeded()
        model.microphoneLevel = min(max(microphone, 0), 1)
        model.systemAudioLevel = min(max(systemAudio, 0), 1)
    }

    func updateMeetingWarnings(_ warnings: [MixedRecordingWarning]) {
        expireOverdueSuccessOverlayIfNeeded()
        model.meetingWarnings = warnings.sorted { $0.id < $1.id }
        if let panel { resize(panel) }
    }

    func updatePreview(_ state: LivePreviewState) {
        expireOverdueSuccessOverlayIfNeeded()
        model.previewState = state
    }

    func updateSource(_ source: RecordingAudioSource) {
        expireOverdueSuccessOverlayIfNeeded()
        model.source = source
    }

    func configure(size: OverlaySize, position: OverlayPosition) {
        expireOverdueSuccessOverlayIfNeeded()
        model.size = size
        overlayPosition = position
        guard let panel else { return }
        resize(panel)
        self.position(panel, on: currentScreen ?? screenContainingMouse())
    }

    func hide() {
        presentationGeneration &+= 1
        cancelSuccessHideTimer()
        panel?.orderOut(nil)
        model.level = 0
        model.microphoneLevel = 0
        model.systemAudioLevel = 0
        model.meetingWarnings = []
        model.previewState = .disabled
    }

    private func scheduleSuccessHide(generation: UInt64, after delay: TimeInterval) {
        let deadline = Date().addingTimeInterval(delay)
        successHideDeadline = deadline
        let timer = DispatchSource.makeTimerSource(queue: Self.successHideQueue)
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      self.presentationGeneration == generation,
                      case .success = self.model.status else { return }
                self.logSuccessHideLateness(deadline: deadline)
                self.hide()
                NativeDictateLogger.app.notice("Inserted overlay auto-hidden")
            }
        }
        successHideTimer = timer
        timer.resume()
    }

    private func cancelSuccessHideTimer() {
        successHideTimer?.cancel()
        successHideTimer = nil
        successHideDeadline = nil
    }

    private func expireOverdueSuccessOverlayIfNeeded(now: Date = Date()) {
        guard case .success = model.status,
              let deadline = successHideDeadline,
              now >= deadline else { return }
        logSuccessHideLateness(deadline: deadline, now: now)
        hide()
        NativeDictateLogger.app.notice("Inserted overlay auto-hidden")
    }

    private func logSuccessHideLateness(deadline: Date, now: Date = Date()) {
        let lateness = now.timeIntervalSince(deadline)
        guard lateness > 0.5 else { return }
        NativeDictateLogger.app.notice(
            "Inserted overlay auto-hide fired late by \(lateness, format: .fixed(precision: 3), privacy: .public)s"
        )
    }

    private func makePanel() -> NonActivatingPanel {
        let panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: RecordingOverlayView(model: model))
        self.panel = panel
        return panel
    }

    private func screenContainingMouse() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func position(_ panel: NSPanel, on screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let origin: NSPoint
        switch overlayPosition {
        case .bottomTrailing:
            origin = NSPoint(
                x: visibleFrame.maxX - panel.frame.width - 24,
                y: visibleFrame.minY + 24
            )
        case .bottomCenter:
            origin = NSPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.minY + 24
            )
        case .menuBarTrailing:
            origin = NSPoint(
                x: visibleFrame.maxX - panel.frame.width - 24,
                y: visibleFrame.maxY - panel.frame.height - 24
            )
        }
        panel.setFrameOrigin(origin)
    }

    private func resize(_ panel: NSPanel) {
        panel.setContentSize(model.contentSize)
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct RecordingOverlayView: View {
    @ObservedObject var model: RecordingOverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previousPreviewLineCount = 1

    var body: some View {
        Group {
            if model.usesSingleRowLayout {
                compactContent
            } else {
                regularContent
            }
        }
        .frame(width: model.contentSize.width, height: model.contentSize.height)
        .background(
            Color.black.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.34), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recording-overlay")
    }

    private var compactContent: some View {
        headerRow(indicatorDiameter: 30, meterWidth: 82, meterBars: 11)
            .padding(.horizontal, 13)
    }

    private var regularContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            headerRow(
                indicatorDiameter: 32,
                meterWidth: model.size == .expanded ? 132 : 96,
                meterBars: model.size == .expanded ? 16 : 12
            )

            if model.status == .recording {
                previewContent
            }
        }
        .padding(13)
    }

    private func headerRow(
        indicatorDiameter: CGFloat,
        meterWidth: CGFloat,
        meterBars: Int
    ) -> some View {
        HStack(spacing: 9) {
            statusIndicator(diameter: indicatorDiameter)
            statusHeader
            Spacer(minLength: 4)
            if model.status == .recording {
                if model.source == .mixed {
                    MeetingAudioLevelMeters(
                        microphone: model.microphoneLevel,
                        systemAudio: model.systemAudioLevel,
                        barCount: max(6, meterBars - 4)
                    )
                    .frame(width: meterWidth + 44)
                } else {
                    AudioBars(level: model.level, barCount: meterBars, height: 17)
                        .frame(width: meterWidth)
                }
            } else {
                secondaryStatusContent
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Text(model.status.title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.15)
                .fixedSize(horizontal: model.status == .recording, vertical: false)
                .foregroundStyle(Color.white.opacity(0.94))
            if showsLiveBadge, model.size != .compact {
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }
            if model.status == .recording,
               model.source == .mixed,
               !model.meetingWarnings.isEmpty {
                Group {
                    if model.size == .compact {
                        Image(systemName: "exclamationmark.triangle.fill")
                    } else {
                        Label("WARNING", systemImage: "exclamationmark.triangle.fill")
                    }
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
                .accessibilityLabel("Meeting capture warning")
            }
            if model.status == .recording,
               model.size != .compact,
               model.source != .mixed {
                Label(model.source.shortTitle, systemImage: model.source.symbolName)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.54))
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private var showsLiveBadge: Bool {
        guard model.status == .recording else { return false }
        return switch model.previewState {
        case .waiting, .active:
            true
        case .disabled, .unavailable, .failed:
            false
        }
    }

    @ViewBuilder
    private var secondaryStatusContent: some View {
        if case let .error(message) = model.status {
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(model.size == .compact ? 1 : 2)
        } else if model.status == .processing || model.status == .finalizing || model.status == .inserting {
            ProgressView()
                .controlSize(.small)
                .tint(statusColor)
        } else if case .longForm = model.status {
            ProgressView()
                .controlSize(.small)
                .tint(statusColor)
        } else if case let .success(message) = model.status {
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.68))
        }
    }

    private func statusIndicator(diameter: CGFloat) -> some View {
        ZStack {
            if model.status == .recording {
                Circle()
                    .stroke(statusColor.opacity(0.18), lineWidth: 6)
                    .scaleEffect(reduceMotion ? 1 : 1.12)
            }
            Circle()
                .fill(statusColor.opacity(0.13))
            Image(systemName: model.status.symbolName)
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(statusColor)
                .symbolEffect(.pulse, isActive: model.status == .recording && !reduceMotion)
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: model.status)
    }

    private var statusColor: Color {
        switch model.status {
        case .recording:
            model.source == .mixed && !model.meetingWarnings.isEmpty ? .orange : .red
        case .processing, .finalizing, .inserting, .longForm: .accentColor
        case .success: .green
        case .error: .orange
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        let presentation = OverlayPreviewPresentation.resolve(
            source: model.source,
            state: model.previewState
        )
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if presentation.showsActivityIndicator {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                }
                Text(presentation.heading)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(Color.white.opacity(0.46))
            }

            if model.source == .mixed, !model.meetingWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.meetingWarnings) { warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .lineLimit(model.size == .expanded ? 3 : 2)
                .accessibilityElement(children: .combine)
            } else if model.source == .systemAudio || model.source == .mixed {
                Text(presentation.statusMessage ?? "The transcript is created after recording stops.")
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(model.size == .expanded ? 4 : 3)
            } else {
                switch model.previewState {
                case .disabled:
                    Text(presentation.statusMessage ?? "Preview is off")
                        .foregroundStyle(Color.white.opacity(0.44))
                case .waiting:
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("Listening…")
                    }
                    .foregroundStyle(Color.white.opacity(0.72))
                case let .active(text):
                    let visibleText = OverlayPreviewPresentation.visibleText(text, for: model.size)
                    if model.size == .expanded {
                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(visibleText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.disabled)
                                    .foregroundStyle(previewTextColor)
                                Color.clear.frame(height: 1).id("preview-end")
                            }
                            .onChange(of: visibleText) {
                                let lineCount = visibleText.reduce(into: 1) { count, character in
                                    if character == "\n" { count += 1 }
                                }
                                defer { previousPreviewLineCount = lineCount }
                                guard lineCount > previousPreviewLineCount else { return }
                                proxy.scrollTo("preview-end", anchor: .bottom)
                            }
                        }
                    } else {
                        Text(visibleText)
                            .lineLimit(3)
                            .truncationMode(.head)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(previewTextColor)
                    }
                case let .unavailable(message), let .failed(message):
                    Text(presentation.statusMessage ?? message)
                        .foregroundStyle(Color.white.opacity(0.66))
                        .lineLimit(model.size == .expanded ? 4 : 3)
                }
            }
        }
        .font(.system(size: model.size == .expanded ? 15 : 13, weight: .regular, design: .rounded))
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var previewTextColor: Color {
        Color(red: 0.82, green: 0.84, blue: 0.86)
    }

}

private struct MeetingAudioLevelMeters: View {
    let microphone: Float
    let systemAudio: Float
    let barCount: Int

    var body: some View {
        VStack(spacing: 3) {
            meterRow(
                title: "Mic",
                symbol: "mic.fill",
                level: microphone,
                accessibilityName: "Microphone"
            )
            meterRow(
                title: "System",
                symbol: "speaker.wave.2.fill",
                level: systemAudio,
                accessibilityName: "System Audio"
            )
        }
    }

    private func meterRow(
        title: String,
        symbol: String,
        level: Float,
        accessibilityName: String
    ) -> some View {
        HStack(spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.66))
                .lineLimit(1)
                .frame(width: 48, alignment: .leading)
            AudioBars(level: level, barCount: barCount, height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityName) level")
        .accessibilityValue("\(Int((min(max(level, 0), 1) * 100).rounded())) percent")
    }
}

private struct AudioBars: View {
    let level: Float
    let barCount: Int
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(barColor(for: index))
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight(for: index))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let pattern: [CGFloat] = [0.34, 0.58, 0.82, 0.48, 1, 0.68, 0.4]
        let shape = pattern[index % pattern.count]
        let active = max(CGFloat(level), 0.08)
        return max(3, height * shape * (0.25 + active * 0.75))
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Float(index + 1) / Float(barCount)
        return threshold <= max(level, 0.04)
            ? Color(red: 0.22, green: 1, blue: 0.48)
            : Color(red: 0.22, green: 1, blue: 0.48).opacity(0.14)
    }
}
