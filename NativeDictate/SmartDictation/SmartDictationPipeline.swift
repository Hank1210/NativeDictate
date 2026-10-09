import Foundation
import OSLog

struct SmartDictationRunFailure: LocalizedError {
    let underlyingError: Error
    let record: DictationRecord

    var errorDescription: String? { underlyingError.localizedDescription }
}

private nonisolated struct LocalSmartProcessingResult: Sendable {
    var formattedText: String
    var dictionaryResult: TextTransformationResult
    var formattingDuration: TimeInterval
    var dictionaryDuration: TimeInterval
}

private nonisolated struct EnhancementLayoutProtection: Sendable {
    var text: String
    var styleInstruction: String
    var protectedTerms: [String]
    var markers: [String: String]
}

@MainActor
final class SmartDictationPipeline {
    private let historyStore: DictationHistoryStore
    private let formatter: SpokenFormattingProcessor
    private let dictionaryProcessor: PersonalDictionaryProcessor

    init(
        historyStore: DictationHistoryStore,
        formatter: SpokenFormattingProcessor = SpokenFormattingProcessor(),
        dictionaryProcessor: PersonalDictionaryProcessor = PersonalDictionaryProcessor()
    ) {
        self.historyStore = historyStore
        self.formatter = formatter
        self.dictionaryProcessor = dictionaryProcessor
    }

    func run(
        record: DictationRecord,
        spokenFormattingEnabled: Bool,
        dictionaryEntries: [DictionaryEntry],
        style: WritingStyleProfile,
        enhancementModel: String,
        fallback: SmartDictationFallback,
        enhancer: (any TranscriptEnhancing)?,
        enhancementAllowed: Bool = true,
        deferSuccessfulPersistence: Bool = false
    ) async throws -> DictationRecord {
        guard let original = record.correctedTranscript ?? record.originalTranscript else {
            throw TranscriptEnhancementError.emptyInput
        }
        var updated = record
        updated.processingStatus = .formatting
        updated.spokenFormattingEnabled = spokenFormattingEnabled
        updated.writingStyleID = style.id
        updated.enhancementErrorCategory = nil
        updated.enhancementErrorMessage = nil
        updated.enhancementFallback = nil
        updated.updatedAt = Date()
        // A queued dictation retains its durable audio and recovery manifest.
        // Keep every intermediate text transformation in memory and write the
        // complete JSON History only once after insertion. Persisting each AI
        // stage rewrote the whole History several times and could accumulate a
        // long serial file-I/O backlog during one app session.
        let stageLocally = deferSuccessfulPersistence
        let initialStageStartedAt = Date()
        try await store(updated, persistToDisk: !stageLocally)
        NativeDictateLogger.transcription.info(
            "Smart Dictation initial History stage completed in \(Self.elapsedSeconds(since: initialStageStartedAt), privacy: .public)s"
        )

        let formatter = formatter
        let dictionaryProcessor = dictionaryProcessor
        let language = updated.language
        let localResult = await Task.detached(priority: .userInitiated) {
            let formattingStartedAt = Date()
            let formatted = spokenFormattingEnabled
                ? formatter.process(original, language: language).text
                : original
            let formattingDuration = Date().timeIntervalSince(formattingStartedAt)

            let dictionaryStartedAt = Date()
            let dictionaryResult = dictionaryProcessor.process(
                formatted,
                entries: dictionaryEntries,
                language: language
            )
            return LocalSmartProcessingResult(
                formattedText: formatted,
                dictionaryResult: dictionaryResult,
                formattingDuration: formattingDuration,
                dictionaryDuration: Date().timeIntervalSince(dictionaryStartedAt)
            )
        }.value
        NativeDictateLogger.transcription.info(
            "Spoken formatting completed in \(Self.formattedSeconds(localResult.formattingDuration), privacy: .public)s"
        )
        NativeDictateLogger.transcription.info(
            "Personal dictionary completed in \(Self.formattedSeconds(localResult.dictionaryDuration), privacy: .public)s"
        )
        updated.formattedTranscript = localResult.formattedText
        updated.dictionaryTranscript = localResult.dictionaryResult.text
        updated.dictionaryReplacementCount = localResult.dictionaryResult.replacementCount
        updated.processingStatus = .formatted
        updated.finalText = localResult.dictionaryResult.text
        updated.updatedAt = Date()
        let formattedStageStartedAt = Date()
        try await store(updated, persistToDisk: !stageLocally)
        NativeDictateLogger.transcription.info(
            "Smart Dictation formatted History stage completed in \(Self.elapsedSeconds(since: formattedStageStartedAt), privacy: .public)s"
        )

        guard style.usesAI else {
            updated.processingStatus = .completed
            updated.enhancementProviderID = nil
            updated.enhancementModelID = nil
            updated.updatedAt = Date()
            let completedStageStartedAt = Date()
            try await store(updated, persistToDisk: !stageLocally)
            NativeDictateLogger.transcription.info(
                "Smart Dictation completed History stage completed in \(Self.elapsedSeconds(since: completedStageStartedAt), privacy: .public)s"
            )
            return updated
        }
        guard enhancementAllowed else {
            updated.processingStatus = .completed
            updated.enhancementProviderID = nil
            updated.enhancementModelID = nil
            updated.enhancementErrorCategory = nil
            updated.enhancementErrorMessage = nil
            updated.enhancementFallback = .useLocallyProcessed
            updated.updatedAt = Date()
            let completedStageStartedAt = Date()
            try await store(updated, persistToDisk: !stageLocally)
            NativeDictateLogger.transcription.notice(
                "AI writing style skipped because cloud enhancement is not permitted; using locally processed text"
            )
            NativeDictateLogger.transcription.info(
                "Smart Dictation skipped-enhancement History stage completed in \(Self.elapsedSeconds(since: completedStageStartedAt), privacy: .public)s"
            )
            return updated
        }
        guard let enhancer else { throw TranscriptionProviderError.missingAPIKey }
        return try await enhance(
            record: updated,
            style: style,
            model: enhancementModel,
            fallback: fallback,
            dictionaryEntries: dictionaryEntries,
            enhancer: enhancer,
            persistToDisk: !deferSuccessfulPersistence
        )
    }

    func retryEnhancement(
        record: DictationRecord,
        style: WritingStyleProfile,
        model: String,
        fallback: SmartDictationFallback,
        dictionaryEntries: [DictionaryEntry],
        enhancer: any TranscriptEnhancing
    ) async throws -> DictationRecord {
        try await enhance(
            record: record,
            style: style,
            model: model,
            fallback: fallback,
            dictionaryEntries: dictionaryEntries,
            enhancer: enhancer
        )
    }

    func processWithStyle(
        record: DictationRecord,
        style: WritingStyleProfile,
        model: String,
        fallback: SmartDictationFallback,
        dictionaryEntries: [DictionaryEntry],
        enhancer: (any TranscriptEnhancing)?,
        enhancementAllowed: Bool = true
    ) async throws -> DictationRecord {
        guard let localText = record.dictionaryTranscript ?? record.formattedTranscript ?? record.originalTranscript else {
            throw TranscriptEnhancementError.emptyInput
        }
        var updated = record
        updated.writingStyleID = style.id
        updated.enhancementErrorCategory = nil
        updated.enhancementErrorMessage = nil
        updated.enhancementFallback = nil
        updated.updatedAt = Date()

        guard style.usesAI else {
            updated.finalText = localText
            updated.processingStatus = .completed
            updated.enhancementProviderID = nil
            updated.enhancementModelID = nil
            try await persist(updated)
            return updated
        }
        guard enhancementAllowed else {
            updated.finalText = localText
            updated.processingStatus = .completed
            updated.enhancementProviderID = nil
            updated.enhancementModelID = nil
            updated.enhancementErrorCategory = nil
            updated.enhancementErrorMessage = nil
            updated.enhancementFallback = .useLocallyProcessed
            try await persist(updated)
            return updated
        }
        guard let enhancer else { throw TranscriptionProviderError.missingAPIKey }
        try await persist(updated)
        return try await enhance(
            record: updated,
            style: style,
            model: model,
            fallback: fallback,
            dictionaryEntries: dictionaryEntries,
            enhancer: enhancer
        )
    }

    func recoverInterruptedLocalProcessing(
        record: DictationRecord,
        spokenFormattingEnabled: Bool,
        dictionaryEntries: [DictionaryEntry],
        intendedStyle: WritingStyleProfile
    ) async throws -> DictationRecord {
        var updated = try await run(
            record: record,
            spokenFormattingEnabled: spokenFormattingEnabled,
            dictionaryEntries: dictionaryEntries,
            style: BuiltInWritingStyles.all[0],
            enhancementModel: "",
            fallback: .ask,
            enhancer: nil
        )
        guard intendedStyle.usesAI else { return updated }
        updated.writingStyleID = intendedStyle.id
        updated.processingStatus = .enhancementFailed
        updated.enhancementErrorCategory = .interrupted
        updated.enhancementErrorMessage = "Local processing was recovered. AI enhancement was not restarted automatically."
        updated.enhancementFallback = .ask
        updated.updatedAt = Date()
        try await persist(updated)
        return updated
    }

    private func enhance(
        record: DictationRecord,
        style: WritingStyleProfile,
        model: String,
        fallback: SmartDictationFallback,
        dictionaryEntries: [DictionaryEntry],
        enhancer: any TranscriptEnhancing,
        persistToDisk: Bool = true
    ) async throws -> DictationRecord {
        guard let input = record.dictionaryTranscript ?? record.formattedTranscript ?? record.originalTranscript else {
            throw TranscriptEnhancementError.emptyInput
        }
        let layoutProtection = Self.protectLayoutForEnhancement(input: input, styleInstruction: style.instruction)
        var updated = record
        updated.processingStatus = .enhancing
        updated.enhancementAttemptCount += 1
        updated.enhancementModelID = model
        updated.enhancementErrorCategory = nil
        updated.enhancementErrorMessage = nil
        updated.updatedAt = Date()
        try await store(updated, persistToDisk: persistToDisk)

        do {
            let result = try await enhancer.enhance(
                TranscriptEnhancementRequest(
                    text: layoutProtection.text,
                    styleInstruction: layoutProtection.styleInstruction,
                    language: updated.language,
                    model: model,
                    protectedTerms: dictionaryEntries.filter(\.isEnabled).map(\.replacement)
                        + layoutProtection.protectedTerms
                )
            )
            let restoredText = try Self.restoreProtectedLayoutMarkers(
                in: result.text,
                markers: layoutProtection.markers
            )
            updated.finalText = try EnhancementResponseValidator().validate(
                output: restoredText,
                input: input,
                protectedTerms: dictionaryEntries.filter(\.isEnabled).map(\.replacement)
            )
            updated.processingStatus = .enhanced
            updated.enhancementProviderID = result.provider
            updated.enhancementModelID = result.model
            updated.updatedAt = Date()
            try await store(updated, persistToDisk: persistToDisk)
            updated.processingStatus = .completed
            updated.updatedAt = Date()
            try await store(updated, persistToDisk: persistToDisk)
            return updated
        } catch {
            updated.processingStatus = .enhancementFailed
            updated.enhancementErrorCategory = enhancementCategory(for: error)
            updated.enhancementErrorMessage = error.localizedDescription
            updated.enhancementFallback = fallback
            updated.updatedAt = Date()

            switch fallback {
            case .ask:
                try await store(updated, persistToDisk: persistToDisk)
                throw SmartDictationRunFailure(underlyingError: error, record: updated)
            case .useLocallyProcessed:
                updated.finalText = input
                updated.processingStatus = .completed
                try await store(updated, persistToDisk: persistToDisk)
                return updated
            case .useOriginal:
                updated.finalText = updated.originalTranscript
                updated.processingStatus = .completed
                try await store(updated, persistToDisk: persistToDisk)
                return updated
            }
        }
    }

    private func persist(_ record: DictationRecord) async throws {
        do { try await historyStore.upsert(record) }
        catch { throw TranscriptionPersistenceFailure(underlyingError: error, record: record) }
    }

    private func store(_ record: DictationRecord, persistToDisk: Bool) async throws {
        guard !persistToDisk else {
            try await persist(record)
            return
        }
        do { try await historyStore.stage(record) }
        catch { throw TranscriptionPersistenceFailure(underlyingError: error, record: record) }
    }

    private nonisolated static func elapsedSeconds(since date: Date) -> String {
        formattedSeconds(Date().timeIntervalSince(date))
    }

    private nonisolated static func formattedSeconds(_ interval: TimeInterval) -> String {
        String(format: "%.3f", interval)
    }

    private nonisolated static func protectLayoutForEnhancement(
        input: String,
        styleInstruction: String
    ) -> EnhancementLayoutProtection {
        guard input.contains("\n") else {
            return EnhancementLayoutProtection(
                text: input,
                styleInstruction: styleInstruction,
                protectedTerms: [],
                markers: [:]
            )
        }

        var text = input
        var markers: [String: String] = [:]
        guard let expression = try? NSRegularExpression(pattern: #"\n+"#) else {
            return EnhancementLayoutProtection(
                text: input,
                styleInstruction: styleInstruction,
                protectedTerms: [],
                markers: [:]
            )
        }

        let matches = expression.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed()
        for (index, match) in matches.enumerated() {
            guard let range = Range(match.range, in: text) else { continue }
            let marker = "[[NATIVEDICTATE_LAYOUT_BREAK_\(index + 1)]]"
            markers[marker] = String(text[range])
            text.replaceSubrange(range, with: " \(marker) ")
        }

        let instruction = """
        \(styleInstruction)

        Preserve every token that looks like [[NATIVEDICTATE_LAYOUT_BREAK_N]] exactly as written. These tokens mark user-requested line or paragraph breaks and must remain in their original order. Do not remove, rename, translate or add them.
        """

        return EnhancementLayoutProtection(
            text: text,
            styleInstruction: instruction,
            protectedTerms: Array(markers.keys),
            markers: markers
        )
    }

    private nonisolated static func restoreProtectedLayoutMarkers(
        in text: String,
        markers: [String: String]
    ) throws -> String {
        guard !markers.isEmpty else { return text }
        var result = text
        for marker in markers.keys.sorted(by: { $0.count > $1.count }) {
            guard let replacement = markers[marker] else { continue }
            guard result.localizedCaseInsensitiveContains(marker) else {
                throw TranscriptEnhancementError.implausibleResult(
                    "a protected layout marker is missing: \(marker)"
                )
            }
            let pattern = #"[ \t]*"# + NSRegularExpression.escapedPattern(for: marker) + #"[ \t]*"#
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                result = result.replacingOccurrences(of: marker, with: replacement)
                continue
            }
            result = expression.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func enhancementCategory(for error: Error) -> DictationErrorCategory {
        if let error = error as? TranscriptEnhancementError {
            switch error {
            case let .server(code, _):
                switch code {
                case 401, 403: return .authentication
                case 429: return .rateLimit
                case 500...599: return .providerTemporary
                default: return .providerPermanent
                }
            case .emptyInput, .emptyResult, .implausibleResult, .invalidResponse:
                return .providerPermanent
            }
        }
        return DictationFailureClassifier.category(for: error)
    }
}
