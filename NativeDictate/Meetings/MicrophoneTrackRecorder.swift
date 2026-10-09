@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

nonisolated enum MicrophoneTrackRecorderError: LocalizedError, Sendable, Equatable {
    case alreadyPrepared
    case notPrepared
    case invalidOutputURL
    case unavailableInput
    case noAudioReceived
    case captureCancelled
    case conversionFailed(String)
    case writerFailed(String, outOfSpace: Bool)

    var errorDescription: String? {
        switch self {
        case .alreadyPrepared:
            "The microphone track is already prepared."
        case .notPrepared:
            "The microphone track is not prepared."
        case .invalidOutputURL:
            "The microphone original must use a CAF output path."
        case .unavailableInput:
            "No usable microphone input is available."
        case .noAudioReceived:
            "The microphone started but delivered no audio buffers."
        case .captureCancelled:
            "Microphone capture was cancelled."
        case let .conversionFailed(message):
            "The microphone audio could not be converted to mono Float32 PCM: \(message)"
        case let .writerFailed(message, _):
            "The microphone original could not be written: \(message)"
        }
    }
}

actor MicrophoneTrackRecorder: MixedTrackRecording {
    nonisolated let role: RecordingTrackRole = .localSpeaker

    private let inputDeviceID: AudioDeviceID?
    private let firstBufferTimeout: Duration
    private var engine: AVAudioEngine?
    private var selectedInput: SelectedMicrophoneInput?
    private var sink: MicrophoneTrackCaptureSink?
    private var levelHandler: MixedTrackLevelHandler?
    private var warningHandler: MixedTrackWarningHandler?
    private var hasInstalledTap = false
    private var isRecording = false

    init(
        inputDeviceID: AudioDeviceID? = nil,
        firstBufferTimeout: Duration = .seconds(2)
    ) {
        self.inputDeviceID = inputDeviceID
        self.firstBufferTimeout = firstBufferTimeout
    }

    func setLevelHandler(_ handler: MixedTrackLevelHandler?) async {
        levelHandler = handler
        sink?.setLevelHandler(handler)
    }

    func setWarningHandler(_ handler: MixedTrackWarningHandler?) async {
        warningHandler = handler
        sink?.setWarningHandler(handler)
    }

    func prepare(outputURL: URL) async throws {
        guard engine == nil, selectedInput == nil else {
            throw MicrophoneTrackRecorderError.alreadyPrepared
        }
        guard outputURL.pathExtension.lowercased() == "caf" else {
            throw MicrophoneTrackRecorderError.invalidOutputURL
        }

        let selectedInput = try inputDeviceID.map { try SelectedMicrophoneInput(deviceID: $0) }
        let engine = selectedInput == nil ? AVAudioEngine() : nil
        let inputNode = engine?.inputNode
        let sourceFormat = selectedInput?.format ?? inputNode?.outputFormat(forBus: 0)
        guard let sourceFormat,
              sourceFormat.sampleRate > 0,
              sourceFormat.channelCount > 0 else {
            throw MicrophoneTrackRecorderError.unavailableInput
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw MicrophoneTrackRecorderError.unavailableInput
        }

        let sink = try MicrophoneTrackCaptureSink(
            outputURL: outputURL,
            sourceFormat: sourceFormat,
            outputFormat: outputFormat,
            levelHandler: levelHandler,
            warningHandler: warningHandler
        )
        if let selectedInput {
            selectedInput.setHandlers(
                onBuffer: { buffer, time in sink.append(buffer, at: time) },
                onError: { status in sink.recordCaptureError(status) }
            )
        } else if let engine, let inputNode {
            inputNode.installTap(onBus: 0, bufferSize: 4_096, format: sourceFormat) {
                buffer, time in sink.append(buffer, at: time)
            }
            hasInstalledTap = true
            engine.prepare()
        }
        self.engine = engine
        self.selectedInput = selectedInput
        self.sink = sink
    }

    func start(requestedHostTime: UInt64) async throws -> MixedTrackStartResult {
        guard engine != nil || selectedInput != nil,
              let sink, !isRecording else {
            throw MicrophoneTrackRecorderError.notPrepared
        }
        sink.begin(requestedHostTime: requestedHostTime)
        do {
            if let selectedInput {
                try selectedInput.start()
            } else {
                try engine?.start()
            }
            isRecording = true
            let anchor = try await sink.waitForFirstAnchor(timeout: firstBufferTimeout)
            return MixedTrackStartResult(firstAnchor: anchor)
        } catch {
            engine?.stop()
            selectedInput?.stop()
            isRecording = false
            throw error
        }
    }

    func stop() async throws -> MixedTrackCaptureResult {
        guard engine != nil || selectedInput != nil,
              let sink, isRecording else {
            throw MicrophoneTrackRecorderError.notPrepared
        }
        stopEngine()
        defer { reset() }
        return try sink.finish()
    }

    func cancel() async -> MixedTrackCaptureResult? {
        guard engine != nil || selectedInput != nil || sink != nil else { return nil }
        sink?.cancelPendingStart()
        stopEngine()
        defer { reset() }
        guard let sink else { return nil }
        return try? sink.finish()
    }

    private func stopEngine() {
        if hasInstalledTap, let engine {
            engine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        engine?.stop()
        selectedInput?.stop()
        isRecording = false
    }

    private func reset() {
        engine = nil
        selectedInput = nil
        sink = nil
        hasInstalledTap = false
        isRecording = false
    }
}

/// Thread-safe endpoint used directly by AVAudioEngine's realtime callback.
/// The engine is stopped and its tap removed before `finish()` is called.
nonisolated final class MicrophoneTrackCaptureSink: @unchecked Sendable {
    private let lock = NSLock()
    private let outputURL: URL
    private let sourceFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private var file: AVAudioFile?
    private var metrics: PCMTrackMetrics
    private var failure: MicrophoneTrackRecorderError?
    private var hasBegun = false
    private var levelHandler: MixedTrackLevelHandler?
    private var warningHandler: MixedTrackWarningHandler?
    private var clippingWarningGate = AudioLevelUpdateGate(updatesPerSecond: 1)
    private var didReportFailure = false
    private let levelUpdateGate = AudioLevelUpdateGate(updatesPerSecond: 10)

    init(
        outputURL: URL,
        sourceFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        levelHandler: MixedTrackLevelHandler? = nil,
        warningHandler: MixedTrackWarningHandler? = nil
    ) throws {
        self.outputURL = outputURL
        self.sourceFormat = sourceFormat
        self.outputFormat = outputFormat
        self.levelHandler = levelHandler
        self.warningHandler = warningHandler
        converter = sourceFormat == outputFormat
            ? nil
            : AVAudioConverter(from: sourceFormat, to: outputFormat)
        if sourceFormat != outputFormat, converter == nil {
            throw MicrophoneTrackRecorderError.conversionFailed(
                "AVAudioConverter could not create the requested format conversion."
            )
        }
        file = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        metrics = PCMTrackMetrics(sampleRate: outputFormat.sampleRate)
    }

    func setLevelHandler(_ handler: MixedTrackLevelHandler?) {
        lock.lock()
        levelHandler = handler
        lock.unlock()
    }

    func setWarningHandler(_ handler: MixedTrackWarningHandler?) {
        lock.lock()
        warningHandler = handler
        lock.unlock()
    }

    func begin(requestedHostTime: UInt64) {
        lock.lock()
        metrics = PCMTrackMetrics(
            requestedHostTime: requestedHostTime,
            sampleRate: outputFormat.sampleRate
        )
        failure = nil
        clippingWarningGate = AudioLevelUpdateGate(updatesPerSecond: 1)
        didReportFailure = false
        hasBegun = true
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        lock.lock()
        defer { lock.unlock() }
        guard hasBegun, failure == nil, let file else { return }
        do {
            let outputBuffer = try convertedBuffer(from: buffer)
            guard outputBuffer.frameLength > 0 else { return }
            try file.write(from: outputBuffer)
            let clippedFrameCount = metrics.clippedFrameCount
            metrics.record(buffer: outputBuffer, time: time)
            if metrics.clippedFrameCount > clippedFrameCount,
               clippingWarningGate.shouldPublish(at: ProcessInfo.processInfo.systemUptime) {
                warningHandler?(.clipping)
            }
            publishLevelIfNeeded(from: outputBuffer)
        } catch let error as MicrophoneTrackRecorderError {
            failure = error
            reportFailureIfNeeded(error)
        } catch {
            let writerError = MicrophoneTrackRecorderError.writerFailed(
                error.localizedDescription,
                outOfSpace: MixedRecordingWriteFailure.isOutOfSpace(
                    error,
                    writingTo: outputURL
                )
            )
            failure = writerError
            reportFailureIfNeeded(writerError)
        }
    }

    func recordCaptureError(_ status: OSStatus) {
        lock.lock()
        defer { lock.unlock() }
        guard hasBegun, failure == nil else { return }
        let error = MicrophoneTrackRecorderError.conversionFailed(
            "Core Audio input returned \(status)."
        )
        failure = error
        reportFailureIfNeeded(error)
    }

    private func reportFailureIfNeeded(_ error: MicrophoneTrackRecorderError) {
        guard !didReportFailure else { return }
        didReportFailure = true
        if case .writerFailed = error {
            warningHandler?(.writerFailed)
        } else {
            warningHandler?(.sourceLost)
        }
    }

    private func publishLevelIfNeeded(from buffer: AVAudioPCMBuffer) {
        guard levelUpdateGate.shouldPublish(at: ProcessInfo.processInfo.systemUptime) else {
            return
        }
        levelHandler?(AudioLevelMeter.normalizedRMS(buffer))
    }

    func waitForFirstAnchor(timeout: Duration) async throws -> TrackTimestampAnchor {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            let (anchor, failure) = startSnapshot()
            if let failure { throw failure }
            if let anchor { return anchor }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw MicrophoneTrackRecorderError.noAudioReceived
    }

    func cancelPendingStart() {
        lock.lock()
        if metrics.firstAnchor == nil, failure == nil {
            failure = .captureCancelled
        }
        lock.unlock()
    }

    func finish() throws -> MixedTrackCaptureResult {
        lock.lock()
        if let failure {
            file = nil
            lock.unlock()
            throw failure
        }
        guard hasBegun else {
            file = nil
            lock.unlock()
            throw MicrophoneTrackRecorderError.notPrepared
        }
        file = nil
        let metrics = self.metrics
        hasBegun = false
        lock.unlock()

        let byteCount = Int64(
            try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        )
        do {
            return try metrics.captureResult(byteCount: byteCount)
        } catch PCMTrackMetricsError.noAudioReceived {
            throw MicrophoneTrackRecorderError.noAudioReceived
        }
    }

    private func convertedBuffer(from buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard buffer.format == sourceFormat else {
            throw MicrophoneTrackRecorderError.conversionFailed(
                "The input format changed while recording."
            )
        }
        guard let converter else { return buffer }
        let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(
            max(1, ceil(Double(buffer.frameLength) * ratio) + 32)
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: capacity
        ) else {
            throw MicrophoneTrackRecorderError.conversionFailed(
                "The converted audio buffer could not be allocated."
            )
        }

        do {
            try converter.convert(to: outputBuffer, from: buffer)
        } catch {
            throw MicrophoneTrackRecorderError.conversionFailed(
                error.localizedDescription
            )
        }
        return outputBuffer
    }

    private func startSnapshot() -> (TrackTimestampAnchor?, MicrophoneTrackRecorderError?) {
        lock.lock()
        defer { lock.unlock() }
        return (metrics.firstAnchor, failure)
    }
}
