import Foundation

nonisolated enum DictationJobStatus: String, Codable, CaseIterable, Sendable {
    case queued
    case preparing
    case transcribing
    case correcting
    case formatting
    case enhancing
    case readyToInsert
    case inserting
    case completed
    case paused
    case failed
    case cancelled
    case insertionDeferred

    var isTerminal: Bool {
        [.completed, .failed, .cancelled, .insertionDeferred, .paused].contains(self)
    }
}

nonisolated struct PersistedDictationConfiguration: Codable, Equatable, Sendable {
    var providerID: TranscriptionProviderID
    var engineID: String
    var modelID: String
    var executionLocation: TranscriptionExecutionLocation
    var language: String?
    var writingStyleID: UUID
    var spokenFormattingEnabled: Bool
    var personalDictionaryEnabled: Bool
    var insertionPreference: InsertionPreference
    var privacyMode: PrivacyMode
    var cloudEnhancementEnabled: Bool
    var enhancementModel: String
    var enhancementFallback: SmartDictationFallback
    var profileID: UUID?
}

nonisolated struct CorrectionSummary: Codable, Equatable, Sendable {
    var appliedCount: Int
    var ignoredAmbiguousCount: Int
    var undoneCount: Int
}

nonisolated struct DictationJob: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var recordID: UUID
    var createdAt: Date
    var updatedAt: Date
    var queueSequence: Int64
    var audioRelativePath: String
    var audioSource: RecordingAudioSource
    var providerID: String
    var engineID: String
    var modelID: String
    var executionLocation: TranscriptionExecutionLocation
    var language: String?
    var targetBundleIdentifier: String?
    var targetApplicationName: String?
    var effectiveConfiguration: PersistedDictationConfiguration
    var status: DictationJobStatus
    var correctionSummary: CorrectionSummary?
    var insertionAttemptCount: Int
    var automaticInsertionCompleted: Bool
    var lastErrorCategory: DictationErrorCategory?
    var lastErrorMessage: String?
}

nonisolated struct DictationQueueSnapshot: Equatable, Sendable {
    var processingCount: Int
    var queuedCount: Int
    var reservationCount: Int

    var totalActiveCount: Int { processingCount + queuedCount + reservationCount }
}

nonisolated enum DictationQueueError: LocalizedError {
    case full(maximumWaiting: Int)
    case reservationMissing
    case jobNotCancellable
    case meetingProcessingBusy
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case let .full(maximumWaiting):
            "The processing queue is full (maximum \(maximumWaiting) waiting dictations). Wait for one job to finish."
        case .reservationMissing:
            "The recording could not be added because its queue reservation was lost. The audio was kept."
        case .jobNotCancellable:
            "This dictation has already started processing and can no longer be cancelled as a waiting job."
        case .meetingProcessingBusy:
            "Meeting processing is active or another dictation is waiting. Wait for it to finish before starting a new recording."
        case let .unsupportedSchema(schema):
            "A dictation job uses unsupported schema version \(schema)."
        }
    }
}
