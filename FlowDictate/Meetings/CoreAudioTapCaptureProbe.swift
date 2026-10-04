import CoreAudio
import Foundation

nonisolated enum SystemAudioCaptureBackend: String, Codable, Sendable, Equatable {
    case coreAudioTap
    case screenCaptureKit
}

nonisolated enum SystemAudioProbeDuration: Int, CaseIterable, Identifiable, Sendable {
    case fiveSeconds = 5
    case fiveMinutes = 300
    case thirtyMinutes = 1_800
    case sixtyMinutes = 3_600

    var id: Int { rawValue }
    var duration: Duration { .seconds(rawValue) }

    var title: String {
        switch self {
        case .fiveSeconds: "5 Seconds"
        case .fiveMinutes: "5 Minutes"
        case .thirtyMinutes: "30 Minutes"
        case .sixtyMinutes: "60 Minutes"
        }
    }

    var compactTitle: String {
        switch self {
        case .fiveSeconds: "5 sec"
        case .fiveMinutes: "5 min"
        case .thirtyMinutes: "30 min"
        case .sixtyMinutes: "60 min"
        }
    }
}

nonisolated struct SystemAudioCaptureStrategy: Sendable {
    let preferredBackend: SystemAudioCaptureBackend
    let minimumOperatingSystem: OperatingSystemVersion
    let requiresAudioCaptureUsageDescription: Bool
    let permissionSettingsLabel: String

    static func candidate(
        for version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Self {
        if isAtLeastMacOS14_2(version) {
            return Self(
                preferredBackend: .coreAudioTap,
                minimumOperatingSystem: OperatingSystemVersion(
                    majorVersion: 14,
                    minorVersion: 2,
                    patchVersion: 0
                ),
                requiresAudioCaptureUsageDescription: true,
                permissionSettingsLabel: "System Audio Recording Only"
            )
        }
        return Self(
            preferredBackend: .screenCaptureKit,
            minimumOperatingSystem: OperatingSystemVersion(
                majorVersion: 14,
                minorVersion: 0,
                patchVersion: 0
            ),
            requiresAudioCaptureUsageDescription: false,
            permissionSettingsLabel: "Screen & System Audio Recording"
        )
    }

    private static func isAtLeastMacOS14_2(_ version: OperatingSystemVersion) -> Bool {
        version.majorVersion > 14
            || (version.majorVersion == 14 && version.minorVersion >= 2)
    }
}

nonisolated struct CoreAudioTapProbeReport: Sendable, Equatable {
    let requestedDuration: TimeInterval
    let wallDuration: TimeInterval
    let callbackCount: Int
    let nonSilentCallbackCount: Int
    let frameCount: Int64
    let sampleRate: Double
    let channelCount: Int
    let firstHostTime: UInt64?
    let lastHostTime: UInt64?
    let firstSampleTime: Double?
    let lastSampleTime: Double?
    let missingHostTimeCount: Int
    let missingSampleTimeCount: Int
    let hostTimeRegressionCount: Int
    let sampleTimeRegressionCount: Int
    let sampleDiscontinuityCount: Int
    let largestPositiveSampleGapFrames: Int64
    let largestHostTimeDeltaNanoseconds: UInt64
    let cleanup: CoreAudioTapCleanupReport

    var capturedDuration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(frameCount) / sampleRate
    }

    var stopDelay: TimeInterval {
        wallDuration - requestedDuration
    }

    var hasCapturedSignal: Bool {
        nonSilentCallbackCount > 0
    }

    var hasMonotonicTimeline: Bool {
        missingHostTimeCount == 0
            && missingSampleTimeCount == 0
            && hostTimeRegressionCount == 0
            && sampleTimeRegressionCount == 0
    }

    var hasContinuousSampleTimeline: Bool {
        hasMonotonicTimeline && sampleDiscontinuityCount == 0
    }
}

nonisolated struct CoreAudioTapCleanupReport: Sendable, Equatable {
    let stopStatus: OSStatus?
    let destroyIOProcStatus: OSStatus?
    let destroyAggregateDeviceStatus: OSStatus?
    let destroyTapStatus: OSStatus?
    let aggregateDeviceRemoved: Bool
    let tapRemoved: Bool

    var succeeded: Bool {
        stopStatus == noErr
            && destroyIOProcStatus == noErr
            && destroyAggregateDeviceStatus == noErr
            && destroyTapStatus == noErr
            && aggregateDeviceRemoved
            && tapRemoved
    }

    var firstFailure: (operation: String, status: OSStatus)? {
        for (operation, status) in [
            ("stop the aggregate device", stopStatus),
            ("remove the aggregate-device IO callback", destroyIOProcStatus),
            ("destroy the private aggregate device", destroyAggregateDeviceStatus),
            ("destroy the process tap", destroyTapStatus)
        ] {
            guard let status else {
                return ("confirm that cleanup did \(operation)", kAudioHardwareUnspecifiedError)
            }
            if status != noErr { return (operation, status) }
        }
        if !aggregateDeviceRemoved {
            return ("verify aggregate-device removal", kAudioHardwareUnspecifiedError)
        }
        if !tapRemoved {
            return ("verify process-tap removal", kAudioHardwareUnspecifiedError)
        }
        return nil
    }
}

nonisolated struct CoreAudioTapRepeatedProbeReport: Sendable, Equatable {
    let cycles: [CoreAudioTapProbeReport]

    var completedCycleCount: Int { cycles.count }
    var totalCallbackCount: Int { cycles.reduce(0) { $0 + $1.callbackCount } }
    var totalNonSilentCallbackCount: Int {
        cycles.reduce(0) { $0 + $1.nonSilentCallbackCount }
    }
    var hostTimeRegressionCount: Int {
        cycles.reduce(0) { $0 + $1.hostTimeRegressionCount }
    }
    var sampleTimeRegressionCount: Int {
        cycles.reduce(0) { $0 + $1.sampleTimeRegressionCount }
    }
    var sampleDiscontinuityCount: Int {
        cycles.reduce(0) { $0 + $1.sampleDiscontinuityCount }
    }
    var largestPositiveSampleGapFrames: Int64 {
        cycles.map(\.largestPositiveSampleGapFrames).max() ?? 0
    }
    var hasCapturedSignal: Bool { totalNonSilentCallbackCount > 0 }
    var allCleanupSucceeded: Bool { cycles.allSatisfy { $0.cleanup.succeeded } }
    var allTimelinesMonotonic: Bool { cycles.allSatisfy(\.hasMonotonicTimeline) }
}

nonisolated enum CoreAudioTapProbeError: LocalizedError, Equatable {
    case requiresMacOS14_2
    case missingUsageDescription
    case operationFailed(operation: String, status: OSStatus)
    case invalidTapIdentifier
    case invalidTapFormat
    case noAudioCallbacks
    case cleanupTimedOut
    case invalidCycleCount

    var errorDescription: String? {
        switch self {
        case .requiresMacOS14_2:
            "The audio-only Core Audio tap requires macOS 14.2 or later."
        case .missingUsageDescription:
            "The app is missing NSAudioCaptureUsageDescription."
        case let .operationFailed(operation, status):
            "Core Audio could not \(operation) (OSStatus \(statusDescription(status)))."
        case .invalidTapIdentifier:
            "Core Audio created a tap without a usable identifier."
        case .invalidTapFormat:
            "Core Audio created a tap without a usable audio format."
        case .noAudioCallbacks:
            "The Core Audio tap started but delivered no audio callbacks."
        case .cleanupTimedOut:
            "Core Audio did not finish releasing the audio-only capture. Restart NativeDictate before trying again."
        case .invalidCycleCount:
            "The Core Audio tap repetition count must be between 1 and 100."
        }
    }

    private func statusDescription(_ status: OSStatus) -> String {
        let value = UInt32(bitPattern: status)
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        if bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) {
            return "'\(String(bytes: bytes, encoding: .ascii) ?? "????")' / \(status)"
        }
        return String(status)
    }
}

/// Development-only measurement path for the Phase 4.1 capture decision.
/// It never registers a screen output and never persists audio samples.
actor CoreAudioTapCaptureProbe {
    func run(for duration: Duration = .seconds(5)) async throws -> CoreAudioTapProbeReport {
        guard #available(macOS 14.2, *) else {
            throw CoreAudioTapProbeError.requiresMacOS14_2
        }
        guard Bundle.main.object(
            forInfoDictionaryKey: "NSAudioCaptureUsageDescription"
        ) as? String != nil else {
            throw CoreAudioTapProbeError.missingUsageDescription
        }

        let metrics = CoreAudioTapProbeMetrics()
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        var ioProcID: AudioDeviceIOProcID?
        var deviceStarted = false
        var timedStopResult: CoreAudioTapTimedStop.Result?
        var createdTapUID: String?
        var createdAggregateUID: String?

        do {
            let excludedProcessIDs = try currentProcessObjectID().map { [$0] } ?? []
            let tapDescription = CATapDescription(
                monoGlobalTapButExcludeProcesses: excludedProcessIDs
            )
            tapDescription.name = "NativeDictate audio-only capture probe"
            tapDescription.isPrivate = true
            tapDescription.muteBehavior = .unmuted

            try check(
                AudioHardwareCreateProcessTap(tapDescription, &tapID),
                operation: "create the process tap"
            )
            let tapUID = try tapUID(for: tapID)
            createdTapUID = tapUID
            let tapFormat = try tapFormat(for: tapID)

            let aggregateUID = "de.mcc.FlowDictate.capture-probe.\(UUID().uuidString)"
            createdAggregateUID = aggregateUID
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "NativeDictate Capture Probe",
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
                operation: "create the private aggregate device"
            )

            let callbackQueue = DispatchQueue(
                label: "de.mcc.FlowDictate.core-audio-tap-probe",
                qos: .userInitiated
            )
            try check(
                AudioDeviceCreateIOProcIDWithBlock(
                    &ioProcID,
                    aggregateDeviceID,
                    callbackQueue
                ) { _, inputData, inputTime, _, _ in
                    metrics.record(
                        inputData: inputData,
                        inputTime: inputTime,
                        format: tapFormat
                    )
                },
                operation: "install the aggregate-device IO callback"
            )
            try check(
                AudioDeviceStart(aggregateDeviceID, ioProcID),
                operation: "start audio-only capture"
            )
            deviceStarted = true
            let timedStop = CoreAudioTapTimedStop {
                AudioDeviceStop(aggregateDeviceID, ioProcID)
            }
            timedStopResult = await timedStop.wait(for: duration.timeInterval)
            deviceStarted = timedStopResult?.status != noErr
            try check(
                timedStopResult?.status ?? kAudioHardwareUnspecifiedError,
                operation: "stop audio-only capture"
            )
            try Task.checkCancellation()
        } catch {
            let cleanupReport = await cleanupWithTimeout(
                tapID: tapID,
                aggregateDeviceID: aggregateDeviceID,
                ioProcID: ioProcID,
                deviceStarted: deviceStarted,
                precomputedStopStatus: timedStopResult?.status,
                tapUID: createdTapUID,
                aggregateUID: createdAggregateUID
            )
            guard cleanupReport != nil else {
                throw CoreAudioTapProbeError.cleanupTimedOut
            }
            throw error
        }

        guard let initialCleanupReport = await cleanupWithTimeout(
            tapID: tapID,
            aggregateDeviceID: aggregateDeviceID,
            ioProcID: ioProcID,
            deviceStarted: deviceStarted,
            precomputedStopStatus: timedStopResult?.status,
            tapUID: createdTapUID,
            aggregateUID: createdAggregateUID
        ) else {
            throw CoreAudioTapProbeError.cleanupTimedOut
        }
        let cleanupReport = await waitForCleanupRegistrationRemoval(
            initialCleanupReport,
            tapUID: createdTapUID,
            aggregateUID: createdAggregateUID
        )
        if let failure = cleanupReport.firstFailure {
            throw CoreAudioTapProbeError.operationFailed(
                operation: failure.operation,
                status: failure.status
            )
        }
        let report = metrics.report(
            requestedDuration: duration.timeInterval,
            wallDuration: timedStopResult?.elapsed ?? 0,
            cleanup: cleanupReport
        )
        guard report.callbackCount > 0 else {
            throw CoreAudioTapProbeError.noAudioCallbacks
        }
        return report
    }

    func runRepeated(
        cycles: Int = 10,
        cycleDuration: Duration = .seconds(1),
        pause: Duration = .milliseconds(100)
    ) async throws -> CoreAudioTapRepeatedProbeReport {
        guard (1...100).contains(cycles) else {
            throw CoreAudioTapProbeError.invalidCycleCount
        }
        var reports: [CoreAudioTapProbeReport] = []
        reports.reserveCapacity(cycles)
        for cycleIndex in 0..<cycles {
            try Task.checkCancellation()
            reports.append(try await run(for: cycleDuration))
            if cycleIndex < cycles - 1 { try await Task.sleep(for: pause) }
        }
        return CoreAudioTapRepeatedProbeReport(cycles: reports)
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
        try check(status, operation: "read the tap identifier")
        let result = value as String
        guard !result.isEmpty else { throw CoreAudioTapProbeError.invalidTapIdentifier }
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
            operation: "read the tap format"
        )
        guard value.mSampleRate > 0, value.mChannelsPerFrame > 0 else {
            throw CoreAudioTapProbeError.invalidTapFormat
        }
        return value
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw CoreAudioTapProbeError.operationFailed(operation: operation, status: status)
        }
    }

    @available(macOS 14.2, *)
    private func cleanupWithTimeout(
        tapID: AudioObjectID,
        aggregateDeviceID: AudioObjectID,
        ioProcID: AudioDeviceIOProcID?,
        deviceStarted: Bool,
        precomputedStopStatus: OSStatus? = nil,
        tapUID: String?,
        aggregateUID: String?
    ) async -> CoreAudioTapCleanupReport? {
        await withCheckedContinuation { continuation in
            let completion = CoreAudioTapCleanupCompletion(continuation: continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                completion.resume(
                    with: Self.cleanup(
                        tapID: tapID,
                        aggregateDeviceID: aggregateDeviceID,
                        ioProcID: ioProcID,
                        deviceStarted: deviceStarted,
                        precomputedStopStatus: precomputedStopStatus,
                        tapUID: tapUID,
                        aggregateUID: aggregateUID
                    )
                )
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 3) {
                completion.resume(with: nil)
            }
        }
    }

    @available(macOS 14.2, *)
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
            destroyTapStatus = AudioHardwareDestroyProcessTap(tapID)
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

    private func waitForCleanupRegistrationRemoval(
        _ initialReport: CoreAudioTapCleanupReport,
        tapUID: String?,
        aggregateUID: String?
    ) async -> CoreAudioTapCleanupReport {
        var aggregateDeviceRemoved = initialReport.aggregateDeviceRemoved
        var tapRemoved = initialReport.tapRemoved
        for _ in 0..<20 where !aggregateDeviceRemoved || !tapRemoved {
            try? await Task.sleep(for: .milliseconds(50))
            aggregateDeviceRemoved = Self.isUIDUnregistered(
                aggregateUID,
                selector: kAudioHardwarePropertyTranslateUIDToDevice
            )
            tapRemoved = Self.isUIDUnregistered(
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

nonisolated final class CoreAudioTapTimedStop: @unchecked Sendable {
    nonisolated struct Result: Sendable, Equatable {
        let status: OSStatus
        let elapsed: TimeInterval
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(
        label: "de.mcc.FlowDictate.core-audio-tap-timed-stop",
        qos: .userInteractive
    )
    private let stopAction: () -> OSStatus
    private var startedAtUptimeNanoseconds: UInt64 = 0
    private var timer: DispatchSourceTimer?
    private var continuation: CheckedContinuation<Result, Never>?
    private var result: Result?
    private var isStopping = false

    init(stopAction: @escaping () -> OSStatus) {
        self.stopAction = stopAction
    }

    func wait(for duration: TimeInterval) async -> Result {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(returning: result)
                    return
                }
                self.continuation = continuation
                startedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
                let timer = DispatchSource.makeTimerSource(queue: queue)
                self.timer = timer
                timer.setEventHandler { [weak self] in self?.stopNow() }
                timer.schedule(deadline: .now() + max(0, duration), leeway: .milliseconds(10))
                timer.resume()
                let shouldStopImmediately = Task.isCancelled
                lock.unlock()
                if shouldStopImmediately { stopNow() }
            }
        } onCancel: {
            stopNow()
        }
    }

    func stopNow() {
        lock.lock()
        guard result == nil, !isStopping else {
            lock.unlock()
            return
        }
        isStopping = true
        let startedAt = startedAtUptimeNanoseconds
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        lock.unlock()

        let stoppedAt = DispatchTime.now().uptimeNanoseconds
        let status = stopAction()
        let elapsed = startedAt == 0
            ? 0
            : TimeInterval(stoppedAt - startedAt) / 1_000_000_000
        let result = Result(status: status, elapsed: elapsed)

        lock.lock()
        self.result = result
        isStopping = false
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

nonisolated private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

nonisolated private final class CoreAudioTapCleanupCompletion: @unchecked Sendable {
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

nonisolated struct CoreAudioTapTimelineAnalyzer: Sendable, Equatable {
    private(set) var firstHostTime: UInt64?
    private(set) var lastHostTime: UInt64?
    private(set) var firstSampleTime: Double?
    private(set) var lastSampleTime: Double?
    private(set) var missingHostTimeCount = 0
    private(set) var missingSampleTimeCount = 0
    private(set) var hostTimeRegressionCount = 0
    private(set) var sampleTimeRegressionCount = 0
    private(set) var sampleDiscontinuityCount = 0
    private(set) var largestPositiveSampleGapFrames: Int64 = 0
    private(set) var largestHostTimeDeltaNanoseconds: UInt64 = 0

    private var previousFrameCount: Int64?

    mutating func record(hostTime: UInt64?, sampleTime: Double?, frameCount: Int64) {
        if let hostTime {
            firstHostTime = firstHostTime ?? hostTime
            if let previousHostTime = lastHostTime {
                if hostTime <= previousHostTime {
                    hostTimeRegressionCount += 1
                } else {
                    largestHostTimeDeltaNanoseconds = max(
                        largestHostTimeDeltaNanoseconds,
                        AudioConvertHostTimeToNanos(hostTime - previousHostTime)
                    )
                }
            }
            lastHostTime = hostTime
        } else {
            missingHostTimeCount += 1
        }

        if let sampleTime {
            firstSampleTime = firstSampleTime ?? sampleTime
            if let previousSampleTime = lastSampleTime,
               let previousFrameCount {
                if sampleTime < previousSampleTime { sampleTimeRegressionCount += 1 }
                let expectedSampleTime = previousSampleTime + Double(previousFrameCount)
                let delta = sampleTime - expectedSampleTime
                if abs(delta) > 0.5 {
                    sampleDiscontinuityCount += 1
                    if delta > 0.5 {
                        largestPositiveSampleGapFrames = max(
                            largestPositiveSampleGapFrames,
                            Int64(delta.rounded())
                        )
                    }
                }
            }
            lastSampleTime = sampleTime
            previousFrameCount = frameCount
        } else {
            missingSampleTimeCount += 1
        }
    }
}

nonisolated private final class CoreAudioTapProbeMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var callbackCount = 0
    private var nonSilentCallbackCount = 0
    private var frameCount: Int64 = 0
    private var sampleRate: Double = 0
    private var channelCount = 0
    private var timeline = CoreAudioTapTimelineAnalyzer()

    func record(
        inputData: UnsafePointer<AudioBufferList>,
        inputTime: UnsafePointer<AudioTimeStamp>,
        format: AudioStreamBasicDescription
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        let bytesPerFrame = Int(format.mBytesPerFrame)
        let observedFrames = buffers.first.map { buffer -> Int64 in
            guard bytesPerFrame > 0 else { return 0 }
            return Int64(Int(buffer.mDataByteSize) / bytesPerFrame)
        } ?? 0
        let containsNonZeroByte = buffers.contains { buffer in
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { return false }
            return UnsafeRawBufferPointer(
                start: data,
                count: Int(buffer.mDataByteSize)
            ).contains { $0 != 0 }
        }
        let hostTime = inputTime.pointee.mFlags.contains(.hostTimeValid)
            ? inputTime.pointee.mHostTime
            : nil
        let sampleTime = inputTime.pointee.mFlags.contains(.sampleTimeValid)
            ? inputTime.pointee.mSampleTime
            : nil

        lock.lock()
        callbackCount += 1
        if containsNonZeroByte { nonSilentCallbackCount += 1 }
        frameCount += observedFrames
        timeline.record(
            hostTime: hostTime,
            sampleTime: sampleTime,
            frameCount: observedFrames
        )
        sampleRate = format.mSampleRate
        channelCount = Int(format.mChannelsPerFrame)
        lock.unlock()
    }

    func report(
        requestedDuration: TimeInterval,
        wallDuration: TimeInterval,
        cleanup: CoreAudioTapCleanupReport
    ) -> CoreAudioTapProbeReport {
        lock.lock()
        defer { lock.unlock() }
        return CoreAudioTapProbeReport(
            requestedDuration: requestedDuration,
            wallDuration: wallDuration,
            callbackCount: callbackCount,
            nonSilentCallbackCount: nonSilentCallbackCount,
            frameCount: frameCount,
            sampleRate: sampleRate,
            channelCount: channelCount,
            firstHostTime: timeline.firstHostTime,
            lastHostTime: timeline.lastHostTime,
            firstSampleTime: timeline.firstSampleTime,
            lastSampleTime: timeline.lastSampleTime,
            missingHostTimeCount: timeline.missingHostTimeCount,
            missingSampleTimeCount: timeline.missingSampleTimeCount,
            hostTimeRegressionCount: timeline.hostTimeRegressionCount,
            sampleTimeRegressionCount: timeline.sampleTimeRegressionCount,
            sampleDiscontinuityCount: timeline.sampleDiscontinuityCount,
            largestPositiveSampleGapFrames: timeline.largestPositiveSampleGapFrames,
            largestHostTimeDeltaNanoseconds: timeline.largestHostTimeDeltaNanoseconds,
            cleanup: cleanup
        )
    }
}
