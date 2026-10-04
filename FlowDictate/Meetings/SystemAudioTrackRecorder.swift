@preconcurrency import AVFoundation
import CoreAudio
import Foundation

nonisolated enum SystemAudioTrackRecorderError: LocalizedError, Sendable, Equatable {
    case alreadyPrepared
    case notPrepared
    case invalidOutputURL
    case requiresMacOS14_2
    case missingUsageDescription
    case invalidTapIdentifier
    case invalidTapFormat
    case permissionDenied
    case unavailable
    case noAudioReceived
    case captureCancelled
    case interrupted(String)
    case conversionFailed(String)
    case writerFailed(String, outOfSpace: Bool)
    case operationFailed(operation: String, status: OSStatus)
    case cleanupTimedOut

    var errorDescription: String? {
        switch self {
        case .alreadyPrepared:
            "The system audio track is already prepared."
        case .notPrepared:
            "The system audio track is not prepared."
        case .invalidOutputURL:
            "The system audio original must use a CAF output path."
        case .requiresMacOS14_2:
            "The Core Audio system audio track requires macOS 14.2 or later."
        case .missingUsageDescription:
            "The app is missing NSAudioCaptureUsageDescription."
        case .invalidTapIdentifier:
            "Core Audio created a system audio tap without a usable identifier."
        case .invalidTapFormat:
            "Core Audio created a system audio tap without a usable PCM format."
        case .permissionDenied:
            "Screen & System Audio Recording access is required for this system audio track."
        case .unavailable:
            "System audio capture is not available."
        case .noAudioReceived:
            "The system audio track started but delivered no audio buffers."
        case .captureCancelled:
            "System audio capture was cancelled."
        case let .interrupted(message):
            "System audio capture stopped unexpectedly: \(message)"
        case let .conversionFailed(message):
            "System audio could not be converted to mono Float32 PCM: \(message)"
        case let .writerFailed(message, _):
            "The system audio original could not be written: \(message)"
        case let .operationFailed(operation, status):
            "Core Audio could not \(operation) (OSStatus \(status))."
        case .cleanupTimedOut:
            "Core Audio did not finish releasing the system audio capture. Restart NativeDictate before trying again."
        }
    }
}

/// Productive Core Audio implementation for macOS 14.2 and later.
/// Backend selection lives in `SystemAudioTrackRecorder` so a recording never
/// silently switches permission or recovery contracts after preparation.
actor CoreAudioSystemTrackRecorder: MixedTrackRecording {
    nonisolated let role: RecordingTrackRole = .systemAudio

    private let firstBufferTimeout: Duration
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var tapUID: String?
    private var aggregateUID: String?
    private var callbackQueue: DispatchQueue?
    private var sink: SystemAudioTrackCaptureSink?
    private var levelHandler: MixedTrackLevelHandler?
    private var warningHandler: MixedTrackWarningHandler?
    private var deviceStarted = false
    private var precomputedStopStatus: OSStatus?

    init(firstBufferTimeout: Duration = .seconds(2)) {
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
        guard sink == nil, tapID == kAudioObjectUnknown else {
            throw SystemAudioTrackRecorderError.alreadyPrepared
        }
        guard outputURL.pathExtension.lowercased() == "caf" else {
            throw SystemAudioTrackRecorderError.invalidOutputURL
        }
        guard #available(macOS 14.2, *) else {
            throw SystemAudioTrackRecorderError.requiresMacOS14_2
        }
        guard Bundle.main.object(
            forInfoDictionaryKey: "NSAudioCaptureUsageDescription"
        ) as? String != nil else {
            throw SystemAudioTrackRecorderError.missingUsageDescription
        }

        do {
            let excludedProcessIDs = try currentProcessObjectID().map { [$0] } ?? []
            let tapDescription = CATapDescription(
                monoGlobalTapButExcludeProcesses: excludedProcessIDs
            )
            tapDescription.name = "NativeDictate mixed system audio"
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = .unmuted

            try check(
                AudioHardwareCreateProcessTap(tapDescription, &tapID),
                operation: "create the system audio tap"
            )
            let tapUID = try tapUID(for: tapID)
            self.tapUID = tapUID
            var tapFormat = try tapFormat(for: tapID)
            guard let sourceFormat = AVAudioFormat(streamDescription: &tapFormat),
                  sourceFormat.sampleRate > 0,
                  sourceFormat.channelCount > 0,
                  let outputFormat = AVAudioFormat(
                      commonFormat: .pcmFormatFloat32,
                      sampleRate: sourceFormat.sampleRate,
                      channels: 1,
                      interleaved: false
                  ) else {
                throw SystemAudioTrackRecorderError.invalidTapFormat
            }
            let sink = try SystemAudioTrackCaptureSink(
                outputURL: outputURL,
                sourceFormat: sourceFormat,
                outputFormat: outputFormat,
                levelHandler: levelHandler,
                warningHandler: warningHandler
            )
            self.sink = sink

            let aggregateUID = "de.mcc.FlowDictate.mixed-system-audio.\(UUID().uuidString)"
            self.aggregateUID = aggregateUID
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "NativeDictate Mixed System Audio",
                kAudioAggregateDeviceUIDKey: aggregateUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapUIDKey: tapUID,
                        kAudioSubTapDriftCompensationKey: true
                    ]
                ]
            ]
            try check(
                AudioHardwareCreateAggregateDevice(
                    aggregateDescription as CFDictionary,
                    &aggregateDeviceID
                ),
                operation: "create the private system audio device"
            )

            let callbackQueue = DispatchQueue(
                label: "de.mcc.FlowDictate.mixed-system-audio",
                qos: .userInitiated
            )
            self.callbackQueue = callbackQueue
            try check(
                AudioDeviceCreateIOProcIDWithBlock(
                    &ioProcID,
                    aggregateDeviceID,
                    callbackQueue
                ) { _, inputData, inputTime, _, _ in
                    sink.append(inputData: inputData, inputTime: inputTime)
                },
                operation: "install the system audio callback"
            )
        } catch {
            _ = await releaseResources()
            reset()
            throw error
        }
    }

    func start(requestedHostTime: UInt64) async throws -> MixedTrackStartResult {
        guard aggregateDeviceID != kAudioObjectUnknown,
              ioProcID != nil,
              let sink,
              !deviceStarted else {
            throw SystemAudioTrackRecorderError.notPrepared
        }
        sink.begin(requestedHostTime: requestedHostTime)
        do {
            try check(
                AudioDeviceStart(aggregateDeviceID, ioProcID),
                operation: "start system audio capture"
            )
            deviceStarted = true
            let anchor = try await sink.waitForFirstAnchor(timeout: firstBufferTimeout)
            return MixedTrackStartResult(firstAnchor: anchor)
        } catch {
            precomputedStopStatus = stopDeviceIfNeeded()
            throw error
        }
    }

    func stop() async throws -> MixedTrackCaptureResult {
        guard let sink, aggregateDeviceID != kAudioObjectUnknown else {
            throw SystemAudioTrackRecorderError.notPrepared
        }
        precomputedStopStatus = stopDeviceIfNeeded()
        sink.endCapture()
        let captureResult: Result<MixedTrackCaptureResult, Error>
        do {
            captureResult = .success(try sink.finish())
        } catch {
            captureResult = .failure(error)
        }
        let cleanupResult = await releaseResources()
        reset()

        try validateCleanup(cleanupResult)
        return try captureResult.get()
    }

    func cancel() async -> MixedTrackCaptureResult? {
        guard sink != nil || tapID != kAudioObjectUnknown else { return nil }
        sink?.cancelPendingStart()
        precomputedStopStatus = stopDeviceIfNeeded()
        sink?.endCapture()
        let result = try? sink?.finish()
        _ = await releaseResources()
        reset()
        return result ?? nil
    }

    private func stopDeviceIfNeeded() -> OSStatus? {
        guard deviceStarted, aggregateDeviceID != kAudioObjectUnknown else {
            return precomputedStopStatus
        }
        let status = AudioDeviceStop(aggregateDeviceID, ioProcID)
        deviceStarted = false
        return status
    }

    private func validateCleanup(_ report: CoreAudioTapCleanupReport?) throws {
        guard let report else { throw SystemAudioTrackRecorderError.cleanupTimedOut }
        if let failure = report.firstFailure {
            throw SystemAudioTrackRecorderError.operationFailed(
                operation: failure.operation,
                status: failure.status
            )
        }
    }

    private func reset() {
        tapID = AudioObjectID(kAudioObjectUnknown)
        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        ioProcID = nil
        tapUID = nil
        aggregateUID = nil
        callbackQueue = nil
        sink = nil
        deviceStarted = false
        precomputedStopStatus = nil
    }

    @available(macOS 14.2, *)
    private func currentProcessObjectID() throws -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processID = getpid()
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var outputSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &processID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                qualifier,
                &outputSize,
                &processObjectID
            )
        }
        try check(status, operation: "resolve the current audio process")
        return processObjectID == kAudioObjectUnknown ? nil : processObjectID
    }

    @available(macOS 14.2, *)
    private func tapUID(for tapID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString>.size)
        var value: CFString = "" as CFString
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, pointer)
        }
        try check(status, operation: "read the system audio tap identifier")
        let result = value as String
        guard !result.isEmpty else {
            throw SystemAudioTrackRecorderError.invalidTapIdentifier
        }
        return result
    }

    @available(macOS 14.2, *)
    private func tapFormat(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var value = AudioStreamBasicDescription()
        try check(
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &value),
            operation: "read the system audio tap format"
        )
        guard value.mSampleRate > 0, value.mChannelsPerFrame > 0 else {
            throw SystemAudioTrackRecorderError.invalidTapFormat
        }
        return value
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw SystemAudioTrackRecorderError.operationFailed(
                operation: operation,
                status: status
            )
        }
    }

    private func releaseResources() async -> CoreAudioTapCleanupReport? {
        let tapID = tapID
        let aggregateDeviceID = aggregateDeviceID
        let ioProcID = ioProcID
        let deviceStarted = deviceStarted
        let stopStatus = precomputedStopStatus
        let tapUID = tapUID
        let aggregateUID = aggregateUID
        let initialReport = await withCheckedContinuation { continuation in
            let completion = SystemAudioTrackCleanupCompletion(continuation: continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                completion.resume(
                    with: Self.cleanup(
                        tapID: tapID,
                        aggregateDeviceID: aggregateDeviceID,
                        ioProcID: ioProcID,
                        deviceStarted: deviceStarted,
                        precomputedStopStatus: stopStatus,
                        tapUID: tapUID,
                        aggregateUID: aggregateUID
                    )
                )
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 3) {
                completion.resume(with: nil)
            }
        }
        guard let initialReport else { return nil }
        return await Self.waitForRegistrationRemoval(
            initialReport,
            tapUID: tapUID,
            aggregateUID: aggregateUID
        )
    }

    nonisolated private static func cleanup(
        tapID: AudioObjectID,
        aggregateDeviceID: AudioObjectID,
        ioProcID: AudioDeviceIOProcID?,
        deviceStarted: Bool,
        precomputedStopStatus: OSStatus?,
        tapUID: String?,
        aggregateUID: String?
    ) -> CoreAudioTapCleanupReport {
        var stopStatus = precomputedStopStatus
        var destroyIOProcStatus: OSStatus?
        var destroyAggregateDeviceStatus: OSStatus?
        var destroyTapStatus: OSStatus?
        if aggregateDeviceID != kAudioObjectUnknown {
            if deviceStarted { stopStatus = AudioDeviceStop(aggregateDeviceID, ioProcID) }
            if let ioProcID {
                destroyIOProcStatus = AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            }
            destroyAggregateDeviceStatus = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                destroyTapStatus = AudioHardwareDestroyProcessTap(tapID)
            } else {
                destroyTapStatus = kAudioHardwareUnsupportedOperationError
            }
        }
        return CoreAudioTapCleanupReport(
            stopStatus: stopStatus,
            destroyIOProcStatus: destroyIOProcStatus,
            destroyAggregateDeviceStatus: destroyAggregateDeviceStatus,
            destroyTapStatus: destroyTapStatus,
            aggregateDeviceRemoved: isUIDUnregistered(
                aggregateUID,
                selector: kAudioHardwarePropertyTranslateUIDToDevice
            ),
            tapRemoved: isUIDUnregistered(
                tapUID,
                selector: kAudioHardwarePropertyTranslateUIDToTap
            )
        )
    }

    nonisolated private static func isUIDUnregistered(
        _ uid: String?,
        selector: AudioObjectPropertySelector
    ) -> Bool {
        guard let uid else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var qualifier = uid as CFString
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var outputSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &qualifier) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                pointer,
                &outputSize,
                &objectID
            )
        }
        return status == noErr && objectID == kAudioObjectUnknown
    }

    nonisolated private static func waitForRegistrationRemoval(
        _ initialReport: CoreAudioTapCleanupReport,
        tapUID: String?,
        aggregateUID: String?
    ) async -> CoreAudioTapCleanupReport {
        var aggregateDeviceRemoved = initialReport.aggregateDeviceRemoved
        var tapRemoved = initialReport.tapRemoved
        for _ in 0..<20 where !aggregateDeviceRemoved || !tapRemoved {
            try? await Task.sleep(for: .milliseconds(50))
            aggregateDeviceRemoved = isUIDUnregistered(
                aggregateUID,
                selector: kAudioHardwarePropertyTranslateUIDToDevice
            )
            tapRemoved = isUIDUnregistered(
                tapUID,
                selector: kAudioHardwarePropertyTranslateUIDToTap
            )
        }
        return CoreAudioTapCleanupReport(
            stopStatus: initialReport.stopStatus,
            destroyIOProcStatus: initialReport.destroyIOProcStatus,
            destroyAggregateDeviceStatus: initialReport.destroyAggregateDeviceStatus,
            destroyTapStatus: initialReport.destroyTapStatus,
            aggregateDeviceRemoved: aggregateDeviceRemoved,
            tapRemoved: tapRemoved
        )
    }
}

/// Thread-safe endpoint invoked by the Core Audio IO callback queue.
nonisolated final class SystemAudioTrackCaptureSink: @unchecked Sendable {
    private let lock = NSLock()
    private let outputURL: URL
    private let sourceFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private var file: AVAudioFile?
    private var metrics: PCMTrackMetrics
    private var failure: SystemAudioTrackRecorderError?
    private var hasBegun = false
    private var acceptsAudio = false
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
            throw SystemAudioTrackRecorderError.conversionFailed(
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
        acceptsAudio = true
        lock.unlock()
    }

    func append(
        inputData: UnsafePointer<AudioBufferList>,
        inputTime: UnsafePointer<AudioTimeStamp>
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard hasBegun, acceptsAudio, failure == nil, let file else { return }
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            bufferListNoCopy: inputData,
            deallocator: nil
        ) else {
            failure = .conversionFailed("The Core Audio buffer did not match the tap format.")
            return
        }
        do {
            let outputBuffer = try convertedBuffer(from: sourceBuffer)
            guard outputBuffer.frameLength > 0 else { return }
            try file.write(from: outputBuffer)
            var timeStamp = inputTime.pointee
            let audioTime = AVAudioTime(
                audioTimeStamp: &timeStamp,
                sampleRate: sourceFormat.sampleRate
            )
            let clippedFrameCount = metrics.clippedFrameCount
            metrics.record(buffer: outputBuffer, time: audioTime)
            if metrics.clippedFrameCount > clippedFrameCount,
               clippingWarningGate.shouldPublish(at: ProcessInfo.processInfo.systemUptime) {
                warningHandler?(.clipping)
            }
            publishLevelIfNeeded(from: outputBuffer)
        } catch let error as SystemAudioTrackRecorderError {
            failure = error
            reportFailureIfNeeded(error)
        } catch {
            let writerError = SystemAudioTrackRecorderError.writerFailed(
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

    private func reportFailureIfNeeded(_ error: SystemAudioTrackRecorderError) {
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
        lock.unlock()
    }

    func cancelPendingStart() {
        lock.lock()
        acceptsAudio = false
        if metrics.firstAnchor == nil, failure == nil {
            failure = .captureCancelled
        }
        lock.unlock()
    }

    func finish() throws -> MixedTrackCaptureResult {
        lock.lock()
        acceptsAudio = false
        if let failure {
            file = nil
            lock.unlock()
            throw failure
        }
        guard hasBegun else {
            file = nil
            lock.unlock()
            throw SystemAudioTrackRecorderError.notPrepared
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
            throw SystemAudioTrackRecorderError.noAudioReceived
        }
    }

    private func convertedBuffer(from buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard buffer.format == sourceFormat else {
            throw SystemAudioTrackRecorderError.conversionFailed(
                "The tap format changed while recording."
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
            throw SystemAudioTrackRecorderError.conversionFailed(
                "The converted system audio buffer could not be allocated."
            )
        }
        do {
            try converter.convert(to: outputBuffer, from: buffer)
        } catch {
            throw SystemAudioTrackRecorderError.conversionFailed(
                error.localizedDescription
            )
        }
        return outputBuffer
    }

    func firstAnchorSnapshot() -> (
        TrackTimestampAnchor?,
        SystemAudioTrackRecorderError?
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (metrics.firstAnchor, failure)
    }
}

nonisolated private final class SystemAudioTrackCleanupCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CoreAudioTapCleanupReport?, Never>?

    init(continuation: CheckedContinuation<CoreAudioTapCleanupReport?, Never>) {
        self.continuation = continuation
    }

    func resume(with report: CoreAudioTapCleanupReport?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: report)
    }
}
