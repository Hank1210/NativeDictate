import Foundation

nonisolated enum SystemAudioPermissionReadiness: Sendable, Equatable {
    case authorized
    case requestRequired
    case verifiedWhenCaptureStarts

    var title: String {
        switch self {
        case .authorized:
            "Allowed"
        case .requestRequired:
            "Permission required"
        case .verifiedWhenCaptureStarts:
            "Checked when recording starts"
        }
    }

    var symbolName: String {
        switch self {
        case .authorized:
            "checkmark.circle.fill"
        case .requestRequired:
            "exclamationmark.circle"
        case .verifiedWhenCaptureStarts:
            "questionmark.circle"
        }
    }
}

nonisolated struct SystemAudioPermissionStatus: Sendable, Equatable {
    let backend: SystemAudioCaptureBackend
    let readiness: SystemAudioPermissionReadiness
    let settingsLabel: String

    var detail: String {
        switch (backend, readiness) {
        case (.coreAudioTap, .verifiedWhenCaptureStarts):
            "macOS asks for System Audio access when the first mixed recording starts. Apple provides no public API to check this permission beforehand."
        case (.coreAudioTap, .authorized):
            "System Audio access was verified by a successful audio-only capture during this app session."
        case (.coreAudioTap, .requestRequired):
            // This state is intentionally not produced by the resolver. Core Audio
            // doesn't expose a public preflight API that can support this claim.
            "System Audio access must be reviewed in System Settings."
        case (.screenCaptureKit, .authorized):
            "Screen & System Audio Recording access is allowed. NativeDictate registers only an audio output and saves no video."
        case (.screenCaptureKit, .requestRequired):
            "macOS will request Screen & System Audio Recording access when System Audio starts."
        case (.screenCaptureKit, .verifiedWhenCaptureStarts):
            "Screen & System Audio Recording access is checked when capture starts."
        }
    }

    static func resolve(
        for source: RecordingAudioSource,
        version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        screenCaptureAuthorized: Bool,
        coreAudioTapSucceededThisSession: Bool
    ) -> Self {
        let strategy = SystemAudioCaptureStrategy.candidate(for: version)
        let backend: SystemAudioCaptureBackend = source == .mixed
            ? strategy.preferredBackend
            : .screenCaptureKit
        switch backend {
        case .screenCaptureKit:
            return Self(
                backend: .screenCaptureKit,
                readiness: screenCaptureAuthorized ? .authorized : .requestRequired,
                settingsLabel: "Screen & System Audio Recording"
            )
        case .coreAudioTap:
            return Self(
                backend: .coreAudioTap,
                readiness: coreAudioTapSucceededThisSession
                    ? .authorized
                    : .verifiedWhenCaptureStarts,
                settingsLabel: "System Audio Recording Only"
            )
        }
    }
}
