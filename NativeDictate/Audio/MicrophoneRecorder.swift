@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import OSLog

struct AudioRecordingResult: Sendable {
    let id: UUID
    let url: URL
    let startedAt: Date
    let duration: TimeInterval
    let sourceMetadata: AudioSourceMetadata
}

enum AudioRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case unavailableInput
    case noAudioReceived
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A recording is already in progress."
        case .notRecording:
            "No recording is in progress."
        case .unavailableInput:
            "No usable microphone input is available."
        case .noAudioReceived:
            "The microphone started but delivered no audio buffers. Check the selected input device."
        case let .captureFailed(message):
            "Microphone capture failed: \(message)"
        }
    }
}

enum AudioLevelMeter {
    nonisolated static func normalizedRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        return normalizedRMS(
            UnsafeBufferPointer(start: channel, count: frameCount)
        )
    }

    nonisolated static func normalizedRMS(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for sample in samples {
            sum += Double(sample * sample)
        }
        return normalizedRMS(sumOfSquares: sum, sampleCount: samples.count)
    }

    nonisolated static func normalizedRMS(
        sumOfSquares: Double,
        sampleCount: Int
    ) -> Float {
        guard sampleCount > 0 else { return 0 }
        let rms = Float(sqrt(sumOfSquares / Double(sampleCount)))
        guard rms > 0.000_001 else { return 0 }

        // Speech occupies only a small part of the linear amplitude range. Map a
        // useful microphone range (-55...-8 dBFS) to the full meter and give quiet
        // speech a little more visual weight without making silence look active.
        let decibels = 20 * log10(rms)
        let linear = min(max((decibels + 55) / 47, 0), 1)
        return pow(linear, 0.65)
    }
}

nonisolated final class AudioLevelUpdateGate: @unchecked Sendable {
    private let minimumInterval: TimeInterval
    private var lastUpdate = -TimeInterval.infinity

    init(updatesPerSecond: Double = 10) {
        minimumInterval = 1 / max(updatesPerSecond, 1)
    }

    func shouldPublish(at timestamp: TimeInterval) -> Bool {
        guard timestamp - lastUpdate >= minimumInterval else { return false }
        lastUpdate = timestamp
        return true
    }
}

@MainActor
protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    var lastTimelineReport: ScreenCaptureTimelineReport? { get }
    var levelHandler: (@MainActor (Float) -> Void)? { get set }
    var previewBufferHandler: (@Sendable (LivePreviewAudioBuffer) -> Void)? { get set }
    func selectInputDevice(_ deviceID: AudioDeviceID?)
    func start() async throws
    func start(at outputURL: URL?) async throws
    func stop() async throws -> AudioRecordingResult
}

extension AudioRecording {
    var lastTimelineReport: ScreenCaptureTimelineReport? { nil }

    func start(at outputURL: URL?) async throws {
        try await start()
    }
}

@MainActor
final class MicrophoneRecorder: AudioRecording {
    private let store: AudioStore
    private var engine: AVAudioEngine?
    private var selectedInput: SelectedMicrophoneInput?
    private var sink: MicrophoneRecordingSink?
    private var recordingID: UUID?
    private var recordingURL: URL?
    private var startedAt: Date?
    private var selectedDeviceID: AudioDeviceID?

    var levelHandler: (@MainActor (Float) -> Void)?
    var previewBufferHandler: (@Sendable (LivePreviewAudioBuffer) -> Void)? {
        didSet { sink?.setPreviewHandler(previewBufferHandler) }
    }

    var isRecording: Bool {
        engine?.isRunning == true || selectedInput?.isRunning == true
    }

    convenience init(locationStore: RecordingLocationStore? = nil) {
        self.init(store: AudioStore(locationStore: locationStore))
    }

    init(store: AudioStore) {
        self.store = store
    }

    func selectInputDevice(_ deviceID: AudioDeviceID?) {
        selectedDeviceID = deviceID
    }

    func start() async throws {
        guard !isRecording else { throw AudioRecorderError.alreadyRecording }

        let id = UUID()
        let url = try store.makeRecordingURL(id: id)
        let selectedInput = try selectedDeviceID.map {
            try SelectedMicrophoneInput(deviceID: $0)
        }
        let engine = selectedInput == nil ? AVAudioEngine() : nil
        let inputNode = engine?.inputNode
        let tapFormat = selectedInput?.format ?? inputNode?.outputFormat(forBus: 0)
        guard let tapFormat,
              tapFormat.sampleRate > 0, tapFormat.channelCount > 0 else {
            throw AudioRecorderError.unavailableInput
        }
        NativeDictateLogger.audio.info(
            "Opening microphone: \(tapFormat.sampleRate, privacy: .public) Hz/\(tapFormat.channelCount, privacy: .public) ch, selected input \(selectedInput != nil, privacy: .public)"
        )

        let file = try AVAudioFile(forWriting: url, settings: tapFormat.settings)
        let sink = MicrophoneRecordingSink(
            file: file,
            previewHandler: previewBufferHandler,
            levelHandler: { [weak self] level in
                Task { @MainActor [weak self] in self?.levelHandler?(level) }
            }
        )
        if let selectedInput {
            selectedInput.setHandlers(
                onBuffer: { buffer, _ in sink.append(buffer) },
                onError: { status in sink.recordCaptureError(status) }
            )
        } else if let inputNode {
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) {
                buffer, _ in sink.append(buffer)
            }
        }

        do {
            engine?.prepare()
            if let selectedInput {
                try selectedInput.start()
            } else {
                try engine?.start()
            }
            try await sink.waitForFirstBuffer(timeout: .seconds(2))
        } catch {
            if let inputNode { inputNode.removeTap(onBus: 0) }
            engine?.stop()
            selectedInput?.stop()
            sink.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }

        self.engine = engine
        self.selectedInput = selectedInput
        self.sink = sink
        recordingID = id
        recordingURL = url
        startedAt = Date()
        NativeDictateLogger.audio.info("Recording started: \(url.lastPathComponent, privacy: .public)")
    }

    func stop() async throws -> AudioRecordingResult {
        guard
            engine != nil || selectedInput != nil,
            let id = recordingID,
            let url = recordingURL,
            let startedAt,
            let sink
        else {
            throw AudioRecorderError.notRecording
        }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        selectedInput?.stop()
        let recordedDuration = sink.close()
        let recordedFormat = sink.format
        self.engine = nil
        self.selectedInput = nil
        self.sink = nil
        recordingID = nil
        recordingURL = nil
        self.startedAt = nil
        levelHandler?(0)

        let result = AudioRecordingResult(
            id: id,
            url: url,
            startedAt: startedAt,
            duration: recordedDuration,
            sourceMetadata: AudioSourceMetadata(
                source: .microphone,
                sampleRate: recordedFormat.sampleRate,
                channelCount: Int(recordedFormat.channelCount)
            )
        )
        NativeDictateLogger.audio.info(
            "Recording stopped after \(result.duration, format: .fixed(precision: 2)) seconds"
        )
        return result
    }
}

/// Serializes file writes from either microphone backend and measures written PCM,
/// not elapsed wall time. This prevents empty files reaching the transcription model.
nonisolated final class MicrophoneRecordingSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var writtenFrames: Int64 = 0
    private var failure: AudioRecorderError?
    private var previewHandler: (@Sendable (LivePreviewAudioBuffer) -> Void)?
    private let levelHandler: @Sendable (Float) -> Void
    private let levelGate = AudioLevelUpdateGate(updatesPerSecond: 10)
    let format: AVAudioFormat

    init(
        file: AVAudioFile,
        previewHandler: (@Sendable (LivePreviewAudioBuffer) -> Void)?,
        levelHandler: @escaping @Sendable (Float) -> Void
    ) {
        self.file = file
        format = file.processingFormat
        self.previewHandler = previewHandler
        self.levelHandler = levelHandler
    }

    func setPreviewHandler(_ handler: (@Sendable (LivePreviewAudioBuffer) -> Void)?) {
        lock.withLock { previewHandler = handler }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard failure == nil, let file, buffer.frameLength > 0 else { return }
        do {
            try file.write(from: buffer)
            writtenFrames += Int64(buffer.frameLength)
        } catch {
            failure = .captureFailed(error.localizedDescription)
            NativeDictateLogger.audio.error(
                "Audio file write failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        if let previewHandler,
           let previewBuffer = LivePreviewAudioBuffer(copying: buffer) {
            previewHandler(previewBuffer)
        }
        if levelGate.shouldPublish(at: ProcessInfo.processInfo.systemUptime) {
            levelHandler(AudioLevelMeter.normalizedRMS(buffer))
        }
    }

    func recordCaptureError(_ status: OSStatus) {
        lock.lock()
        if failure == nil {
            failure = .captureFailed("Core Audio input returned \(status).")
        }
        lock.unlock()
    }

    func waitForFirstBuffer(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            let (frames, failure) = snapshot()
            if let failure { throw failure }
            if frames > 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw AudioRecorderError.noAudioReceived
    }

    @discardableResult
    func close() -> TimeInterval {
        lock.lock()
        file = nil
        let duration = Double(writtenFrames) / format.sampleRate
        lock.unlock()
        return duration
    }

    private func snapshot() -> (Int64, AudioRecorderError?) {
        lock.lock()
        defer { lock.unlock() }
        return (writtenFrames, failure)
    }
}
