import Foundation

enum DictationRecordStatus: String, Codable, CaseIterable, Sendable {
    case recorded
    case transcribing
    case transcriptionFailed
    case transcribed
    case inserting
    case insertionFailed
    case insertionUnknown
    case completed
    case cancelled
    case recovered
    case audioMissing
    case audioCorrupt

    nonisolated var title: String {
        switch self {
        case .recorded: "Recorded"
        case .transcribing: "Transcribing"
        case .transcriptionFailed: "Transcription failed"
        case .transcribed: "Transcribed"
        case .inserting: "Inserting"
        case .insertionFailed: "Insertion failed"
        case .insertionUnknown: "Insertion needs review"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .recovered: "Recovered"
        case .audioMissing: "Audio missing"
        case .audioCorrupt: "Audio damaged"
        }
    }

    nonisolated var symbolName: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .transcribing, .inserting: "ellipsis.circle"
        case .recorded, .transcribed: "clock.circle"
        case .cancelled: "xmark.circle"
        case .recovered: "lifepreserver"
        case .transcriptionFailed, .insertionFailed, .insertionUnknown, .audioMissing, .audioCorrupt:
            "exclamationmark.triangle.fill"
        }
    }
}

extension DictationRecord {
    func withSmartConfiguration(
        writingStyleID: UUID,
        spokenFormattingEnabled: Bool
    ) -> Self {
        var copy = self
        copy.writingStyleID = writingStyleID
        copy.spokenFormattingEnabled = spokenFormattingEnabled
        return copy
    }
}


enum DictationErrorCategory: String, Codable, Sendable {
    case configuration
    case credentialMissing
    case authentication
    case permission
    case storageUnavailable
    case storageFull
    case audioDevice
    case audioCorrupt
    case systemAudioPermission
    case systemAudioUnavailable
    case systemAudioInterrupted
    case network
    case timeout
    case rateLimit
    case providerTemporary
    case providerPermanent
    case providerUnavailable
    case localModelMissing
    case localModelCorrupt
    case unsupportedLanguage
    case localInitialization
    case networkBlocked
    case insertion
    case directInsertionUnsupported
    case directInsertionUnknown
    case clipboardConflict
    case interrupted
    case transcriptionPreflight
    case insufficientWorkingStorage
    case segmentPlanning
    case segmentExport
    case segmentValidation
    case segmentTranscription
    case transcriptMerge
    case sessionPersistence
    case sourceChanged
    case unknown
}

nonisolated struct DictationRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var recordingStartedAt: Date
    var recordingEndedAt: Date
    var duration: TimeInterval
    var status: DictationRecordStatus
    var audioRelativePath: String
    var audioFileSize: Int64
    var audioSource: RecordingAudioSource = .microphone
    var audioSampleRate: Double = 0
    var audioChannelCount: Int = 0
    var meetingSummary: MeetingHistorySummary? = nil
    var originalTranscript: String?
    var correctedTranscript: String? = nil
    var correctionSummary: CorrectionSummary? = nil
    var formattedTranscript: String? = nil
    var dictionaryTranscript: String? = nil
    var finalText: String?
    var writingStyleID: UUID? = BuiltInWritingStyles.originalID
    var processingStatus: SmartProcessingStatus = .notStarted
    var enhancementProviderID: String? = nil
    var enhancementModelID: String? = nil
    var enhancementAttemptCount: Int = 0
    var enhancementErrorCategory: DictationErrorCategory? = nil
    var enhancementErrorMessage: String? = nil
    var enhancementFallback: SmartDictationFallback? = nil
    var dictionaryReplacementCount: Int = 0
    var spokenFormattingEnabled: Bool = false
    var providerID: String
    var modelID: String
    var language: String?
    var targetBundleIdentifier: String?
    var targetApplicationName: String?
    var attemptCount: Int
    var lastAttemptAt: Date?
    var errorCategory: DictationErrorCategory?
    var errorCode: String?
    var errorMessage: String?
    var transcriptionSessionID: UUID? = nil
    var transcriptionSegmentCount: Int? = nil
    var completedTranscriptionSegmentCount: Int = 0
    var hasPartialTranscript: Bool = false
    var partialTranscript: String? = nil
    var jobID: UUID? = nil
    var jobStatus: DictationJobStatus? = nil
    var queueSequence: Int64? = nil
    var cancelled: Bool
    var updatedAt: Date
    var schemaVersion: Int
    var archivedAt: Date?

    nonisolated var previewText: String {
        let text = finalText ?? originalTranscript
        return text?.isEmpty == false ? text! : status.title
    }

    nonisolated var canRetry: Bool {
        [.recorded, .transcriptionFailed, .recovered].contains(status)
    }

    nonisolated var canInsert: Bool {
        guard let finalText else { return false }
        return !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated var canRetryEnhancement: Bool {
        processingStatus == .enhancementFailed
            && dictionaryTranscript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && writingStyleID != nil
            && writingStyleID != BuiltInWritingStyles.originalID
    }

    nonisolated var isAutomaticallyProtected: Bool {
        if let meetingSummary {
            return meetingSummary.isAutomaticallyProtected
        }
        if let jobStatus,
           ![DictationJobStatus.completed, .cancelled, .insertionDeferred].contains(jobStatus) {
            return true
        }
        if transcriptionSessionID != nil || hasPartialTranscript {
            return true
        }
        if processingStatus == .enhancing || processingStatus == .enhancementFailed {
            return true
        }
        return switch status {
        case .transcriptionFailed, .insertionFailed, .insertionUnknown, .recovered,
             .audioMissing, .audioCorrupt, .transcribing, .inserting:
            true
        default:
            false
        }
    }

    nonisolated static func newRecording(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        status: DictationRecordStatus,
        audioRelativePath: String,
        audioFileSize: Int64,
        providerID: String,
        modelID: String,
        language: String?,
        targetBundleIdentifier: String?,
        targetApplicationName: String?,
        sourceMetadata: AudioSourceMetadata = .microphoneDefault
    ) -> Self {
        Self(
            id: id,
            createdAt: endedAt,
            recordingStartedAt: startedAt,
            recordingEndedAt: endedAt,
            duration: duration,
            status: status,
            audioRelativePath: audioRelativePath,
            audioFileSize: audioFileSize,
            audioSource: sourceMetadata.source,
            audioSampleRate: sourceMetadata.sampleRate,
            audioChannelCount: sourceMetadata.channelCount,
            originalTranscript: nil,
            finalText: nil,
            providerID: providerID,
            modelID: modelID,
            language: language,
            targetBundleIdentifier: targetBundleIdentifier,
            targetApplicationName: targetApplicationName,
            attemptCount: 0,
            lastAttemptAt: nil,
            errorCategory: nil,
            errorCode: nil,
            errorMessage: nil,
            cancelled: status == .cancelled,
            updatedAt: endedAt,
            schemaVersion: NativeDictateVersion.dictationRecordSchema,
            archivedAt: nil
        )
    }

    nonisolated static func recoveredAudio(
        id: UUID = UUID(),
        relativePath: String,
        fileSize: Int64,
        message: String,
        now: Date = Date()
    ) -> Self {
        var record = newRecording(
            id: id,
            startedAt: now,
            endedAt: now,
            duration: 0,
            status: .recovered,
            audioRelativePath: relativePath,
            audioFileSize: fileSize,
            providerID: "",
            modelID: "",
            language: nil,
            targetBundleIdentifier: nil,
            targetApplicationName: nil
        )
        record.errorCategory = .interrupted
        record.errorMessage = message
        return record
    }

    nonisolated static func migratedLegacyRecording(
        id: UUID = UUID(),
        relativePath: String,
        fileSize: Int64,
        now: Date = Date()
    ) -> Self {
        recoveredAudio(
            id: id,
            relativePath: relativePath,
            fileSize: fileSize,
            message: "Recovered from the Phase 1 recordings folder.",
            now: now
        )
    }
}

extension DictationRecord {
    private enum CodingKeys: String, CodingKey {
        case id, createdAt, recordingStartedAt, recordingEndedAt, duration, status
        case audioRelativePath, audioFileSize, audioSource, audioSampleRate, audioChannelCount
        case meetingSummary
        case originalTranscript, correctedTranscript, correctionSummary, formattedTranscript
        case dictionaryTranscript, finalText, writingStyleID, processingStatus
        case enhancementProviderID, enhancementModelID, enhancementAttemptCount
        case enhancementErrorCategory, enhancementErrorMessage, dictionaryReplacementCount
        case enhancementFallback, spokenFormattingEnabled, providerID, modelID, language
        case targetBundleIdentifier, targetApplicationName, attemptCount, lastAttemptAt
        case errorCategory, errorCode, errorMessage, transcriptionSessionID
        case transcriptionSegmentCount, completedTranscriptionSegmentCount
        case hasPartialTranscript, partialTranscript
        case jobID, jobStatus, queueSequence
        case cancelled, updatedAt, schemaVersion, archivedAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        recordingStartedAt = try values.decode(Date.self, forKey: .recordingStartedAt)
        recordingEndedAt = try values.decode(Date.self, forKey: .recordingEndedAt)
        duration = try values.decode(TimeInterval.self, forKey: .duration)
        status = try values.decode(DictationRecordStatus.self, forKey: .status)
        audioRelativePath = try values.decode(String.self, forKey: .audioRelativePath)
        audioFileSize = try values.decode(Int64.self, forKey: .audioFileSize)
        audioSource = try values.decodeIfPresent(RecordingAudioSource.self, forKey: .audioSource)
            ?? .microphone
        audioSampleRate = try values.decodeIfPresent(Double.self, forKey: .audioSampleRate) ?? 0
        audioChannelCount = try values.decodeIfPresent(Int.self, forKey: .audioChannelCount) ?? 0
        meetingSummary = try values.decodeIfPresent(
            MeetingHistorySummary.self,
            forKey: .meetingSummary
        )?.validated()
        originalTranscript = try values.decodeIfPresent(String.self, forKey: .originalTranscript)
        correctedTranscript = try values.decodeIfPresent(String.self, forKey: .correctedTranscript)
        correctionSummary = try values.decodeIfPresent(CorrectionSummary.self, forKey: .correctionSummary)
        formattedTranscript = try values.decodeIfPresent(String.self, forKey: .formattedTranscript)
        dictionaryTranscript = try values.decodeIfPresent(String.self, forKey: .dictionaryTranscript)
        finalText = try values.decodeIfPresent(String.self, forKey: .finalText)
        writingStyleID = try values.decodeIfPresent(UUID.self, forKey: .writingStyleID)
            ?? BuiltInWritingStyles.originalID
        let inferredStatus: SmartProcessingStatus = originalTranscript == nil ? .notStarted : .completed
        processingStatus = try values.decodeIfPresent(SmartProcessingStatus.self, forKey: .processingStatus)
            ?? inferredStatus
        enhancementProviderID = try values.decodeIfPresent(String.self, forKey: .enhancementProviderID)
        enhancementModelID = try values.decodeIfPresent(String.self, forKey: .enhancementModelID)
        enhancementAttemptCount = try values.decodeIfPresent(Int.self, forKey: .enhancementAttemptCount) ?? 0
        enhancementErrorCategory = try values.decodeIfPresent(DictationErrorCategory.self, forKey: .enhancementErrorCategory)
        enhancementErrorMessage = try values.decodeIfPresent(String.self, forKey: .enhancementErrorMessage)
        enhancementFallback = try values.decodeIfPresent(SmartDictationFallback.self, forKey: .enhancementFallback)
        dictionaryReplacementCount = try values.decodeIfPresent(Int.self, forKey: .dictionaryReplacementCount) ?? 0
        spokenFormattingEnabled = try values.decodeIfPresent(Bool.self, forKey: .spokenFormattingEnabled) ?? false
        providerID = try values.decode(String.self, forKey: .providerID)
        modelID = try values.decode(String.self, forKey: .modelID)
        language = try values.decodeIfPresent(String.self, forKey: .language)
        targetBundleIdentifier = try values.decodeIfPresent(String.self, forKey: .targetBundleIdentifier)
        targetApplicationName = try values.decodeIfPresent(String.self, forKey: .targetApplicationName)
        attemptCount = try values.decode(Int.self, forKey: .attemptCount)
        lastAttemptAt = try values.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        errorCategory = try values.decodeIfPresent(DictationErrorCategory.self, forKey: .errorCategory)
        errorCode = try values.decodeIfPresent(String.self, forKey: .errorCode)
        errorMessage = try values.decodeIfPresent(String.self, forKey: .errorMessage)
        transcriptionSessionID = try values.decodeIfPresent(UUID.self, forKey: .transcriptionSessionID)
        transcriptionSegmentCount = try values.decodeIfPresent(Int.self, forKey: .transcriptionSegmentCount)
        completedTranscriptionSegmentCount = try values.decodeIfPresent(
            Int.self,
            forKey: .completedTranscriptionSegmentCount
        ) ?? 0
        hasPartialTranscript = try values.decodeIfPresent(Bool.self, forKey: .hasPartialTranscript) ?? false
        partialTranscript = try values.decodeIfPresent(String.self, forKey: .partialTranscript)
        jobID = try values.decodeIfPresent(UUID.self, forKey: .jobID)
        jobStatus = try values.decodeIfPresent(DictationJobStatus.self, forKey: .jobStatus)
        queueSequence = try values.decodeIfPresent(Int64.self, forKey: .queueSequence)
        cancelled = try values.decode(Bool.self, forKey: .cancelled)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        schemaVersion = NativeDictateVersion.dictationRecordSchema
        archivedAt = try values.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}
