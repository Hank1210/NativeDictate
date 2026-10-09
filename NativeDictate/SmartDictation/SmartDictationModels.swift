import Foundation

nonisolated enum SmartProcessingStatus: String, Codable, CaseIterable, Sendable {
    case notStarted
    case formatting
    case formatted
    case enhancing
    case enhanced
    case enhancementFailed
    case completed
}

nonisolated enum SmartDictationFallback: String, Codable, CaseIterable, Identifiable, Sendable {
    case ask
    case useLocallyProcessed
    case useOriginal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask after an error"
        case .useLocallyProcessed: "Use locally processed text"
        case .useOriginal: "Use original transcript"
        }
    }
}

nonisolated struct WritingStyleProfile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var instruction: String
    var isBuiltIn: Bool
    var isEnabled: Bool
    var schemaVersion: Int

    var usesAI: Bool { id != BuiltInWritingStyles.originalID }
}

nonisolated enum BuiltInWritingStyles {
    static let originalID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let cleanedID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let emailID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    static let bulletsID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    static let formalID = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
    static let casualID = UUID(uuidString: "00000000-0000-4000-8000-000000000006")!

    static let all: [WritingStyleProfile] = [
        WritingStyleProfile(
            id: originalID,
            name: "Original",
            instruction: "",
            isBuiltIn: true,
            isEnabled: true,
            schemaVersion: 1
        ),
        WritingStyleProfile(
            id: cleanedID,
            name: "Cleaned Up",
            instruction: "Remove filler words and obvious repetitions. Preserve the meaning, facts, names, numbers, URLs, tone, and user-requested line breaks or paragraphs.",
            isBuiltIn: true,
            isEnabled: true,
            schemaVersion: 1
        ),
        WritingStyleProfile(
            id: emailID,
            name: "Email",
            instruction: "Turn the transcript into a readable email with sensible paragraphs and a polite, neutral tone. Do not invent a greeting, recipient, subject or facts that were not spoken.",
            isBuiltIn: true,
            isEnabled: true,
            schemaVersion: 1
        ),
        WritingStyleProfile(
            id: bulletsID,
            name: "Bullet Points",
            instruction: "Structure the content as a concise bullet list. Preserve every material fact and do not add new information.",
            isBuiltIn: true,
            isEnabled: true,
            schemaVersion: 1
        ),
        WritingStyleProfile(
            id: formalID,
            name: "Formal",
            instruction: "Rewrite in clear professional language. Preserve meaning, names, numbers, URLs and all factual content.",
            isBuiltIn: true,
            isEnabled: true,
            schemaVersion: 1
        ),
        WritingStyleProfile(
            id: casualID,
            name: "Casual",
            instruction: "Rewrite in a natural conversational style suitable for a chat message. Preserve all facts and do not add information.",
            isBuiltIn: true,
            isEnabled: true,
            schemaVersion: 1
        )
    ]

    static func profile(id: UUID) -> WritingStyleProfile? {
        all.first { $0.id == id }
    }
}

nonisolated struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var spokenForm: String
    var replacement: String
    var language: String?
    var caseSensitive: Bool
    var matchWholeWordsOnly: Bool
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
}

nonisolated struct TextTransformationResult: Equatable, Sendable {
    let text: String
    let replacementCount: Int
}

nonisolated struct SmartDictationResult: Equatable, Sendable {
    let formattedTranscript: String
    let dictionaryTranscript: String
    let finalText: String
    let dictionaryReplacementCount: Int
    let enhancementProviderID: String?
    let enhancementModelID: String?
}

nonisolated enum SmartDictationValidationError: LocalizedError, Equatable {
    case emptyName
    case nameTooLong
    case emptyInstruction
    case instructionTooLong
    case emptyDictionaryValue
    case duplicateDictionaryEntry
    case invalidImport

    var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a style name."
        case .nameTooLong: "Style names can contain at most 60 characters."
        case .emptyInstruction: "Enter an instruction for this style."
        case .instructionTooLong: "Style instructions can contain at most 4,000 characters."
        case .emptyDictionaryValue: "Spoken form and replacement cannot be empty."
        case .duplicateDictionaryEntry: "An identical dictionary entry already exists."
        case .invalidImport: "The selected Smart Dictation file is invalid or unsupported."
        }
    }
}
