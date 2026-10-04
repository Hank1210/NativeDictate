import Foundation

nonisolated enum MeetingSessionStatus: String, Codable, Sendable, Equatable {
    case preparing
    case recording
    case finalizing
    case queued
    case transcribing
    case merging
    case completed
    case partial
    case paused
    case failed
    case cancelled
}

nonisolated enum RecordingTrackRole: String, Codable, CaseIterable, Sendable, Hashable {
    case localSpeaker
    case systemAudio
}

nonisolated enum TrackCaptureStatus: String, Codable, Sendable, Equatable {
    case preparing
    case recording
    case finalized
    case unavailable
    case interrupted
    case transcriptionPending
    case transcribing
    case transcribed
    case failed
}

/// Compatibility names used by the Phase 4.1 PRD.
typealias MeetingTrackRole = RecordingTrackRole
typealias MeetingTrackStatus = TrackCaptureStatus

nonisolated struct TrackTimestampAnchor: Codable, Sendable, Equatable {
    var hostTime: UInt64
    var trackFramePosition: Int64
    var sessionTimeMilliseconds: Int64
}

nonisolated enum TrackGapReason: String, Codable, Sendable {
    case missingAtStart
    case droppedBuffers
    case deviceChanged
    case sourceInterrupted
    case unknown
}

nonisolated struct TrackGap: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var startMilliseconds: Int64
    var endMilliseconds: Int64
    var reason: TrackGapReason

    var durationMilliseconds: Int64 { endMilliseconds - startMilliseconds }
}

nonisolated struct TrackQualityMetrics: Codable, Sendable, Equatable {
    var peakLevel: Float?
    var clippedFrameCount: Int64
    var silentDurationMilliseconds: Int64
    var droppedBufferCount: Int64
}

nonisolated struct MeetingAudioTrack: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var role: RecordingTrackRole
    var status: TrackCaptureStatus
    var audioRelativePath: String?
    var formatIdentifier: String?
    var sampleRate: Double
    var channelCount: Int
    var firstHostTime: UInt64?
    var lastHostTime: UInt64?
    var durationMilliseconds: Int64
    var byteCount: Int64
    var timestampAnchors: [TrackTimestampAnchor]
    var gaps: [TrackGap]
    var quality: TrackQualityMetrics
    var transcriptionSessionID: UUID?
    var transcriptRelativePath: String?
    var errorCategory: DictationErrorCategory?
    var errorMessage: String?
}

nonisolated enum MeetingSynchronizationQuality: String, Codable, Sendable, Equatable {
    case notAnalyzed
    case good
    case degraded
    case unreliable
}

nonisolated struct SynchronizationReport: Codable, Sendable, Equatable {
    var quality: MeetingSynchronizationQuality
    var initialOffsetMilliseconds: Double?
    var estimatedDriftPartsPerMillion: Double?
    var residualDriftMilliseconds: Double?
    var analyzedAnchorCount: Int
}

nonisolated struct MeetingQualityReport: Codable, Sendable, Equatable {
    var synchronizationQuality: MeetingSynchronizationQuality
    var completeTrackRoles: Set<RecordingTrackRole>
    var totalGapCount: Int
    var totalGapDurationMilliseconds: Int64
    var totalClippedFrameCount: Int64
}

nonisolated enum MeetingCompletionMode: Codable, Sendable, Equatable {
    case allTracks
    case acceptedSingleTrack(RecordingTrackRole)
}

nonisolated enum MeetingTranscriptInsertionState: String, Codable, Sendable, Equatable {
    case ready
    case attempting
    case completed
    case deferred
    case unknown
}

nonisolated struct MixedRecordingSession: Codable, Sendable, Equatable, Identifiable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var recordID: UUID
    var dictationJobID: UUID?
    var status: MeetingSessionStatus
    var createdAt: Date
    var updatedAt: Date
    var providerID: String
    var engineID: String
    var modelID: String
    var language: String?
    /// Optional only for migration of manifests created by earlier 4.1 test builds.
    var privacyMode: PrivacyMode?
    var profileID: UUID?
    var tracks: [MeetingAudioTrack]
    var synchronization: SynchronizationReport?
    var qualityReport: MeetingQualityReport?
    var completionMode: MeetingCompletionMode?
    var mergedTimelineRelativePath: String?
    var finalTranscript: String?
    /// Optional for manifests created before the timed-merge implementation.
    var transcriptInsertionState: MeetingTranscriptInsertionState? = nil
    var transcriptInsertionAttemptCount: Int? = nil
    var lastErrorCategory: DictationErrorCategory?
    var lastErrorMessage: String?

    mutating func normalizeInterruptedWork(now: Date = Date()) {
        var changed = false
        for index in tracks.indices {
            switch tracks[index].status {
            case .preparing, .recording, .transcribing:
                tracks[index].status = .interrupted
                tracks[index].errorCategory = .interrupted
                tracks[index].errorMessage =
                    "Track processing was interrupted when NativeDictate stopped."
                changed = true
            default:
                break
            }
        }

        switch status {
        case .preparing, .recording, .finalizing, .transcribing, .merging:
            status = .paused
            lastErrorCategory = .interrupted
            lastErrorMessage =
                "Meeting processing was interrupted when NativeDictate stopped. Resume from History."
            changed = true
        default:
            break
        }
        if changed { updatedAt = now }
    }

    func validated() throws -> Self {
        guard schemaVersion > 0, schemaVersion <= Self.currentSchemaVersion else {
            throw MixedRecordingSessionValidationError.unsupportedSchema(schemaVersion)
        }
        guard updatedAt >= createdAt else {
            throw MixedRecordingSessionValidationError.invalidDateOrder
        }
        guard tracks.count == RecordingTrackRole.allCases.count,
              Set(tracks.map(\.role)) == Set(RecordingTrackRole.allCases) else {
            throw MixedRecordingSessionValidationError.invalidTrackRoles
        }
        guard Set(tracks.map(\.id)).count == tracks.count else {
            throw MixedRecordingSessionValidationError.duplicateTrackIdentifier
        }

        for track in tracks {
            try validate(track)
        }

        if let synchronization {
            guard synchronization.analyzedAnchorCount >= 0,
                  synchronization.initialOffsetMilliseconds.map(\.isFinite) ?? true,
                  synchronization.estimatedDriftPartsPerMillion.map(\.isFinite) ?? true,
                  synchronization.residualDriftMilliseconds.map({ $0.isFinite && $0 >= 0 }) ?? true else {
                throw MixedRecordingSessionValidationError.invalidSynchronizationReport
            }
        }
        if let qualityReport {
            guard qualityReport.totalGapCount >= 0,
                  qualityReport.totalGapDurationMilliseconds >= 0,
                  qualityReport.totalClippedFrameCount >= 0,
                  qualityReport.completeTrackRoles.isSubset(of: Set(RecordingTrackRole.allCases)) else {
                throw MixedRecordingSessionValidationError.invalidQualityReport
            }
        }
        if let transcriptInsertionAttemptCount {
            guard transcriptInsertionAttemptCount >= 0 else {
                throw MixedRecordingSessionValidationError.invalidInsertionState
            }
        }
        if transcriptInsertionState == .completed,
           transcriptInsertionAttemptCount != 1 {
            throw MixedRecordingSessionValidationError.invalidInsertionState
        }
        if transcriptInsertionState == .attempting,
           transcriptInsertionAttemptCount != 1 {
            throw MixedRecordingSessionValidationError.invalidInsertionState
        }

        let originalPaths = tracks.compactMap(\.audioRelativePath)
        guard Set(originalPaths).count == originalPaths.count else {
            throw MixedRecordingSessionValidationError.duplicateOriginalPath
        }
        if let mergedTimelineRelativePath {
            try validate(relativePath: mergedTimelineRelativePath)
            guard mergedTimelineRelativePath.hasPrefix("transcription/") else {
                throw MixedRecordingSessionValidationError.invalidMergedTimelinePath
            }
            guard !originalPaths.contains(mergedTimelineRelativePath) else {
                throw MixedRecordingSessionValidationError.derivedPathOverwritesOriginal
            }
        }

        if status == .recording,
           !tracks.contains(where: { $0.status == .recording }) {
            throw MixedRecordingSessionValidationError.invalidSessionState
        }
        if status == .completed {
            guard finalTranscript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  mergedTimelineRelativePath != nil,
                  let completionMode else {
                throw MixedRecordingSessionValidationError.invalidCompletion
            }
            switch completionMode {
            case .allTracks:
                guard tracks.allSatisfy({ $0.status == .transcribed }) else {
                    throw MixedRecordingSessionValidationError.invalidCompletion
                }
            case let .acceptedSingleTrack(role):
                guard tracks.first(where: { $0.role == role })?.status == .transcribed,
                      tracks.first(where: { $0.role != role }).map({
                          [.unavailable, .interrupted, .failed].contains($0.status)
                      }) == true else {
                    throw MixedRecordingSessionValidationError.invalidCompletion
                }
            }
        }
        return self
    }

    private func validate(_ track: MeetingAudioTrack) throws {
        guard track.sampleRate.isFinite, track.sampleRate >= 0,
              track.channelCount >= 0,
              track.durationMilliseconds >= 0,
              track.byteCount >= 0,
              track.quality.clippedFrameCount >= 0,
              track.quality.silentDurationMilliseconds >= 0,
              track.quality.droppedBufferCount >= 0,
              track.quality.peakLevel.map({ $0.isFinite && $0 >= 0 && $0 <= 1 }) ?? true else {
            throw MixedRecordingSessionValidationError.invalidTrackMetrics(track.role)
        }
        if let firstHostTime = track.firstHostTime,
           let lastHostTime = track.lastHostTime,
           lastHostTime < firstHostTime {
            throw MixedRecordingSessionValidationError.nonMonotonicTimeline(track.role)
        }

        for (index, anchor) in track.timestampAnchors.enumerated() {
            guard anchor.trackFramePosition >= 0, anchor.sessionTimeMilliseconds >= 0 else {
                throw MixedRecordingSessionValidationError.nonMonotonicTimeline(track.role)
            }
            if index > 0 {
                let previous = track.timestampAnchors[index - 1]
                guard anchor.hostTime > previous.hostTime,
                      anchor.trackFramePosition > previous.trackFramePosition,
                      anchor.sessionTimeMilliseconds >= previous.sessionTimeMilliseconds else {
                    throw MixedRecordingSessionValidationError.nonMonotonicTimeline(track.role)
                }
            }
        }
        for (index, gap) in track.gaps.enumerated() {
            guard gap.startMilliseconds >= 0,
                  gap.endMilliseconds > gap.startMilliseconds,
                  gap.endMilliseconds <= track.durationMilliseconds else {
                throw MixedRecordingSessionValidationError.invalidGap(track.role)
            }
            if index > 0, gap.startMilliseconds < track.gaps[index - 1].endMilliseconds {
                throw MixedRecordingSessionValidationError.invalidGap(track.role)
            }
        }

        if let path = track.audioRelativePath {
            try validate(relativePath: path)
        }
        if let path = track.transcriptRelativePath {
            try validate(relativePath: path)
            guard path.hasPrefix("transcription/") else {
                throw MixedRecordingSessionValidationError.invalidTranscriptPath(track.role)
            }
            if path == track.audioRelativePath {
                throw MixedRecordingSessionValidationError.derivedPathOverwritesOriginal
            }
        }
        if [.finalized, .transcriptionPending, .transcribing, .transcribed].contains(track.status) {
            guard track.audioRelativePath != nil,
                  track.formatIdentifier?.isEmpty == false,
                  track.sampleRate > 0,
                  track.channelCount > 0,
                  track.durationMilliseconds > 0,
                  track.byteCount > 0 else {
                throw MixedRecordingSessionValidationError.missingFinalizedTrackMetadata(track.role)
            }
        }
        if track.status == .transcribed {
            guard track.transcriptionSessionID != nil,
                  track.transcriptRelativePath != nil else {
                throw MixedRecordingSessionValidationError.missingTranscriptMetadata(track.role)
            }
        }
    }

    private func validate(relativePath: String) throws {
        let components = NSString(string: relativePath).pathComponents
        guard !relativePath.isEmpty,
              !NSString(string: relativePath).isAbsolutePath,
              !components.contains("..") else {
            throw MixedRecordingSessionValidationError.unsafeRelativePath(relativePath)
        }
    }
}

typealias MeetingSessionManifest = MixedRecordingSession

nonisolated enum MixedRecordingSessionValidationError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidDateOrder
    case invalidTrackRoles
    case duplicateTrackIdentifier
    case duplicateOriginalPath
    case invalidTrackMetrics(RecordingTrackRole)
    case nonMonotonicTimeline(RecordingTrackRole)
    case invalidGap(RecordingTrackRole)
    case missingFinalizedTrackMetadata(RecordingTrackRole)
    case missingTranscriptMetadata(RecordingTrackRole)
    case invalidTranscriptPath(RecordingTrackRole)
    case invalidMergedTimelinePath
    case invalidInsertionState
    case invalidSynchronizationReport
    case invalidQualityReport
    case unsafeRelativePath(String)
    case derivedPathOverwritesOriginal
    case invalidSessionState
    case invalidCompletion

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "Unsupported meeting session schema version \(version)."
        case .invalidDateOrder:
            "The meeting session update date precedes its creation date."
        case .invalidTrackRoles:
            "A mixed recording must contain one microphone and one System Audio track."
        case .duplicateTrackIdentifier:
            "The meeting session contains duplicate track identifiers."
        case .duplicateOriginalPath:
            "The meeting session contains duplicate original-track paths."
        case let .invalidTrackMetrics(role):
            "The \(role.rawValue) track contains invalid quality metrics."
        case let .nonMonotonicTimeline(role):
            "The \(role.rawValue) track contains a non-monotonic timeline."
        case let .invalidGap(role):
            "The \(role.rawValue) track contains an invalid gap."
        case let .missingFinalizedTrackMetadata(role):
            "The finalized \(role.rawValue) track is missing required metadata."
        case let .missingTranscriptMetadata(role):
            "The transcribed \(role.rawValue) track is missing its transcript metadata."
        case let .invalidTranscriptPath(role):
            "The \(role.rawValue) transcript must be stored in the meeting transcription directory."
        case .invalidMergedTimelinePath:
            "The merged meeting timeline must be stored in the meeting transcription directory."
        case .invalidInsertionState:
            "The meeting transcript insertion state is invalid."
        case .invalidSynchronizationReport:
            "The meeting session contains invalid synchronization metrics."
        case .invalidQualityReport:
            "The meeting session contains invalid aggregate quality metrics."
        case let .unsafeRelativePath(path):
            "The meeting session contains an unsafe relative path: \(path)"
        case .derivedPathOverwritesOriginal:
            "A derived artifact must not overwrite an original track."
        case .invalidSessionState:
            "The meeting session status does not match its track states."
        case .invalidCompletion:
            "A completed meeting requires a transcript and an explicit valid completion mode."
        }
    }
}

nonisolated enum MixedRecordingConsentGate: Sendable, Equatable {
    case notRequired
    case confirmationRequired
    case satisfied

    static func requirement(
        for source: RecordingAudioSource,
        hasCurrentConsent: Bool
    ) -> Self {
        guard source == .mixed else { return .notRequired }
        return hasCurrentConsent ? .satisfied : .confirmationRequired
    }

    var allowsRecording: Bool { self != .confirmationRequired }
}
