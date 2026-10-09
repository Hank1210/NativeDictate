import Foundation

/// Adapts a meeting track to FlowDictate's existing single-file and long-form
/// transcription pipeline without adding synthetic rows to the user's History.
@MainActor
final class LongFormTrackTranscriptionExecutor: TrackTranscriptionExecuting {
    typealias ProviderResolver = @MainActor @Sendable (
        TrackTranscriptionRequest
    ) async throws -> any TranscriptionProvider

    private let providerResolver: ProviderResolver
    private let maximumAttempts: Int
    private let longFormConfiguration: LongFormConfiguration
    private let now: @Sendable () -> Date

    init(
        maximumAttempts: Int = 3,
        longFormConfiguration: LongFormConfiguration = .default,
        now: @escaping @Sendable () -> Date = Date.init,
        providerResolver: @escaping ProviderResolver
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.longFormConfiguration = longFormConfiguration
        self.now = now
        self.providerResolver = providerResolver
    }

    nonisolated func transcribe(
        _ request: TrackTranscriptionRequest
    ) async throws -> TrackTranscriptionOutput {
        try await execute(request)
    }

    private func execute(
        _ request: TrackTranscriptionRequest
    ) async throws -> TrackTranscriptionOutput {
        let workflowDirectory = request.transcriptionDirectory.appendingPathComponent(
            "track-workflows",
            isDirectory: true
        )
        let historyStore = DictationHistoryStore(
            fileURL: workflowDirectory.appendingPathComponent("records.json")
        )
        let sessionStore = TranscriptionSessionStore(
            rootURL: workflowDirectory.appendingPathComponent("long-form", isDirectory: true)
        )

        if let completed = try await historyStore.record(id: request.transcriptionSessionID),
           completed.status == .transcribed,
           completed.originalTranscript != nil,
           (completed.originalTranscript?.trimmingCharacters(
               in: .whitespacesAndNewlines
           ).isEmpty == false || completed.transcriptionSegmentCount != nil) {
            let savedSegments = try await sessionStore.load(
                recordID: request.transcriptionSessionID
            )?.segments ?? []
            return try output(
                from: completed,
                role: request.role,
                durationMilliseconds: request.durationMilliseconds,
                timedUnits: LongFormTranscriptionRunner.timedUnits(from: savedSegments)
            )
        }

        guard let providerID = TranscriptionProviderID(rawValue: request.providerID) else {
            throw TranscriptionProviderError.providerUnavailable(
                reason: "The frozen meeting transcription provider is not supported."
            )
        }
        if providerID == .openAI {
            try NetworkPolicy(
                mode: request.privacyMode,
                cloudEnhancementEnabled: false
            ).requirePermission(for: .transcription)
        }

        let provider = try await providerResolver(request)
        let runner = TranscriptionRunner(
            historyStore: historyStore,
            sessionStore: sessionStore,
            longFormConfiguration: longFormConfiguration
        )
        let existing = try await historyStore.record(id: request.transcriptionSessionID)
        let record = existing ?? makeRecord(request)
        let completed = try await runner.run(
            record: record,
            audioURL: request.audioURL,
            language: request.language,
            maximumAttempts: maximumAttempts,
            provider: provider,
            allowsEmptyTranscript: true,
            retainCompletedLongFormSession: true
        )
        return try output(
            from: completed,
            role: request.role,
            durationMilliseconds: request.durationMilliseconds,
            timedUnits: runner.latestTimedUnits
        )
    }

    private func makeRecord(_ request: TrackTranscriptionRequest) -> DictationRecord {
        let endedAt = now()
        let duration = Double(request.durationMilliseconds) / 1_000
        return DictationRecord.newRecording(
            id: request.transcriptionSessionID,
            startedAt: endedAt.addingTimeInterval(-duration),
            endedAt: endedAt,
            duration: duration,
            status: .recorded,
            audioRelativePath: request.audioRelativePath,
            audioFileSize: request.byteCount,
            providerID: request.providerID,
            modelID: request.modelID,
            language: request.language,
            targetBundleIdentifier: nil,
            targetApplicationName: nil,
            sourceMetadata: AudioSourceMetadata(
                source: request.role == .localSpeaker ? .microphone : .systemAudio,
                sampleRate: request.sampleRate,
                channelCount: request.channelCount
            )
        )
    }

    private func output(
        from record: DictationRecord,
        role: RecordingTrackRole,
        durationMilliseconds: Int64? = nil,
        timedUnits: [TranscriptionTimedUnit] = []
    ) throws -> TrackTranscriptionOutput {
        guard let transcript = record.originalTranscript,
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || record.transcriptionSegmentCount != nil else {
            throw TrackTranscriptionRunnerError.invalidOutput(role)
        }
        let segmentCount = max(record.transcriptionSegmentCount ?? 1, 1)
        let completedSegmentCount = record.transcriptionSegmentCount == nil
            ? 1
            : record.completedTranscriptionSegmentCount
        let timedEntries: [TrackTranscriptEntry]?
        if let durationMilliseconds,
           !timedUnits.isEmpty {
            let valid = timedUnits.enumerated().compactMap { index, unit -> TrackTranscriptEntry? in
                guard unit.startMilliseconds >= 0,
                      unit.endMilliseconds > unit.startMilliseconds,
                      unit.endMilliseconds <= durationMilliseconds,
                      !unit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return TrackTranscriptEntry(
                    index: index,
                    startMilliseconds: unit.startMilliseconds,
                    endMilliseconds: unit.endMilliseconds,
                    text: unit.text,
                    precision: unit.precision
                )
            }
            timedEntries = valid.count == timedUnits.count ? valid : nil
        } else {
            timedEntries = nil
        }
        return TrackTranscriptionOutput(
            transcript: transcript,
            providerID: record.providerID,
            modelID: record.modelID,
            segmentCount: segmentCount,
            completedSegmentCount: completedSegmentCount,
            timedEntries: timedEntries,
            isSilent: transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }
}
