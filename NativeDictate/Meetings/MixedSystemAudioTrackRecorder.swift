import Foundation

/// Stable mixed-session facade that selects exactly one system-audio backend for
/// its lifetime. Core Audio is preferred from macOS 14.2; ScreenCaptureKit keeps
/// the supported macOS 14.0/14.1 compatibility path explicit.
actor SystemAudioTrackRecorder: MixedTrackRecording {
    nonisolated let role: RecordingTrackRole = .systemAudio
    nonisolated let backend: SystemAudioCaptureBackend

    private let implementation: any MixedTrackRecording

    init(
        version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) {
        let backend = SystemAudioCaptureStrategy.candidate(for: version).preferredBackend
        self.backend = backend
        implementation = switch backend {
        case .coreAudioTap:
            CoreAudioSystemTrackRecorder()
        case .screenCaptureKit:
            ScreenCaptureKitSystemTrackRecorder()
        }
    }

    func setLevelHandler(_ handler: MixedTrackLevelHandler?) async {
        await implementation.setLevelHandler(handler)
    }

    func setWarningHandler(_ handler: MixedTrackWarningHandler?) async {
        await implementation.setWarningHandler(handler)
    }

    func prepare(outputURL: URL) async throws {
        try await implementation.prepare(outputURL: outputURL)
    }

    func start(requestedHostTime: UInt64) async throws -> MixedTrackStartResult {
        try await implementation.start(requestedHostTime: requestedHostTime)
    }

    func stop() async throws -> MixedTrackCaptureResult {
        try await implementation.stop()
    }

    func cancel() async -> MixedTrackCaptureResult? {
        await implementation.cancel()
    }
}
