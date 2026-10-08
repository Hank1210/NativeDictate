@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

/// Compatibility implementation for macOS 14.0 and 14.1. It registers only an
/// audio output. No screen frames are requested, written or forwarded.
actor ScreenCaptureKitSystemTrackRecorder: MixedTrackRecording {
    nonisolated let role: RecordingTrackRole = .systemAudio

    private let permissionService: SystemAudioPermissionService
    private let firstBufferTimeout: Duration
    private let captureQueue = DispatchQueue(
        label: "de.mcc.NativeDictate.mixed-screen-capture-audio",
        qos: .userInitiated
    )
    private var stream: SCStream?
    private var output: ScreenCaptureKitTrackOutput?
    private var isRecording = false
    private var levelHandler: MixedTrackLevelHandler?
    private var warningHandler: MixedTrackWarningHandler?

    init(
        permissionService: SystemAudioPermissionService = SystemAudioPermissionService(),
        firstBufferTimeout: Duration = .seconds(2)
    ) {
        self.permissionService = permissionService
        self.firstBufferTimeout = firstBufferTimeout
    }

    func setLevelHandler(_ handler: MixedTrackLevelHandler?) async {
        levelHandler = handler
        output?.setLevelHandler(handler)
    }

    func setWarningHandler(_ handler: MixedTrackWarningHandler?) async {
        warningHandler = handler
        output?.setWarningHandler(handler)
    }

    func prepare(outputURL: URL) async throws {
        guard stream == nil, output == nil else {
            throw SystemAudioTrackRecorderError.alreadyPrepared
        }
        guard outputURL.pathExtension.lowercased() == "caf" else {
            throw SystemAudioTrackRecorderError.invalidOutputURL
        }
        guard permissionService.isAuthorized || permissionService.requestAccess() else {
            throw SystemAudioTrackRecorderError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let display = content.displays.first else {
            throw SystemAudioTrackRecorderError.unavailable
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.queueDepth = 3

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let output = ScreenCaptureKitTrackOutput(
            outputURL: outputURL,
            levelHandler: levelHandler,
            warningHandler: warningHandler
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        do {
            try stream.addStreamOutput(
                output,
                type: .audio,
                sampleHandlerQueue: captureQueue
            )
        } catch {
            throw SystemAudioTrackRecorderError.operationFailed(
                operation: "install the ScreenCaptureKit audio callback",
                status: kAudioHardwareUnspecifiedError
            )
        }
        self.output = output
        self.stream = stream
    }

    func start(requestedHostTime: UInt64) async throws -> MixedTrackStartResult {
        guard let stream, let output, !isRecording else {
            throw SystemAudioTrackRecorderError.notPrepared
        }
        output.begin(requestedHostTime: requestedHostTime)
        do {
            try await stream.startCapture()
            isRecording = true
            let anchor = try await output.waitForFirstAnchor(timeout: firstBufferTimeout)
            return MixedTrackStartResult(firstAnchor: anchor)
        } catch {
            if isRecording { try? await stream.stopCapture() }
            isRecording = false
            await drainCaptureQueue()
            output.endCapture()
            throw error
        }
    }

    func stop() async throws -> MixedTrackCaptureResult {
        guard let stream, let output else {
            throw SystemAudioTrackRecorderError.notPrepared
        }
        var stopError: Error?
        if isRecording {
            do { try await stream.stopCapture() }
            catch { stopError = error }
        }
        isRecording = false
        await drainCaptureQueue()
        output.endCapture()
        let captureResult = Result { try output.finish() }
        reset()

        if let stopError {
            throw SystemAudioTrackRecorderError.interrupted(stopError.localizedDescription)
        }
        return try captureResult.get()
    }

    func cancel() async -> MixedTrackCaptureResult? {
        guard let stream, let output else { return nil }
        output.cancelPendingStart()
        if isRecording { try? await stream.stopCapture() }
        isRecording = false
        await drainCaptureQueue()
        output.endCapture()
        let result = try? output.finish()
        reset()
        return result
    }

    private func drainCaptureQueue() async {
        await withCheckedContinuation { continuation in
            captureQueue.async { continuation.resume() }
        }
    }

    private func reset() {
        stream = nil
        output = nil
        isRecording = false
    }
}

nonisolated final class ScreenCaptureKitTrackOutput: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private let outputURL: URL
    private var sink: SystemAudioTrackCaptureSink?
    private var failure: SystemAudioTrackRecorderError?
    private var requestedHostTime: UInt64 = 0
    private var hasBegun = false
    private var acceptsAudio = false
    private var levelHandler: MixedTrackLevelHandler?
    private var warningHandler: MixedTrackWarningHandler?

    init(
        outputURL: URL,
        levelHandler: MixedTrackLevelHandler? = nil,
        warningHandler: MixedTrackWarningHandler? = nil
    ) {
        self.outputURL = outputURL
        self.levelHandler = levelHandler
        self.warningHandler = warningHandler
        super.init()
    }

    func setLevelHandler(_ handler: MixedTrackLevelHandler?) {
        lock.lock()
        levelHandler = handler
        let sink = sink
        lock.unlock()
        sink?.setLevelHandler(handler)
    }

    func setWarningHandler(_ handler: MixedTrackWarningHandler?) {
        lock.lock()
        warningHandler = handler
        let sink = sink
        lock.unlock()
        sink?.setWarningHandler(handler)
    }

    func begin(requestedHostTime: UInt64) {
        lock.lock()
        self.requestedHostTime = requestedHostTime
        failure = nil
        hasBegun = true
        acceptsAudio = true
        lock.unlock()
    }

    func waitForFirstAnchor(timeout: Duration) async throws -> TrackTimestampAnchor {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            let (anchor, failure) = firstAnchorSnapshot()
            if let failure { throw failure }
            if let anchor { return anchor }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SystemAudioTrackRecorderError.noAudioReceived
    }

    func endCapture() {
        lock.lock()
        acceptsAudio = false
        let sink = sink
        lock.unlock()
        sink?.endCapture()
    }

    func cancelPendingStart() {
        lock.lock()
        acceptsAudio = false
        let sink = sink
        if sink == nil, failure == nil { failure = .captureCancelled }
        lock.unlock()
        sink?.cancelPendingStart()
    }

    func finish() throws -> MixedTrackCaptureResult {
        lock.lock()
        acceptsAudio = false
        let sink = sink
        let failure = failure
        let hasBegun = hasBegun
        self.hasBegun = false
        lock.unlock()

        if let failure { throw failure }
        guard hasBegun else { throw SystemAudioTrackRecorderError.notPrepared }
        guard let sink else { throw SystemAudioTrackRecorderError.noAudioReceived }
        return try sink.finish()
    }

    private func append(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        lock.lock()
        guard hasBegun, acceptsAudio, failure == nil else {
            lock.unlock()
            return
        }
        let requestedHostTime = requestedHostTime
        var sink = sink
        let levelHandler = levelHandler
        lock.unlock()

        do {
            guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
                  var basic = CMAudioFormatDescriptionGetStreamBasicDescription(
                      description
                  )?.pointee,
                  let sourceFormat = AVAudioFormat(streamDescription: &basic),
                  sourceFormat.sampleRate > 0,
                  sourceFormat.channelCount > 0 else {
                throw SystemAudioTrackRecorderError.invalidTapFormat
            }
            if sink == nil {
                guard let outputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: sourceFormat.sampleRate,
                    channels: 1,
                    interleaved: false
                ) else {
                    throw SystemAudioTrackRecorderError.invalidTapFormat
                }
                let createdSink = try SystemAudioTrackCaptureSink(
                    outputURL: outputURL,
                    sourceFormat: sourceFormat,
                    outputFormat: outputFormat,
                    levelHandler: levelHandler,
                    warningHandler: warningHandler
                )
                createdSink.begin(requestedHostTime: requestedHostTime)
                lock.lock()
                if self.sink == nil, acceptsAudio {
                    self.sink = createdSink
                    sink = createdSink
                } else {
                    sink = self.sink
                }
                lock.unlock()
            }
            guard let sink else { return }
            try withAudioBufferList(from: sampleBuffer) { audioBufferList in
                var timeStamp = Self.audioTimeStamp(
                    for: sampleBuffer,
                    sampleRate: sourceFormat.sampleRate
                )
                withUnsafePointer(to: &timeStamp) { timePointer in
                    sink.append(inputData: audioBufferList, inputTime: timePointer)
                }
            }
        } catch let error as SystemAudioTrackRecorderError {
            record(error)
        } catch {
            record(.writerFailed(
                error.localizedDescription,
                outOfSpace: MixedRecordingWriteFailure.isOutOfSpace(error)
            ))
        }
    }

    private func firstAnchorSnapshot() -> (
        TrackTimestampAnchor?,
        SystemAudioTrackRecorderError?
    ) {
        lock.lock()
        let sink = sink
        let failure = failure
        lock.unlock()
        guard failure == nil, let sink else { return (nil, failure) }
        return sink.firstAnchorSnapshot()
    }

    private func record(_ error: SystemAudioTrackRecorderError) {
        lock.lock()
        let shouldReport = failure == nil
        if shouldReport { failure = error }
        let warningHandler = warningHandler
        lock.unlock()
        if shouldReport {
            if case .writerFailed = error {
                warningHandler?(.writerFailed)
            } else {
                warningHandler?(.sourceLost)
            }
        }
    }

    private func withAudioBufferList<T>(
        from sampleBuffer: CMSampleBuffer,
        body: (UnsafePointer<AudioBufferList>) throws -> T
    ) throws -> T {
        var requiredSize = 0
        var retainedBlockBuffer: CMBlockBuffer?
        _ = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &retainedBlockBuffer
        )
        guard requiredSize >= MemoryLayout<AudioBufferList>.size else {
            throw SystemAudioTrackRecorderError.unavailable
        }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let audioBufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: requiredSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else {
            throw SystemAudioTrackRecorderError.unavailable
        }
        return try body(UnsafePointer(audioBufferList))
    }

    private static func audioTimeStamp(
        for sampleBuffer: CMSampleBuffer,
        sampleRate: Double
    ) -> AudioTimeStamp {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid,
              !presentationTime.isIndefinite,
              sampleRate > 0 else {
            var fallback = AudioTimeStamp()
            fallback.mHostTime = mach_continuous_time()
            fallback.mFlags = [.hostTimeValid]
            return fallback
        }
        var result = AudioTimeStamp()
        result.mHostTime = CMClockConvertHostTimeToSystemUnits(presentationTime)
        result.mSampleTime = CMTimeGetSeconds(presentationTime) * sampleRate
        result.mFlags = [.hostTimeValid, .sampleTimeValid]
        return result
    }
}

extension ScreenCaptureKitTrackOutput: SCStreamOutput, SCStreamDelegate {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }
        append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        record(.interrupted(error.localizedDescription))
    }
}
