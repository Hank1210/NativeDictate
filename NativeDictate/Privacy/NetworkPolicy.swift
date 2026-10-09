import Foundation

nonisolated enum PrivacyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case offline
    case localWithOptionalCloudEnhancement
    case cloudTranscription

    var id: String { rawValue }

    var title: String {
        switch self {
        case .offline: "Fully offline"
        case .localWithOptionalCloudEnhancement: "Local + optional OpenAI"
        case .cloudTranscription: "Cloud transcription"
        }
    }

    var detail: String {
        switch self {
        case .offline:
            "Blocks transcription, enhancement and update-check network requests."
        case .localWithOptionalCloudEnhancement:
            "Keeps recording audio on this Mac; explicitly enabled cloud writing styles may send text."
        case .cloudTranscription:
            "Allows the selected cloud provider to receive recording audio."
        }
    }
}

nonisolated enum NetworkPurpose: String, Sendable {
    case transcription
    case enhancement
    case credentialValidation
    case updateCheck
    case modelDownload
}

nonisolated struct NetworkPolicy: Sendable {
    let mode: PrivacyMode
    let cloudEnhancementEnabled: Bool

    func allows(_ purpose: NetworkPurpose) -> Bool {
        switch mode {
        case .offline:
            return false
        case .localWithOptionalCloudEnhancement:
            switch purpose {
            case .transcription, .credentialValidation:
                return false
            case .enhancement:
                return cloudEnhancementEnabled
            case .updateCheck, .modelDownload:
                return true
            }
        case .cloudTranscription:
            return true
        }
    }

    func requirePermission(for purpose: NetworkPurpose) throws {
        guard allows(purpose) else {
            throw TranscriptionProviderError.networkBlocked(purpose: purpose)
        }
    }
}
