import Foundation
import os

nonisolated enum TimedTranscriptMergeError: LocalizedError, Equatable {
    case sessionNotFound(UUID)
    case invalidSessionState(MeetingSessionStatus)
    case synchronizationUnavailable
    case unreliableSynchronization
    case missingTrack(RecordingTrackRole)
    case missingTranscript(RecordingTrackRole)
    case mismatchedTranscript(RecordingTrackRole)
    case unsafeTranscriptPath(RecordingTrackRole)
    case invalidTrackEntry(RecordingTrackRole, Int)
    case invalidTimeline

    var errorDescription: String? {
        switch self {
        case let .sessionNotFound(id):
            "Meeting session \(id.uuidString) was not found."
        case let .invalidSessionState(status):
            "Meeting transcript merge cannot start while the session is \(status.rawValue)."
        case .synchronizationUnavailable:
            "The meeting tracks do not have a usable shared timeline."
        case .unreliableSynchronization:
            "The meeting synchronization is too unreliable for an automatic transcript merge."
        case let .missingTrack(role):
            "The \(role.rawValue) track is missing."
        case let .missingTranscript(role):
            "The \(role.rawValue) track transcript is missing."
        case let .mismatchedTranscript(role):
            "The saved \(role.rawValue) transcript does not belong to this meeting track."
        case let .unsafeTranscriptPath(role):
            "The \(role.rawValue) transcript is outside the meeting transcription directory."
        case let .invalidTrackEntry(role, index):
            "The \(role.rawValue) transcript contains an invalid timed entry at index \(index)."
        case .invalidTimeline:
            "The meeting transcript timeline is invalid. Both track transcripts were kept."
        }
    }
}

nonisolated struct TimedTranscriptMerger: Sendable {
    func merge(
        session: MixedRecordingSession,
        transcripts: [MeetingTrackTranscript],
        createdAt: Date = Date()
    ) throws -> TimedTranscriptTimeline {
        let session = try session.validated()
        guard let synchronization = session.synchronization else {
            throw TimedTranscriptMergeError.synchronizationUnavailable
        }
        guard synchronization.quality != .notAnalyzed else {
            throw TimedTranscriptMergeError.synchronizationUnavailable
        }
        guard synchronization.quality != .unreliable else {
            throw TimedTranscriptMergeError.unreliableSynchronization
        }

        var merged: [TimedTranscriptEntry] = []
        for role in RecordingTrackRole.allCases {
            guard let track = session.tracks.first(where: { $0.role == role }) else {
                throw TimedTranscriptMergeError.missingTrack(role)
            }
            guard let transcript = transcripts.first(where: { $0.role == role }) else {
                throw TimedTranscriptMergeError.missingTranscript(role)
            }
            guard transcript.meetingSessionID == session.id,
                  transcript.trackID == track.id,
                  transcript.transcriptionSessionID == track.transcriptionSessionID else {
                throw TimedTranscriptMergeError.mismatchedTranscript(role)
            }
            let entries = try sourceEntries(transcript: transcript, track: track)
            merged.append(contentsOf: try entries.map { entry in
                let start = try mapToSessionTime(
                    entry.startMilliseconds,
                    track: track,
                    synchronization: synchronization,
                    boundary: .start
                )
                let end = try mapToSessionTime(
                    entry.endMilliseconds,
                    track: track,
                    synchronization: synchronization,
                    boundary: .end
                )
                guard end > start else {
                    throw TimedTranscriptMergeError.invalidTrackEntry(role, entry.index)
                }
                return TimedTranscriptEntry(
                    id: Self.entryID(
                        meetingSessionID: session.id,
                        role: role,
                        sourceIndex: entry.index
                    ),
                    role: role,
                    sourceIndex: entry.index,
                    trackStartMilliseconds: entry.startMilliseconds,
                    trackEndMilliseconds: entry.endMilliseconds,
                    sessionStartMilliseconds: start,
                    sessionEndMilliseconds: end,
                    text: entry.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    precision: entry.precision
                )
            })
        }

        merged.sort(by: Self.entryComesBefore)
        return try TimedTranscriptTimeline(
            schemaVersion: TimedTranscriptTimeline.currentSchemaVersion,
            meetingSessionID: session.id,
            entries: merged,
            renderedText: Self.render(merged),
            createdAt: createdAt
        ).validated()
    }

    private func sourceEntries(
        transcript: MeetingTrackTranscript,
        track: MeetingAudioTrack
    ) throws -> [TrackTranscriptEntry] {
        if transcript.isSilent == true { return [] }
        let explicit = transcript.timedEntries ?? []
        let sourceDuration = max(
            1,
            track.durationMilliseconds - track.gaps.reduce(Int64(0)) {
                $0 + $1.durationMilliseconds
            }
        )
        let entries = explicit.isEmpty
            ? [TrackTranscriptEntry(
                index: 0,
                startMilliseconds: 0,
                endMilliseconds: sourceDuration,
                text: transcript.transcript,
                precision: .trackChunk
            )]
            : explicit
        for (offset, entry) in entries.enumerated() {
            guard entry.index == offset,
                  entry.startMilliseconds >= 0,
                  entry.endMilliseconds > entry.startMilliseconds,
                  entry.endMilliseconds <= sourceDuration,
                  !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TimedTranscriptMergeError.invalidTrackEntry(track.role, entry.index)
            }
            if offset > 0,
               entry.startMilliseconds < entries[offset - 1].startMilliseconds {
                throw TimedTranscriptMergeError.invalidTrackEntry(track.role, entry.index)
            }
        }
        return entries
    }

    private func mapToSessionTime(
        _ trackMilliseconds: Int64,
        track: MeetingAudioTrack,
        synchronization: SynchronizationReport,
        boundary: TimelineBoundary
    ) throws -> Int64 {
        guard let firstAnchor = track.timestampAnchors.first else {
            throw TimedTranscriptMergeError.synchronizationUnavailable
        }
        let driftScale: Double
        if track.role == .localSpeaker,
           let partsPerMillion = synchronization.estimatedDriftPartsPerMillion {
            driftScale = 1 + partsPerMillion / 1_000_000
        } else {
            driftScale = 1
        }
        guard driftScale.isFinite, driftScale > 0 else {
            throw TimedTranscriptMergeError.synchronizationUnavailable
        }
        let insertedGapDuration = track.gaps.reduce(Int64(0)) { total, gap in
            let isBeforeBoundary = boundary == .start
                ? gap.startMilliseconds <= trackMilliseconds
                : gap.startMilliseconds < trackMilliseconds
            return total + (isBeforeBoundary ? gap.durationMilliseconds : 0)
        }
        let mapped = Double(firstAnchor.sessionTimeMilliseconds)
            + Double(trackMilliseconds) * driftScale
            + Double(insertedGapDuration)
        guard mapped.isFinite, mapped >= 0, mapped <= Double(Int64.max) else {
            throw TimedTranscriptMergeError.invalidTrackEntry(track.role, 0)
        }
        return Int64(mapped.rounded())
    }

    private enum TimelineBoundary {
        case start
        case end
    }

    private static func entryComesBefore(
        _ left: TimedTranscriptEntry,
        _ right: TimedTranscriptEntry
    ) -> Bool {
        if left.sessionStartMilliseconds != right.sessionStartMilliseconds {
            return left.sessionStartMilliseconds < right.sessionStartMilliseconds
        }
        if roleOrder(left.role) != roleOrder(right.role) {
            return roleOrder(left.role) < roleOrder(right.role)
        }
        return left.sourceIndex < right.sourceIndex
    }

    private static func roleOrder(_ role: RecordingTrackRole) -> Int {
        switch role {
        case .localSpeaker: 0
        case .systemAudio: 1
        }
    }

    /// Derives a stable per-session identifier without persisting random state.
    /// The reversible byte mixing keeps retries deterministic while the session
    /// UUID, role and source index provide the entry namespace.
    private static func entryID(
        meetingSessionID: UUID,
        role: RecordingTrackRole,
        sourceIndex: Int
    ) -> UUID {
        var bytes = meetingSessionID.uuid
        withUnsafeMutableBytes(of: &bytes) { output in
            output[0] ^= role == .localSpeaker ? 0x59 : 0x53
            var encodedIndex = UInt64(sourceIndex).bigEndian
            withUnsafeBytes(of: &encodedIndex) { indexBytes in
                for offset in 0..<MemoryLayout<UInt64>.size {
                    output[8 + offset] ^= indexBytes[offset]
                }
            }
            output[6] = (output[6] & 0x0F) | 0x50
            output[8] = (output[8] & 0x3F) | 0x80
        }
        return UUID(uuid: bytes)
    }

    private struct RenderedTurn {
        var role: RecordingTrackRole
        var firstSourceIndex: Int
        var startMilliseconds: Int64
        var endMilliseconds: Int64
        var text: String
        var wordPrecise: Bool
    }

    private static func render(_ entries: [TimedTranscriptEntry]) -> String {
        // Keep the persisted timeline word-precise. Only its readable projection
        // groups nearby words into bounded turns. Split continuous speech at
        // the other speaker's entry and exit, so a long paragraph cannot be
        // displayed ahead of an utterance that happened inside it.
        var turns: [RenderedTurn] = []
        for role in RecordingTrackRole.allCases {
            var roleTurns: [RenderedTurn] = []
            let otherSpeakerBoundaries = speechBoundaries(ofOtherRoleThan: role, in: entries)
            var boundaryIndex = 0
            for entry in entries where entry.role == role {
                if let last = roleTurns.indices.last {
                    while boundaryIndex < otherSpeakerBoundaries.count,
                          otherSpeakerBoundaries[boundaryIndex]
                            <= roleTurns[last].startMilliseconds {
                        boundaryIndex += 1
                    }
                    var crossesSpeakerBoundary = false
                    while boundaryIndex < otherSpeakerBoundaries.count,
                          otherSpeakerBoundaries[boundaryIndex]
                            <= entry.sessionStartMilliseconds {
                        if roleTurns[last].endMilliseconds - roleTurns[last].startMilliseconds >= 3_000 {
                            crossesSpeakerBoundary = true
                            break
                        }
                        // A very short utterance stays intact. Do not split
                        // it several words later for a boundary now in the past.
                        boundaryIndex += 1
                    }
                    if roleTurns[last].wordPrecise,
                       entry.precision == .word,
                       entry.sessionStartMilliseconds - roleTurns[last].endMilliseconds <= 800,
                       entry.sessionEndMilliseconds - roleTurns[last].startMilliseconds <= 20_000,
                       !crossesSpeakerBoundary,
                       !(roleTurns[last].endMilliseconds - roleTurns[last].startMilliseconds >= 15_000
                         && endsSentence(roleTurns[last].text)) {
                        roleTurns[last].endMilliseconds = max(
                            roleTurns[last].endMilliseconds,
                            entry.sessionEndMilliseconds
                        )
                        roleTurns[last].text = joined(roleTurns[last].text, entry.text)
                        continue
                    }
                }
                roleTurns.append(RenderedTurn(
                    role: role,
                    firstSourceIndex: entry.sourceIndex,
                    startMilliseconds: entry.sessionStartMilliseconds,
                    endMilliseconds: entry.sessionEndMilliseconds,
                    text: entry.text,
                    wordPrecise: entry.precision == .word
                ))
            }
            turns.append(contentsOf: roleTurns)
        }
        turns.sort { left, right in
            if left.startMilliseconds != right.startMilliseconds {
                return left.startMilliseconds < right.startMilliseconds
            }
            if left.role != right.role {
                return roleOrder(left.role) < roleOrder(right.role)
            }
            return left.firstSourceIndex < right.firstSourceIndex
        }
        return turns.map { turn in
            let label = turn.role == .localSpeaker ? "You" : "System Audio"
            let hasPreciseOverlap = turn.wordPrecise && turns.contains { other in
                guard other.role != turn.role, other.wordPrecise else { return false }
                let overlap = min(turn.endMilliseconds, other.endMilliseconds)
                    - max(turn.startMilliseconds, other.startMilliseconds)
                return overlap >= 150
            }
            let suffix = hasPreciseOverlap
                ? " · overlaps \(turn.role == .localSpeaker ? "System Audio" : "You")"
                : ""
            return "[\(label)\(suffix)] \(turn.text)"
        }.joined(separator: "\n")
    }

    private static func speechBoundaries(
        ofOtherRoleThan role: RecordingTrackRole,
        in entries: [TimedTranscriptEntry]
    ) -> [Int64] {
        var boundaries: [Int64] = []
        var speechStart: Int64?
        var speechEnd: Int64 = 0
        for entry in entries where entry.role != role && entry.precision == .word {
            if let start = speechStart,
               entry.sessionStartMilliseconds - speechEnd > 800 {
                boundaries.append(contentsOf: [start, speechEnd])
                speechStart = entry.sessionStartMilliseconds
                speechEnd = entry.sessionEndMilliseconds
            } else {
                speechStart = speechStart ?? entry.sessionStartMilliseconds
                speechEnd = max(speechEnd, entry.sessionEndMilliseconds)
            }
        }
        if let speechStart { boundaries.append(contentsOf: [speechStart, speechEnd]) }
        return boundaries
    }

    private static func endsSentence(_ text: String) -> Bool {
        let closingPunctuation = CharacterSet(charactersIn: "\"'”’)]}")
        let last = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: closingPunctuation).last
        return last.map { ".!?…".contains($0) } ?? false
    }

    private static func joined(_ left: String, _ right: String) -> String {
        guard let first = right.first else { return left }
        let attachesToPrevious = ".,;:!?%)]}".contains(first)
        return left + (attachesToPrevious || left.last?.isWhitespace == true ? "" : " ") + right
    }
}

nonisolated protocol MeetingTranscriptMergeSessionStoring: Sendable {
    func prepareSession(id: UUID) async throws -> MeetingSessionPaths
    func load(sessionID: UUID) async throws -> MixedRecordingSession?
    func save(_ manifest: MixedRecordingSession) async throws
}

extension MeetingSessionStore: MeetingTranscriptMergeSessionStoring {}

actor MeetingTranscriptMergeRunner {
    static let timelineRelativePath = "transcription/merged-timeline.json"

    private let store: any MeetingTranscriptMergeSessionStoring
    private let merger: TimedTranscriptMerger
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    init(
        store: any MeetingTranscriptMergeSessionStoring,
        merger: TimedTranscriptMerger = TimedTranscriptMerger(),
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.merger = merger
        self.fileManager = fileManager
        self.now = now
    }

    func run(sessionID: UUID) async throws -> MixedRecordingSession {
        guard var session = try await store.load(sessionID: sessionID) else {
            throw TimedTranscriptMergeError.sessionNotFound(sessionID)
        }
        guard [.merging, .paused, .failed].contains(session.status) else {
            throw TimedTranscriptMergeError.invalidSessionState(session.status)
        }
        let signpost = NativeDictateLogger.meetingSignposter.beginInterval(
            "Meeting Transcript Merge", id: .exclusive,
            "session: \(sessionID.uuidString, privacy: .public)"
        )
        defer { NativeDictateLogger.meetingSignposter.endInterval("Meeting Transcript Merge", signpost) }
        let paths = try await store.prepareSession(id: sessionID)
        session.status = .merging
        session.lastErrorCategory = nil
        session.lastErrorMessage = nil
        session.updatedAt = max(now(), session.updatedAt)
        try await store.save(session)

        do {
            let transcripts = try session.tracks.map { track in
                try loadTranscript(
                    for: track,
                    session: session,
                    sessionDirectory: paths.sessionDirectory,
                    transcriptionDirectory: paths.transcriptionDirectory
                )
            }
            let timeline = try merger.merge(
                session: session,
                transcripts: transcripts,
                createdAt: max(now(), session.updatedAt)
            )
            let timelineURL = paths.sessionDirectory.appendingPathComponent(
                Self.timelineRelativePath
            )
            try write(timeline, to: timelineURL)

            session.mergedTimelineRelativePath = Self.timelineRelativePath
            session.finalTranscript = timeline.renderedText
            session.completionMode = .allTracks
            session.status = .completed
            session.transcriptInsertionState = .ready
            session.transcriptInsertionAttemptCount = 0
            session.lastErrorCategory = nil
            session.lastErrorMessage = nil
            session.updatedAt = max(now(), session.updatedAt)
            try await store.save(session)
            NativeDictateLogger.meetingSignposter.emitEvent(
                "Meeting Timeline Persisted", id: .exclusive,
                "entries: \(timeline.entries.count), status: \(session.status.rawValue, privacy: .public)"
            )
            return session
        } catch {
            session.status = .paused
            session.lastErrorCategory = .transcriptMerge
            session.lastErrorMessage = error.localizedDescription
            session.updatedAt = max(now(), session.updatedAt)
            try? await store.save(session)
            throw error
        }
    }

    private func loadTranscript(
        for track: MeetingAudioTrack,
        session: MixedRecordingSession,
        sessionDirectory: URL,
        transcriptionDirectory: URL
    ) throws -> MeetingTrackTranscript {
        guard track.status == .transcribed,
              let relativePath = track.transcriptRelativePath else {
            throw TimedTranscriptMergeError.missingTranscript(track.role)
        }
        let url = sessionDirectory.appendingPathComponent(relativePath)
            .standardizedFileURL.resolvingSymlinksInPath()
        let safeDirectory = transcriptionDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.isDescendant(url, of: safeDirectory) else {
            throw TimedTranscriptMergeError.unsafeTranscriptPath(track.role)
        }
        guard fileManager.fileExists(atPath: url.path) else {
            throw TimedTranscriptMergeError.missingTranscript(track.role)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let artifact = try decoder.decode(MeetingTrackTranscript.self, from: Data(contentsOf: url))
        guard artifact.meetingSessionID == session.id,
              artifact.trackID == track.id,
              artifact.role == track.role else {
            throw TimedTranscriptMergeError.mismatchedTranscript(track.role)
        }
        return try artifact.validated()
    }

    private func write(_ timeline: TimedTranscriptTimeline, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(timeline.validated()).write(to: url, options: .atomic)
    }

    private nonisolated static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        candidate.path == directory.path
            || candidate.path.hasPrefix(directory.path + "/")
    }
}
