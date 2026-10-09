import Foundation

nonisolated enum MixedRecordingError: LocalizedError {
    case captureNotAvailable

    var errorDescription: String? {
        "Synchronized Microphone + System Audio capture is not available yet."
    }
}

nonisolated enum RecordingAudioSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case microphone
    case systemAudio
    case mixed

    static let systemAudioDurationGuidance =
        "For reliable transcription, keep recordings to about 15–20 minutes."

    static let systemAudioPreviewGuidance =
        "Live Preview is not available for System Audio. \(systemAudioDurationGuidance)"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .systemAudio: "System Audio"
        case .mixed: "Microphone + System Audio"
        }
    }

    var shortTitle: String {
        switch self {
        case .microphone: "Microphone"
        case .systemAudio: "System Audio"
        case .mixed: "Mixed"
        }
    }

    var symbolName: String {
        switch self {
        case .microphone: "mic.fill"
        case .systemAudio: "speaker.wave.2.fill"
        case .mixed: "waveform"
        }
    }

    var explanation: String {
        switch self {
        case .microphone:
            "Records your selected microphone."
        case .systemAudio:
            "Records the digital audio played by apps on this Mac. No video is saved. \(Self.systemAudioDurationGuidance)"
        case .mixed:
            "Records microphone and system audio as separate, recoverable tracks on one timeline."
        }
    }
}

nonisolated struct AudioSourceMetadata: Codable, Sendable, Equatable {
    var source: RecordingAudioSource
    var sampleRate: Double
    var channelCount: Int

    static let microphoneDefault = AudioSourceMetadata(
        source: .microphone,
        sampleRate: 0,
        channelCount: 0
    )
}
