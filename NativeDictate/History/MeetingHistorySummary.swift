import Foundation

nonisolated struct MeetingHistoryTrackSummary: Codable, Equatable, Identifiable, Sendable {
    var role: RecordingTrackRole
    var status: TrackCaptureStatus
    var durationMilliseconds: Int64
    var byteCount: Int64
    var gapCount: Int
    var clippedFrameCount: Int64

    var id: RecordingTrackRole { role }

    var title: String {
        role == .localSpeaker ? "Microphone" : "System Audio"
    }

    var isComplete: Bool {
        [.finalized, .transcriptionPending, .transcribing, .transcribed].contains(status)
    }

    var canPlayAudio: Bool {
        byteCount > 0
            && ![.preparing, .recording, .unavailable].contains(status)
    }

    var statusTitle: String {
        switch status {
        case .preparing: "Preparing"
        case .recording: "Recording"
        case .finalized: "Recorded"
        case .unavailable: "Unavailable"
        case .interrupted: "Interrupted"
        case .transcriptionPending: "Waiting for transcription"
        case .transcribing: "Transcribing"
        case .transcribed: "Transcribed"
        case .failed: "Failed"
        }
    }

    var statusSymbolName: String {
        switch status {
        case .transcribed: "checkmark.circle.fill"
        case .finalized, .transcriptionPending: "clock.circle"
        case .preparing, .recording, .transcribing: "ellipsis.circle"
        case .unavailable, .interrupted, .failed: "exclamationmark.triangle.fill"
        }
    }
}

/// Compact, content-free meeting metadata stored with a History row. The
/// session manifest remains the source of truth for paths, transcripts and
/// recovery state.
nonisolated struct MeetingHistorySummary: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var sessionID: UUID
    var status: MeetingSessionStatus
    var tracks: [MeetingHistoryTrackSummary]
    var synchronizationQuality: MeetingSynchronizationQuality
    var totalGapCount: Int
    var totalClippedFrameCount: Int64
    var insertionState: MeetingTranscriptInsertionState?

    init(session: MixedRecordingSession) throws {
        let session = try session.validated()
        schemaVersion = Self.currentSchemaVersion
        sessionID = session.id
        status = session.status
        tracks = RecordingTrackRole.allCases.compactMap { role in
            session.tracks.first(where: { $0.role == role }).map { track in
                MeetingHistoryTrackSummary(
                    role: role,
                    status: track.status,
                    durationMilliseconds: track.durationMilliseconds,
                    byteCount: track.byteCount,
                    gapCount: track.gaps.count,
                    clippedFrameCount: track.quality.clippedFrameCount
                )
            }
        }
        synchronizationQuality = session.qualityReport?.synchronizationQuality
            ?? session.synchronization?.quality
            ?? .notAnalyzed
        totalGapCount = session.qualityReport?.totalGapCount
            ?? session.tracks.reduce(0) { $0 + $1.gaps.count }
        totalClippedFrameCount = session.qualityReport?.totalClippedFrameCount
            ?? session.tracks.reduce(0) { $0 + $1.quality.clippedFrameCount }
        insertionState = session.transcriptInsertionState
    }

    func validated() throws -> Self {
        guard schemaVersion == Self.currentSchemaVersion,
              tracks.count == RecordingTrackRole.allCases.count,
              Set(tracks.map(\.role)) == Set(RecordingTrackRole.allCases),
              tracks.allSatisfy({
                  $0.durationMilliseconds >= 0
                      && $0.byteCount >= 0
                      && $0.gapCount >= 0
                      && $0.clippedFrameCount >= 0
              }),
              totalGapCount >= 0,
              totalClippedFrameCount >= 0 else {
            throw MeetingHistorySummaryError.invalidSummary
        }
        return self
    }

    var completeTrackCount: Int {
        tracks.filter(\.isComplete).count
    }

    var failedTrackCount: Int {
        tracks.count { $0.status == .failed }
    }

    var transcribedTrackCount: Int {
        tracks.count { $0.status == .transcribed }
    }

    var hasPartialTranscription: Bool {
        status == .partial && transcribedTrackCount > 0 && failedTrackCount > 0
    }

    var processingActionTitle: String {
        if hasPartialTranscription && failedTrackCount == 1 { return "Retry Failed Track" }
        if hasPartialTranscription && failedTrackCount > 1 { return "Retry Failed Tracks" }
        return "Continue Processing"
    }

    var processingNotice: String? {
        guard hasPartialTranscription else { return nil }
        let completed = transcribedTrackCount
        let total = tracks.count
        return "\(completed) of \(total) tracks transcribed. Retrying keeps completed track work."
    }

    var canResumeProcessing: Bool {
        guard [.queued, .partial, .paused, .failed, .merging].contains(status) else {
            return false
        }
        if tracks.contains(where: {
            [.finalized, .interrupted, .transcriptionPending, .transcribing, .failed]
                .contains($0.status)
        }) {
            return true
        }
        return tracks.allSatisfy { $0.status == .transcribed }
            && [.good, .degraded].contains(synchronizationQuality)
    }

    var canDeleteSession: Bool {
        [.completed, .partial, .paused, .failed, .cancelled].contains(status)
    }

    /// A completed timeline is still actionable until insertion is confirmed.
    /// Keep its History row and originals available for review or retry.
    var isAutomaticallyProtected: Bool {
        switch status {
        case .completed: insertionState != .completed
        default: true
        }
    }

    var canArchiveHistoryEntry: Bool {
        !isAutomaticallyProtected
    }

    /// Keeps the content-free History summary after retention has removed the
    /// completed session directory. Track state and quality remain useful,
    /// while zero byte counts make the UI stop offering stale playback.
    func withoutStoredSessionArtifacts() -> Self {
        var copy = self
        copy.tracks = copy.tracks.map { track in
            var track = track
            track.byteCount = 0
            return track
        }
        return copy
    }

    var captureWarningNotices: [String] {
        tracks.compactMap { track in
            if track.clippedFrameCount > 0 {
                return "\(track.title) clipping was detected. The original track was preserved; review its audio quality."
            }
            if [.unavailable, .interrupted, .failed].contains(track.status) {
                return "\(track.title) was not fully captured. Any available original track remains preserved."
            }
            return nil
        }
    }

    var statusTitle: String {
        switch status {
        case .preparing: "Preparing"
        case .recording: "Recording"
        case .finalizing: "Finalizing tracks"
        case .queued: "Waiting to process"
        case .transcribing: "Transcribing tracks"
        case .merging: "Creating meeting timeline"
        case .completed: "Completed"
        case .partial:
            hasPartialTranscription ? "Partial transcription" : "Partial recording"
        case .paused: "Paused — can be resumed"
        case .failed: "Needs attention"
        case .cancelled: "Cancelled"
        }
    }

    var synchronizationTitle: String {
        switch synchronizationQuality {
        case .notAnalyzed: "Not analyzed"
        case .good: "Good"
        case .degraded: "Degraded"
        case .unreliable: "Unreliable — no automatic merge"
        }
    }

    var synchronizationSymbolName: String {
        switch synchronizationQuality {
        case .good: "checkmark.circle.fill"
        case .degraded: "exclamationmark.circle"
        case .notAnalyzed: "questionmark.circle"
        case .unreliable: "exclamationmark.triangle.fill"
        }
    }
}

nonisolated enum MeetingHistorySummaryError: LocalizedError, Equatable {
    case invalidSummary

    var errorDescription: String? {
        "The meeting History summary is invalid."
    }
}

extension DictationRecord {
    nonisolated static func meetingSession(
        _ session: MixedRecordingSession,
        targetBundleIdentifier: String? = nil,
        targetApplicationName: String? = nil
    ) throws -> Self {
        let summary = try MeetingHistorySummary(session: session).validated()
        let duration = Double(session.tracks.map(\.durationMilliseconds).max() ?? 0) / 1_000
        let status: DictationRecordStatus = switch session.status {
        case .completed: .completed
        case .cancelled: .cancelled
        case .queued, .transcribing, .merging: .transcribing
        case .partial, .paused, .failed: .transcriptionFailed
        case .preparing, .recording, .finalizing: .recorded
        }
        var record = newRecording(
            id: session.recordID,
            startedAt: session.createdAt,
            endedAt: session.createdAt.addingTimeInterval(duration),
            duration: duration,
            status: status,
            audioRelativePath: "MeetingSessions/\(session.id.uuidString)",
            audioFileSize: session.tracks.reduce(0) { $0 + $1.byteCount },
            providerID: session.providerID,
            modelID: session.modelID,
            language: session.language,
            targetBundleIdentifier: targetBundleIdentifier,
            targetApplicationName: targetApplicationName,
            sourceMetadata: AudioSourceMetadata(source: .mixed, sampleRate: 0, channelCount: 0)
        )
        record.originalTranscript = session.finalTranscript
        record.finalText = session.finalTranscript
        record.errorCategory = session.lastErrorCategory
        record.errorMessage = session.lastErrorMessage
        record.cancelled = session.status == .cancelled
        record.updatedAt = session.updatedAt
        record.meetingSummary = summary
        return record
    }
}
