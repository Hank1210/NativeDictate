import Foundation
import os

nonisolated struct TrackTranscriptionRequest: Sendable, Equatable {
    var meetingSessionID: UUID
    var trackID: UUID
    var role: RecordingTrackRole
    var audioURL: URL
    var audioRelativePath: String
    var durationMilliseconds: Int64
    var byteCount: Int64
    var sampleRate: Double
    var channelCount: Int
    var transcriptionDirectory: URL
    var transcriptionSessionID: UUID
    var providerID: String
    var engineID: String
    var modelID: String
    var language: String?
    var privacyMode: PrivacyMode
    var profileID: UUID?
}

nonisolated struct TrackTranscriptionOutput: Sendable, Equatable {
    var transcript: String
    var providerID: String
    var modelID: String
    var segmentCount: Int
    var completedSegmentCount: Int
    var timedEntries: [TrackTranscriptEntry]?
    var isSilent: Bool

    init(
        transcript: String,
        providerID: String,
        modelID: String,
        segmentCount: Int,
        completedSegmentCount: Int,
        timedEntries: [TrackTranscriptEntry]? = nil,
        isSilent: Bool = false
    ) {
        self.transcript = transcript
        self.providerID = providerID
        self.modelID = modelID
        self.segmentCount = segmentCount
        self.completedSegmentCount = completedSegmentCount
        self.timedEntries = timedEntries
        self.isSilent = isSilent
    }
}

nonisolated protocol TrackTranscriptionExecuting: Sendable {
    /// Implementations persist their segment state below `transcriptionDirectory`
    /// using the stable `transcriptionSessionID`. A repeated request resumes that
    /// state and must not repeat already successful segments.
    func transcribe(_ request: TrackTranscriptionRequest) async throws -> TrackTranscriptionOutput
}

nonisolated protocol TrackTranscriptionSessionStoring: Sendable {
    func prepareSession(id: UUID) async throws -> MeetingSessionPaths
    func load(sessionID: UUID) async throws -> MixedRecordingSession?
    func save(_ manifest: MixedRecordingSession) async throws
}

extension MeetingSessionStore: TrackTranscriptionSessionStoring {}

nonisolated protocol MeetingProcessingQueueing: Sendable {
    func beginMeetingProcessing(sessionID: UUID) async throws -> DictationQueueSnapshot
    func finishMeetingProcessing(sessionID: UUID) async -> DictationQueueSnapshot
}

extension DictationProcessingQueue: MeetingProcessingQueueing {}

nonisolated struct MeetingTrackTranscript: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var meetingSessionID: UUID
    var trackID: UUID
    var role: RecordingTrackRole
    var transcriptionSessionID: UUID
    var providerID: String
    var modelID: String
    var language: String?
    var transcript: String
    var segmentCount: Int
    var completedSegmentCount: Int
    /// Optional provider/segment timing. Older 4.1 development artifacts decode
    /// without it and safely fall back to one track-wide chunk.
    var timedEntries: [TrackTranscriptEntry]?
    /// Optional for older development artifacts. Only a verified no-speech
    /// meeting track may persist an empty transcript.
    var isSilent: Bool? = nil
    var createdAt: Date

    func validated() throws -> Self {
        guard schemaVersion == Self.currentSchemaVersion,
              !providerID.isEmpty,
              !modelID.isEmpty,
              (!transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || isSilent == true),
              !(isSilent == true && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
              !(isSilent == true && timedEntries?.isEmpty == false),
              segmentCount > 0,
              completedSegmentCount == segmentCount else {
            throw TrackTranscriptionRunnerError.invalidOutput(role)
        }
        if let timedEntries {
            for (offset, entry) in timedEntries.enumerated() {
                guard entry.index == offset,
                      entry.startMilliseconds >= 0,
                      entry.endMilliseconds > entry.startMilliseconds,
                      !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TrackTranscriptionRunnerError.invalidOutput(role)
                }
                if offset > 0,
                   entry.startMilliseconds < timedEntries[offset - 1].startMilliseconds {
                    throw TrackTranscriptionRunnerError.invalidOutput(role)
                }
            }
        }
        return self
    }
}

nonisolated enum TrackTranscriptionRunnerError: LocalizedError, Equatable {
    case sessionNotFound(UUID)
    case invalidSessionState(MeetingSessionStatus)
    case missingAudio(RecordingTrackRole)
    case unsafeAudioPath(RecordingTrackRole)
    case invalidOutput(RecordingTrackRole)

    var errorDescription: String? {
        switch self {
        case let .sessionNotFound(id):
            "Meeting session \(id.uuidString) was not found."
        case let .invalidSessionState(status):
            "Meeting track transcription cannot start while the session is \(status.rawValue)."
        case let .missingAudio(role):
            "The \(role.rawValue) track has no readable audio source."
        case let .unsafeAudioPath(role):
            "The \(role.rawValue) audio source is outside the meeting tracks directory."
        case let .invalidOutput(role):
            "The \(role.rawValue) transcription result is incomplete."
        }
    }
}

actor TrackTranscriptionRunner {
    private let store: any TrackTranscriptionSessionStoring
    private let executor: any TrackTranscriptionExecuting
    private let processingQueue: (any MeetingProcessingQueueing)?
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    init(
        store: any TrackTranscriptionSessionStoring,
        executor: any TrackTranscriptionExecuting,
        processingQueue: (any MeetingProcessingQueueing)? = nil,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.executor = executor
        self.processingQueue = processingQueue
        self.fileManager = fileManager
        self.now = now
    }

    /// Runs each non-terminal track independently. Track-level failures are
    /// persisted and do not prevent the other track from completing.
    func run(sessionID: UUID) async throws -> MixedRecordingSession {
        let signpost = NativeDictateLogger.meetingSignposter.beginInterval(
            "Meeting Track Processing", id: .exclusive,
            "session: \(sessionID.uuidString, privacy: .public)"
        )
        defer { NativeDictateLogger.meetingSignposter.endInterval("Meeting Track Processing", signpost) }
        if let processingQueue {
            _ = try await processingQueue.beginMeetingProcessing(sessionID: sessionID)
        }
        do {
            let result = try await runAdmitted(sessionID: sessionID)
            if let processingQueue {
                _ = await processingQueue.finishMeetingProcessing(sessionID: sessionID)
            }
            return result
        } catch {
            if let processingQueue {
                _ = await processingQueue.finishMeetingProcessing(sessionID: sessionID)
            }
            throw error
        }
    }

    private func runAdmitted(sessionID: UUID) async throws -> MixedRecordingSession {
        guard var session = try await store.load(sessionID: sessionID) else {
            throw TrackTranscriptionRunnerError.sessionNotFound(sessionID)
        }
        guard Self.canTranscribe(session.status) else {
            throw TrackTranscriptionRunnerError.invalidSessionState(session.status)
        }
        let paths = try await store.prepareSession(id: sessionID)

        session.status = .transcribing
        session.lastErrorCategory = nil
        session.lastErrorMessage = nil
        updateTimestamp(&session)
        try await store.save(session)

        for role in RecordingTrackRole.allCases {
            guard let index = session.tracks.firstIndex(where: { $0.role == role }) else {
                continue
            }
            if [.transcribed, .unavailable].contains(session.tracks[index].status) {
                continue
            }

            let trackSignpost = NativeDictateLogger.meetingSignposter.beginInterval(
                "Meeting Track Transcription", id: .exclusive,
                "role: \(role.rawValue, privacy: .public)"
            )
            defer {
                NativeDictateLogger.meetingSignposter.endInterval(
                    "Meeting Track Transcription", trackSignpost
                )
            }

            let transcriptionSessionID = session.tracks[index].transcriptionSessionID ?? UUID()
            session.tracks[index].transcriptionSessionID = transcriptionSessionID
            session.tracks[index].status = .transcriptionPending
            session.tracks[index].errorCategory = nil
            session.tracks[index].errorMessage = nil
            updateTimestamp(&session)
            try await store.save(session)

            do {
                try Task.checkCancellation()
                let audioURL = try sourceURL(
                    for: session.tracks[index],
                    sessionDirectory: paths.sessionDirectory,
                    tracksDirectory: paths.tracksDirectory
                )
                session.tracks[index].status = .transcribing
                updateTimestamp(&session)
                try await store.save(session)

                let output = try await executor.transcribe(
                    TrackTranscriptionRequest(
                        meetingSessionID: session.id,
                        trackID: session.tracks[index].id,
                        role: role,
                        audioURL: audioURL,
                        audioRelativePath: try requiredAudioRelativePath(
                            session.tracks[index]
                        ),
                        durationMilliseconds: session.tracks[index].durationMilliseconds,
                        byteCount: session.tracks[index].byteCount,
                        sampleRate: session.tracks[index].sampleRate,
                        channelCount: session.tracks[index].channelCount,
                        transcriptionDirectory: paths.transcriptionDirectory,
                        transcriptionSessionID: transcriptionSessionID,
                        providerID: session.providerID,
                        engineID: session.engineID,
                        modelID: session.modelID,
                        language: session.language,
                        privacyMode: session.privacyMode ?? Self.migratedPrivacyMode(
                            providerID: session.providerID
                        ),
                        profileID: session.profileID
                    )
                )
                let artifact = try MeetingTrackTranscript(
                    schemaVersion: MeetingTrackTranscript.currentSchemaVersion,
                    meetingSessionID: session.id,
                    trackID: session.tracks[index].id,
                    role: role,
                    transcriptionSessionID: transcriptionSessionID,
                    providerID: output.providerID,
                    modelID: output.modelID,
                    language: session.language,
                    transcript: output.transcript,
                    segmentCount: output.segmentCount,
                    completedSegmentCount: output.completedSegmentCount,
                    timedEntries: output.timedEntries,
                    isSilent: output.isSilent ? true : nil,
                    createdAt: max(now(), session.updatedAt)
                ).validated()
                let relativePath = Self.transcriptRelativePath(for: role)
                try write(artifact, to: paths.sessionDirectory.appendingPathComponent(relativePath))

                session.tracks[index].status = .transcribed
                session.tracks[index].transcriptRelativePath = relativePath
                session.tracks[index].errorCategory = nil
                session.tracks[index].errorMessage = nil
                updateTimestamp(&session)
                try await store.save(session)
                NativeDictateLogger.meetingSignposter.emitEvent(
                    "Meeting Track Transcript Persisted", id: .exclusive,
                    "role: \(role.rawValue, privacy: .public), segments: \(output.segmentCount)"
                )
            } catch is CancellationError {
                session.tracks[index].status = .interrupted
                session.tracks[index].errorCategory = .interrupted
                session.tracks[index].errorMessage =
                    "Track transcription was interrupted. Its completed segment state was kept."
                session.status = .paused
                session.lastErrorCategory = .interrupted
                session.lastErrorMessage =
                    "Meeting transcription was paused. Continue it from History."
                updateTimestamp(&session)
                try await store.save(session)
                throw CancellationError()
            } catch {
                let underlyingError = (error as? TranscriptionRunFailure)?.underlyingError ?? error
                let category = DictationFailureClassifier.category(for: underlyingError)
                session.tracks[index].errorCategory = category
                session.tracks[index].errorMessage = underlyingError.localizedDescription
                if category == .localModelMissing {
                    session.tracks[index].status = .transcriptionPending
                    session.status = .paused
                    session.lastErrorCategory = category
                    session.lastErrorMessage = underlyingError.localizedDescription
                    updateTimestamp(&session)
                    try await store.save(session)
                    return session
                }
                session.tracks[index].status = .failed
                updateTimestamp(&session)
                try await store.save(session)
            }
        }

        let transcribedCount = session.tracks.count { $0.status == .transcribed }
        if transcribedCount == session.tracks.count {
            session.status = .merging
            session.lastErrorCategory = nil
            session.lastErrorMessage = nil
        } else if transcribedCount > 0 {
            session.status = .partial
            let failed = session.tracks.first {
                $0.status == .failed || $0.status == .unavailable
            }
            session.lastErrorCategory = failed?.errorCategory
            session.lastErrorMessage = failed?.errorMessage
        } else {
            session.status = .failed
            let failed = session.tracks.first { $0.status == .failed }
            session.lastErrorCategory = failed?.errorCategory ?? .unknown
            session.lastErrorMessage = failed?.errorMessage
                ?? "No meeting track could be transcribed."
        }
        updateTimestamp(&session)
        try await store.save(session)
        return session
    }

    private func sourceURL(
        for track: MeetingAudioTrack,
        sessionDirectory: URL,
        tracksDirectory: URL
    ) throws -> URL {
        guard let relativePath = track.audioRelativePath else {
            throw TrackTranscriptionRunnerError.missingAudio(track.role)
        }
        let sourceURL = sessionDirectory.appendingPathComponent(relativePath)
            .standardizedFileURL.resolvingSymlinksInPath()
        let safeTracksDirectory = tracksDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.isDescendant(sourceURL, of: safeTracksDirectory) else {
            throw TrackTranscriptionRunnerError.unsafeAudioPath(track.role)
        }
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw TrackTranscriptionRunnerError.missingAudio(track.role)
        }
        return sourceURL
    }

    private func requiredAudioRelativePath(_ track: MeetingAudioTrack) throws -> String {
        guard let relativePath = track.audioRelativePath else {
            throw TrackTranscriptionRunnerError.missingAudio(track.role)
        }
        return relativePath
    }

    private func write(_ artifact: MeetingTrackTranscript, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(artifact).write(to: url, options: .atomic)
    }

    private func updateTimestamp(_ session: inout MixedRecordingSession) {
        // Preserve manifest ordering if the wall clock moves backwards while a
        // long meeting is being processed or restored from another machine.
        session.updatedAt = max(now(), session.updatedAt)
    }

    private nonisolated static func canTranscribe(_ status: MeetingSessionStatus) -> Bool {
        [.queued, .transcribing, .partial, .paused, .failed, .merging].contains(status)
    }

    private nonisolated static func transcriptRelativePath(
        for role: RecordingTrackRole
    ) -> String {
        "transcription/\(role.rawValue)-transcript.json"
    }

    private nonisolated static func migratedPrivacyMode(providerID: String) -> PrivacyMode {
        providerID == TranscriptionProviderID.openAI.rawValue
            ? .cloudTranscription
            : .offline
    }

    private nonisolated static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let candidatePath = candidate.path
        let directoryPath = directory.path.hasSuffix("/")
            ? directory.path
            : directory.path + "/"
        return candidatePath.hasPrefix(directoryPath)
    }
}

#if DEBUG
/// Debug-only, one-shot fault used to exercise the product's partial meeting
/// recovery UX with real captured tracks. Release builds never compile it.
actor DebugOneShotTrackTranscriptionFailureExecutor: TrackTranscriptionExecuting {
    private let base: any TrackTranscriptionExecuting
    private var pendingRole: RecordingTrackRole?

    init(
        base: any TrackTranscriptionExecuting,
        failing role: RecordingTrackRole
    ) {
        self.base = base
        pendingRole = role
    }

    func transcribe(
        _ request: TrackTranscriptionRequest
    ) async throws -> TrackTranscriptionOutput {
        if pendingRole == request.role {
            pendingRole = nil
            throw URLError(.networkConnectionLost)
        }
        return try await base.transcribe(request)
    }
}
#endif
