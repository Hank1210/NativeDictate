import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import Speech

enum FlowPermissionError: LocalizedError {
    case microphoneDenied
    case eventPostingDenied
    case speechRecognitionDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required. Enable NativeDictate in System Settings → Privacy & Security → Microphone."
        case .eventPostingDenied:
            "Accessibility access is required to paste text. Enable NativeDictate in System Settings → Privacy & Security → Accessibility, then try again."
        case .speechRecognitionDenied:
            "Speech Recognition access is unavailable. Live Preview will stay off, but dictation still works."
        }
    }
}

@MainActor
protocol PermissionManaging {
    func ensureMicrophoneAccess() async throws
    func ensureEventPostingAccess() throws
    func requestSpeechRecognitionAccess() async -> SpeechPermissionState
    var hasMicrophoneAccess: Bool { get }
    var hasEventPostingAccess: Bool { get }
    var speechRecognitionStatus: SpeechPermissionState { get }
    func openMicrophoneSettings()
    func openAccessibilitySettings()
    func openSpeechRecognitionSettings()
}

struct PermissionManager: PermissionManaging {
    func ensureMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw FlowPermissionError.microphoneDenied
            }
        case .denied, .restricted:
            throw FlowPermissionError.microphoneDenied
        @unknown default:
            throw FlowPermissionError.microphoneDenied
        }
    }

    @MainActor
    func ensureEventPostingAccess() throws {
        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
            throw FlowPermissionError.eventPostingDenied
        }
    }

    var hasMicrophoneAccess: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var hasEventPostingAccess: Bool {
        CGPreflightPostEventAccess()
    }

    func requestSpeechRecognitionAccess() async -> SpeechPermissionState {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.speechState(status))
            }
        }
    }

    var speechRecognitionStatus: SpeechPermissionState {
        Self.speechState(SFSpeechRecognizer.authorizationStatus())
    }

    func openMicrophoneSettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    func openSpeechRecognitionSettings() {
        openPrivacySettings(anchor: "Privacy_SpeechRecognition")
    }

    private static func speechState(
        _ status: SFSpeechRecognizerAuthorizationStatus
    ) -> SpeechPermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
