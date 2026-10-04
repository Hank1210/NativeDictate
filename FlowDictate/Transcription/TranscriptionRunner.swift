import Foundation
import OSLog

struct TranscriptionRunFailure: LocalizedError {
    let underlyingError: Error
    let record: DictationRecord

    var errorDescription: String? { underlyingError.localizedDescription }
}

struct TranscriptionPersistenceFailure: LocalizedError {
    let underlyingError: Error
    let record: DictationRecord

    var errorDescription: String? {
        "The recording was saved, but NativeDictate could not update its history: \(underlyingError.localizedDescription)"
    }
}

@MainActor
final class TranscriptionRunner {
    typealias Sleeper = @MainActor (Duration) async throws -> Void

    private let historyStore: DictationHistoryStore
    private let sleeper: Sleeper
    private let longFormRunner: LongFormTranscriptionRunner
    private(set) var latestTimedUnits: [TranscriptionTimedUnit] = []

    init(
        historyStore: DictationHistoryStore,
        sessionStore: TranscriptionSessionStore = TranscriptionSessionStore(),
        longFormConfiguration: LongFormConfiguration = .default,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.historyStore = historyStore
        self.sleeper = sleeper
        longFormRunner = LongFormTranscriptionRunner(
            historyStore: historyStore,
            sessionStore: sessionStore,
            configuration: longFormConfiguration,
            sleeper: sleeper
        )
    }

    func run(
        record: DictationRecord,
        audioURL: URL,
        language: String?,
        maximumAttempts: Int,
        provider: any TranscriptionProvider,
        allowsEmptyTranscript: Bool = false,
        retainCompletedLongFormSession: Bool = false,
        deferSuccessfulPersistence: Bool = false,
        progress: @escaping @MainActor (LongFormProgress) -> Void = { _ in }
    ) async throws -> DictationRecord {
        latestTimedUnits = []
        if let result = try await longFormRunner.runIfNeeded(
            record: record,
            audioURL: audioURL,
            language: language,
            maximumAttempts: maximumAttempts,
            provider: provider,
            allowsEmptyTranscript: allowsEmptyTranscript,
            retainCompletedSession: retainCompletedLongFormSession,
            progress: progress
        ) {
            latestTimedUnits = longFormRunner.latestTimedUnits
            return result
        }
        var updated = record
        if allowsEmptyTranscript,
           (try? await SilentAudioSegmentDetector().isSilent(in: audioURL)) == true {
            try Task.checkCancellation()
            updated.status = .transcribed
            updated.originalTranscript = ""
            updated.finalText = ""
            updated.transcriptionSegmentCount = 1
            updated.completedTranscriptionSegmentCount = 1
            updated.errorCategory = nil
            updated.errorCode = nil
            updated.errorMessage = nil
            updated.updatedAt = Date()
            try await store(updated, persistToDisk: !deferSuccessfulPersistence)
            FlowLogger.transcription.info(
                "Verified silent short meeting track; provider request skipped"
            )
            return updated
        }
        let maximumAttempts = max(maximumAttempts, 1)

        for attempt in 1...maximumAttempts {
            updated.status = .transcribing
            updated.attemptCount += 1
            updated.lastAttemptAt = Date()
            updated.updatedAt = Date()
            try await store(updated, persistToDisk: !deferSuccessfulPersistence)

            let result: TranscriptionResult
            do {
                result = try await provider.transcribe(
                    TranscriptionRequest(audioURL: audioURL, language: language)
                )
            } catch {
                let shouldRetry = attempt < maximumAttempts
                    && DictationFailureClassifier.isRetryable(error)
                if shouldRetry {
                    try await sleeper(attempt == 1 ? .milliseconds(500) : .milliseconds(1_500))
                    continue
                }

                updated.status = .transcriptionFailed
                updated.errorCategory = DictationFailureClassifier.category(for: error)
                updated.errorMessage = error.localizedDescription
                updated.updatedAt = Date()
                do {
                    try await historyStore.upsert(updated)
                } catch {
                    FlowLogger.app.error(
                        "Could not persist transcription failure: \(error.localizedDescription, privacy: .public)"
                    )
                }
                throw TranscriptionRunFailure(underlyingError: error, record: updated)
            }

            latestTimedUnits = result.timedUnits
            updated.status = .transcribed
            updated.originalTranscript = result.text
            updated.finalText = result.text
            updated.providerID = result.provider
            updated.modelID = result.model
            updated.errorCategory = nil
            updated.errorCode = nil
            updated.errorMessage = nil
            updated.updatedAt = Date()
            try await store(updated, persistToDisk: !deferSuccessfulPersistence)
            return updated
        }

        preconditionFailure("At least one transcription attempt must run")
    }

    func recoverInterruptedLongFormSessions() async {
        await longFormRunner.recoverInterruptedSessions()
    }

    func deleteLongFormSession(recordID: UUID) async {
        await longFormRunner.deleteSession(recordID: recordID)
    }

    private func persist(_ record: DictationRecord) async throws {
        do {
            try await historyStore.upsert(record)
        } catch {
            throw TranscriptionPersistenceFailure(underlyingError: error, record: record)
        }
    }

    private func store(_ record: DictationRecord, persistToDisk: Bool) async throws {
        guard !persistToDisk else {
            try await persist(record)
            return
        }
        do { try await historyStore.stage(record) }
        catch { throw TranscriptionPersistenceFailure(underlyingError: error, record: record) }
    }
}
