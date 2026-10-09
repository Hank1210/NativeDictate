import Foundation
import OSLog
import os

@MainActor
final class LongFormTranscriptionRunner {
    typealias Sleeper = @MainActor (Duration) async throws -> Void
    typealias ProgressHandler = @MainActor (LongFormProgress) -> Void
    typealias CapacityProvider = @MainActor @Sendable (URL) throws -> Int64

    private let historyStore: DictationHistoryStore
    private let sessionStore: TranscriptionSessionStore
    private let inspector: AudioAssetInspector
    private let modeResolver: TranscriptionModeResolver
    private let planner: AudioSegmentPlanner
    private let boundaryDetector: SilenceBoundaryDetector
    private let silentSegmentDetector: SilentAudioSegmentDetector
    private let exporter: AudioSegmentExporter
    private let merger: PartialTranscriptMerger
    private let promptBuilder: TranscriptionPromptBuilder
    private let configuration: LongFormConfiguration
    private let sleeper: Sleeper
    private let capacityProvider: CapacityProvider?
    private(set) var latestTimedUnits: [TranscriptionTimedUnit] = []

    init(
        historyStore: DictationHistoryStore,
        sessionStore: TranscriptionSessionStore,
        configuration: LongFormConfiguration = .default,
        inspector: AudioAssetInspector = AudioAssetInspector(),
        boundaryDetector: SilenceBoundaryDetector = SilenceBoundaryDetector(),
        silentSegmentDetector: SilentAudioSegmentDetector = SilentAudioSegmentDetector(),
        capacityProvider: CapacityProvider? = nil,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.historyStore = historyStore
        self.sessionStore = sessionStore
        self.configuration = configuration
        self.inspector = inspector
        self.capacityProvider = capacityProvider
        modeResolver = TranscriptionModeResolver(configuration: configuration)
        planner = AudioSegmentPlanner(configuration: configuration)
        self.boundaryDetector = boundaryDetector
        self.silentSegmentDetector = silentSegmentDetector
        exporter = AudioSegmentExporter(configuration: configuration)
        merger = PartialTranscriptMerger()
        promptBuilder = TranscriptionPromptBuilder(characterLimit: configuration.promptCharacterLimit)
        self.sleeper = sleeper
    }

    /// Returns `nil` when the recording can safely use the existing single-file path.
    func runIfNeeded(
        record: DictationRecord,
        audioURL: URL,
        language: String?,
        maximumAttempts: Int,
        provider: any TranscriptionProvider,
        allowsEmptyTranscript: Bool = false,
        retainCompletedSession: Bool = false,
        progress: @escaping ProgressHandler
    ) async throws -> DictationRecord? {
        latestTimedUnits = []
        let existing = try await sessionStore.load(recordID: record.id)
        if existing == nil,
           record.duration <= Double(configuration.targetDurationMilliseconds) / 1_000,
           record.audioFileSize <= configuration.softUploadByteLimit {
            return nil
        }
        progress(.inspecting)
        let inspectionStarted = ContinuousClock.now
        let inspection = try await inspector.inspect(audioURL)
        NativeDictateLogger.transcription.info(
            "Long-form inspection completed in \(String(describing: inspectionStarted.duration(to: .now)), privacy: .public)"
        )
        let mode = modeResolver.mode(for: inspection, hasExistingSession: existing != nil)
        guard case .longForm = mode else { return nil }

        let currentFingerprint = try inspector.fingerprint(
            url: audioURL,
            relativePath: record.audioRelativePath,
            inspection: inspection
        )
        var manifest: TranscriptionSessionManifest
        var updated = record

        if var existing {
            guard sourceMatches(existing.source, currentFingerprint) else {
                throw await fail(
                    LongFormTranscriptionError.sourceChanged,
                    category: .sourceChanged,
                    record: updated,
                    manifest: &existing
                )
            }
            existing.normalizeInterruptedWork()
            manifest = existing
        } else {
            progress(.planning)
            let planningStarted = ContinuousClock.now
            let available = try availableCapacity(at: audioURL.deletingLastPathComponent())
            let required = modeResolver.requiredWorkingBytes(for: inspection)
            guard available >= required else {
                throw await failWithoutManifest(
                    LongFormTranscriptionError.insufficientWorkingStorage(
                        requiredBytes: required,
                        availableBytes: available
                    ),
                    category: .insufficientWorkingStorage,
                    record: updated
                )
            }
            let sourceURL = audioURL
            let detector = boundaryDetector
            let segments = try await planner.plan(
                durationMilliseconds: inspection.durationMilliseconds,
                boundaryResolver: { nominal, lower, upper in
                    try await detector.boundary(
                        in: sourceURL,
                        nominalMilliseconds: nominal,
                        lowerBoundMilliseconds: lower,
                        upperBoundMilliseconds: upper
                    )
                }
            )
            NativeDictateLogger.transcription.info(
                "Planned \(segments.count, privacy: .public) segments in \(String(describing: planningStarted.duration(to: .now)), privacy: .public)"
            )
            let now = Date()
            manifest = TranscriptionSessionManifest(
                schemaVersion: TranscriptionSessionManifest.currentSchemaVersion,
                id: UUID(),
                recordID: record.id,
                source: currentFingerprint,
                providerID: record.providerID,
                modelID: record.modelID,
                language: language,
                status: .ready,
                segments: segments,
                mergedTranscript: nil,
                mergeAlgorithmVersion: PartialTranscriptMerger.algorithmVersion,
                createdAt: now,
                updatedAt: now,
                lastErrorCategory: nil,
                lastErrorMessage: nil
            )
        }

        do {
            try await sessionStore.save(manifest)
            updateSummary(record: &updated, manifest: manifest)
            updated.status = .transcribing
            updated.errorCategory = nil
            updated.errorMessage = nil
            updated.updatedAt = Date()
            try await persist(updated)

            for index in manifest.segments.indices
                where ![.succeeded, .silent].contains(manifest.segments[index].status) {
                let segmentSignpost = NativeDictateLogger.transcriptionSignposter.beginInterval(
                    "Transcription Segment", id: .exclusive,
                    "record: \(record.id.uuidString, privacy: .public), index: \(index), total: \(manifest.segments.count)"
                )
                defer {
                    NativeDictateLogger.transcriptionSignposter.endInterval(
                        "Transcription Segment", segmentSignpost
                    )
                }
                try Task.checkCancellation()
                let available = try availableCapacity(at: audioURL.deletingLastPathComponent())
                let required = modeResolver.requiredWorkingBytes(for: inspection)
                guard available >= required else {
                    throw LongFormTranscriptionError.insufficientWorkingStorage(
                        requiredBytes: required,
                        availableBytes: available
                    )
                }
                let total = manifest.segments.count
                progress(.preparing(segment: index, total: total))
                manifest.status = .transcribing
                manifest.segments[index].status = .preparing
                manifest.segments[index].errorCategory = nil
                manifest.segments[index].errorMessage = nil
                manifest.updatedAt = Date()
                try await sessionStore.save(manifest)

                let workURL = try await sessionStore.workURL(recordID: record.id, segmentIndex: index)
                let exportStarted = ContinuousClock.now
                let byteCount = try await exporter.export(
                    sourceURL: audioURL,
                    segment: manifest.segments[index],
                    destinationURL: workURL
                )
                NativeDictateLogger.transcription.info(
                    "Exported segment \(index + 1, privacy: .public)/\(total, privacy: .public) in \(String(describing: exportStarted.duration(to: .now)), privacy: .public)"
                )
                manifest.segments[index].preparedRelativePath = workURL.lastPathComponent
                manifest.segments[index].preparedByteCount = byteCount
                manifest.segments[index].status = .ready
                manifest.updatedAt = Date()
                try await sessionStore.save(manifest)

                let attempts = max(maximumAttempts, 1)
                var result: TranscriptionResult?
                var verifiedSilent = false
                for attempt in 1...attempts {
                    try Task.checkCancellation()
                    progress(.transcribing(segment: index, total: total, attempt: attempt))
                    manifest.segments[index].status = .uploading
                    manifest.segments[index].attemptCount += 1
                    manifest.segments[index].lastAttemptAt = Date()
                    manifest.updatedAt = Date()
                    updated.attemptCount += 1
                    updated.lastAttemptAt = Date()
                    try await sessionStore.save(manifest)
                    try await persist(updated)
                    do {
                        let uploadStarted = ContinuousClock.now
                        let previous = index > 0 ? manifest.segments[index - 1].transcript : nil
                        result = try await provider.transcribe(
                            TranscriptionRequest(
                                audioURL: workURL,
                                language: language,
                                prompt: promptBuilder.prompt(previousTranscript: previous)
                            )
                        )
                        NativeDictateLogger.transcription.info(
                            "Transcribed segment \(index + 1, privacy: .public)/\(total, privacy: .public) in \(String(describing: uploadStarted.duration(to: .now)), privacy: .public)"
                        )
                        break
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        if let providerError = error as? TranscriptionProviderError,
                           case .emptyTranscript = providerError,
                           (try? await silentSegmentDetector.isSilent(
                            in: audioURL,
                            segment: manifest.segments[index]
                           )) == true {
                            try Task.checkCancellation()
                            manifest.segments[index].status = .silent
                            manifest.segments[index].transcript = nil
                            manifest.segments[index].timedUnits = nil
                            manifest.segments[index].errorCategory = nil
                            manifest.segments[index].errorMessage = nil
                            manifest.updatedAt = Date()
                            try await sessionStore.save(manifest)
                            await sessionStore.removeWorkFile(
                                recordID: record.id, segmentIndex: index
                            )
                            updateSummary(record: &updated, manifest: manifest)
                            updated.updatedAt = Date()
                            try await persist(updated)
                            NativeDictateLogger.transcription.info(
                                "Verified silent segment \(index + 1, privacy: .public)/\(total, privacy: .public)"
                            )
                            verifiedSilent = true
                            break
                        }
                        if Task.isCancelled { throw CancellationError() }
                        let retry = attempt < attempts && DictationFailureClassifier.isRetryable(error)
                        if retry {
                            try await sleeper(attempt == 1 ? .milliseconds(500) : .milliseconds(1_500))
                            continue
                        }
                        manifest.segments[index].status = .failed
                        manifest.segments[index].errorCategory = .segmentTranscription
                        manifest.segments[index].errorMessage = error.localizedDescription
                        throw error
                    }
                }

                if verifiedSilent { continue }
                guard let result else { throw LongFormTranscriptionError.invalidSessionState }
                manifest.segments[index].status = .succeeded
                manifest.segments[index].transcript = result.text
                manifest.segments[index].timedUnits = result.timedUnits
                manifest.segments[index].errorCategory = nil
                manifest.segments[index].errorMessage = nil
                manifest.providerID = result.provider
                manifest.modelID = result.model
                manifest.updatedAt = Date()
                try await sessionStore.save(manifest)
                NativeDictateLogger.transcriptionSignposter.emitEvent(
                    "Transcription Segment Persisted", id: .exclusive,
                    "index: \(index), bytes: \(byteCount), attempts: \(manifest.segments[index].attemptCount)"
                )
                await sessionStore.removeWorkFile(recordID: record.id, segmentIndex: index)

                updateSummary(record: &updated, manifest: manifest)
                updated.providerID = result.provider
                updated.modelID = result.model
                updated.updatedAt = Date()
                try await persist(updated)
            }

            progress(.merging(total: manifest.segments.count))
            let mergeStarted = ContinuousClock.now
            manifest.status = .merging
            manifest.updatedAt = Date()
            try await sessionStore.save(manifest)
            let text = try merger.merge(manifest.segments)
            guard allowsEmptyTranscript || !text.isEmpty else {
                throw LongFormTranscriptionError.transcriptMergeFailed
            }
            NativeDictateLogger.transcription.info(
                "Merged \(manifest.segments.count, privacy: .public) segments in \(String(describing: mergeStarted.duration(to: .now)), privacy: .public)"
            )
            manifest.mergedTranscript = text
            manifest.status = .completed
            manifest.lastErrorCategory = nil
            manifest.lastErrorMessage = nil
            manifest.updatedAt = Date()
            try await sessionStore.save(manifest)

            updated.status = .transcribed
            updated.originalTranscript = text
            updated.finalText = text
            updated.transcriptionSessionID = nil
            updated.transcriptionSegmentCount = manifest.segments.count
            updated.completedTranscriptionSegmentCount = manifest.segments.count
            updated.hasPartialTranscript = false
            updated.partialTranscript = nil
            updated.errorCategory = nil
            updated.errorCode = nil
            updated.errorMessage = nil
            updated.updatedAt = Date()
            try await persist(updated)
            latestTimedUnits = Self.timedUnits(from: manifest.segments)
            if !retainCompletedSession {
                try await sessionStore.delete(recordID: record.id)
            }
            return updated
        } catch is CancellationError {
            manifest.normalizeInterruptedWork()
            manifest.status = .paused
            try? await sessionStore.save(manifest)
            updateSummary(record: &updated, manifest: manifest)
            updated.status = .transcriptionFailed
            updated.errorCategory = .interrupted
            updated.errorMessage = "Long-form transcription was paused. Continue it from History."
            updated.updatedAt = Date()
            try? await historyStore.upsert(updated)
            progress(.paused(completed: manifest.completedSegmentCount, total: manifest.segments.count))
            throw TranscriptionRunFailure(underlyingError: CancellationError(), record: updated)
        } catch let failure as TranscriptionRunFailure {
            throw failure
        } catch {
            manifest.status = .failed
            manifest.lastErrorCategory = category(for: error)
            manifest.lastErrorMessage = error.localizedDescription
            manifest.updatedAt = Date()
            try? await sessionStore.save(manifest)
            updateSummary(record: &updated, manifest: manifest)
            updated.status = .transcriptionFailed
            updated.errorCategory = category(for: error)
            updated.errorMessage = error.localizedDescription
            updated.updatedAt = Date()
            try? await historyStore.upsert(updated)
            throw TranscriptionRunFailure(underlyingError: error, record: updated)
        }
    }

    /// Convert provider-relative timing into the original track's clock. If a
    /// provider has no word timing, retain the real segment interval rather
    /// than pretending its entire track is one simultaneous utterance.
    static func timedUnits(from segments: [TranscriptionSegment]) -> [TranscriptionTimedUnit] {
        var result: [TranscriptionTimedUnit] = []
        for segment in segments where segment.status == .succeeded {
            let duration = segment.durationMilliseconds
            let units = segment.timedUnits ?? []
            let validUnits = units.compactMap { unit -> TranscriptionTimedUnit? in
                guard !unit.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      unit.startMilliseconds >= 0,
                      unit.startMilliseconds < duration,
                      unit.endMilliseconds > unit.startMilliseconds,
                      unit.endMilliseconds <= duration + 250 else { return nil }
                return TranscriptionTimedUnit(
                    text: unit.text,
                    startMilliseconds: unit.startMilliseconds,
                    // The provider can round its final word slightly past
                    // the exported file's measured end (47 ms in the real
                    // 120-minute session). Never extend the original track.
                    endMilliseconds: min(unit.endMilliseconds, duration),
                    precision: unit.precision
                )
            }
            if !validUnits.isEmpty {
                result.append(contentsOf: validUnits.compactMap { unit in
                    // A word that begins inside the overlap can extend past
                    // the logical boundary and sort before the preceding
                    // segment's final word. Keep only words beginning on the
                    // new side of that boundary.
                    guard unit.startMilliseconds >= segment.overlapBeforeMilliseconds else {
                        return nil
                    }
                    return TranscriptionTimedUnit(
                        text: unit.text,
                        startMilliseconds: segment.startMilliseconds + unit.startMilliseconds,
                        endMilliseconds: segment.startMilliseconds + unit.endMilliseconds,
                        precision: unit.precision
                    )
                })
            } else if let text = segment.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty {
                result.append(TranscriptionTimedUnit(
                    text: text,
                    startMilliseconds: segment.startMilliseconds
                        + segment.overlapBeforeMilliseconds,
                    endMilliseconds: segment.endMilliseconds,
                    precision: .segment
                ))
            }
        }
        return result
    }

    func recoverInterruptedSessions() async {
        do {
            let manifests = try await sessionStore.normalizeInterruptedSessions()
            for manifest in manifests {
                guard var record = try await historyStore.record(id: manifest.recordID) else { continue }
                updateSummary(record: &record, manifest: manifest)
                record.status = .transcriptionFailed
                record.errorCategory = .interrupted
                record.errorMessage = "Long-form transcription can be continued from History."
                record.updatedAt = Date()
                try await historyStore.upsert(record)
            }
        } catch {
            NativeDictateLogger.app.error("Long-form session recovery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteSession(recordID: UUID) async {
        try? await sessionStore.delete(recordID: recordID)
    }

    private func updateSummary(record: inout DictationRecord, manifest: TranscriptionSessionManifest) {
        record.transcriptionSessionID = manifest.id
        record.transcriptionSegmentCount = manifest.segments.count
        record.completedTranscriptionSegmentCount = manifest.completedSegmentCount
        record.partialTranscript = manifest.partialTranscript
        record.hasPartialTranscript = manifest.partialTranscript != nil
    }

    private func sourceMatches(
        _ saved: TranscriptionSourceFingerprint,
        _ current: TranscriptionSourceFingerprint
    ) -> Bool {
        let modificationMatches: Bool
        switch (saved.modificationDate, current.modificationDate) {
        case (nil, nil): modificationMatches = true
        case let (saved?, current?): modificationMatches = abs(saved.timeIntervalSince(current)) < 1.1
        default: modificationMatches = false
        }
        return saved.audioRelativePath == current.audioRelativePath
            && saved.byteCount == current.byteCount
            && abs(saved.durationMilliseconds - current.durationMilliseconds) <= 10
            && modificationMatches
    }

    private func category(for error: Error) -> DictationErrorCategory {
        switch error {
        case LongFormTranscriptionError.insufficientWorkingStorage:
            .insufficientWorkingStorage
        case LongFormTranscriptionError.invalidSegmentPlan:
            .segmentPlanning
        case LongFormTranscriptionError.segmentExportFailed:
            .segmentExport
        case LongFormTranscriptionError.segmentTooLarge:
            .segmentValidation
        case LongFormTranscriptionError.transcriptMergeFailed:
            .transcriptMerge
        case LongFormTranscriptionError.sourceChanged:
            .sourceChanged
        default:
            DictationFailureClassifier.category(for: error)
        }
    }

    private func persist(_ record: DictationRecord) async throws {
        do { try await historyStore.upsert(record) }
        catch { throw TranscriptionPersistenceFailure(underlyingError: error, record: record) }
    }

    private func availableCapacity(at url: URL) throws -> Int64 {
        if let capacityProvider { return try capacityProvider(url) }
        return try inspector.availableCapacity(at: url)
    }

    private func failWithoutManifest(
        _ error: Error,
        category: DictationErrorCategory,
        record: DictationRecord
    ) async -> TranscriptionRunFailure {
        var record = record
        record.status = .transcriptionFailed
        record.errorCategory = category
        record.errorMessage = error.localizedDescription
        record.updatedAt = Date()
        try? await historyStore.upsert(record)
        return TranscriptionRunFailure(underlyingError: error, record: record)
    }

    private func fail(
        _ error: Error,
        category: DictationErrorCategory,
        record: DictationRecord,
        manifest: inout TranscriptionSessionManifest
    ) async -> TranscriptionRunFailure {
        manifest.status = .failed
        manifest.lastErrorCategory = category
        manifest.lastErrorMessage = error.localizedDescription
        manifest.updatedAt = Date()
        try? await sessionStore.save(manifest)
        return await failWithoutManifest(error, category: category, record: record)
    }
}
