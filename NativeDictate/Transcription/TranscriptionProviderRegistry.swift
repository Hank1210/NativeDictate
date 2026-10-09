import Foundation

nonisolated enum TranscriptionProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"
    case local = "local"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .local: "On this Mac"
        }
    }
}

nonisolated enum TranscriptionExecutionLocation: String, Codable, Sendable {
    case local
    case cloud
}

nonisolated enum AudioFormatRequirement: String, Codable, Sendable {
    case commonAudioFile
    case mono16kHzPCM
}

nonisolated struct TranscriptionProviderCapabilities: Codable, Equatable, Sendable {
    var providerID: String
    var engineID: String
    var executionLocation: TranscriptionExecutionLocation
    var requiresCredential: Bool
    var supportsPrompt: Bool
    var supportsTimestamps: Bool
    var supportsLongForm: Bool
    var supportedLanguages: Set<String>?
    var maximumInputBytes: Int64?
    var recommendedAudioFormat: AudioFormatRequirement
}

nonisolated struct TranscriptionProviderDescriptor: Codable, Equatable, Identifiable, Sendable {
    var id: TranscriptionProviderID
    var displayName: String
    var detail: String
    var capabilities: TranscriptionProviderCapabilities
}

nonisolated enum TranscriptionProviderAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var reason: String? {
        if case let .unavailable(reason) = self { return reason }
        return nil
    }
}

nonisolated struct TranscriptionProviderRegistry: Sendable {
    static let openAI = TranscriptionProviderDescriptor(
        id: .openAI,
        displayName: "OpenAI",
        detail: "Sends recording audio to OpenAI for transcription.",
        capabilities: TranscriptionProviderCapabilities(
            providerID: TranscriptionProviderID.openAI.rawValue,
            engineID: "openai-transcriptions",
            executionLocation: .cloud,
            requiresCredential: true,
            supportsPrompt: true,
            supportsTimestamps: false,
            supportsLongForm: true,
            supportedLanguages: nil,
            maximumInputBytes: OpenAITranscriptionProvider.maximumAudioFileBytes,
            recommendedAudioFormat: .commonAudioFile
        )
    )

    static let local = TranscriptionProviderDescriptor(
        id: .local,
        displayName: "Local · Parakeet v3",
        detail: "Runs locally on Apple Silicon. Recording audio does not leave this Mac.",
        capabilities: TranscriptionProviderCapabilities(
            providerID: TranscriptionProviderID.local.rawValue,
            engineID: "fluidaudio-parakeet-v3",
            executionLocation: .local,
            requiresCredential: false,
            supportsPrompt: false,
            supportsTimestamps: true,
            supportsLongForm: true,
            supportedLanguages: Set(LocalModelCatalog.parakeetV3.languages),
            maximumInputBytes: nil,
            recommendedAudioFormat: .mono16kHzPCM
        )
    )

    let descriptors: [TranscriptionProviderDescriptor]

    init(descriptors: [TranscriptionProviderDescriptor] = [Self.local, Self.openAI]) {
        self.descriptors = descriptors
    }

    func descriptor(for id: TranscriptionProviderID) -> TranscriptionProviderDescriptor? {
        descriptors.first { $0.id == id }
    }

    func availability(
        for id: TranscriptionProviderID,
        architecture: String = RuntimeArchitecture.current
    ) -> TranscriptionProviderAvailability {
        switch id {
        case .openAI:
            return .available
        case .local:
            guard architecture == "arm64" else {
                return .unavailable(reason: "Local transcription requires an Apple Silicon Mac.")
            }
            return .available
        }
    }
}

nonisolated enum RuntimeArchitecture {
    static var current: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}
