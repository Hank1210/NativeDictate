import Foundation

enum DictationState: Equatable {
    case idle
    case recording
    case finalizing
    case transcribing
    case enhancing
    case inserting
    case success
    case failed(message: String, retainedAudioURL: URL?)

    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .recording:
            "Recording"
        case .finalizing:
            "Finalizing recording"
        case .transcribing:
            "Transcribing"
        case .enhancing:
            "Improving text"
        case .inserting:
            "Inserting"
        case .success:
            "Inserted"
        case let .failed(message, _):
            "Error: \(message)"
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            "waveform"
        case .recording:
            "record.circle.fill"
        case .finalizing, .transcribing, .enhancing, .inserting:
            "ellipsis.circle"
        case .success:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var acceptsStart: Bool {
        switch self {
        case .idle, .success, .failed:
            true
        case .recording, .finalizing, .transcribing, .enhancing, .inserting:
            false
        }
    }
}
