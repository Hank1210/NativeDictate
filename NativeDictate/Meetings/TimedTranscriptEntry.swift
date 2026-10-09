import Foundation

/// A provider- or chunk-derived interval on one original track. Times remain
/// relative to that track until `TimedTranscriptMerger` maps them onto the
/// shared meeting timeline.
nonisolated struct TrackTranscriptEntry: Codable, Sendable, Equatable {
    var index: Int
    var startMilliseconds: Int64
    var endMilliseconds: Int64
    var text: String
    var precision: TranscriptTimestampPrecision
}

nonisolated struct TimedTranscriptEntry: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var role: RecordingTrackRole
    var sourceIndex: Int
    var trackStartMilliseconds: Int64
    var trackEndMilliseconds: Int64
    var sessionStartMilliseconds: Int64
    var sessionEndMilliseconds: Int64
    var text: String
    var precision: TranscriptTimestampPrecision

    var roleLabel: String {
        switch role {
        case .localSpeaker: "You"
        case .systemAudio: "System Audio"
        }
    }
}

nonisolated struct TimedTranscriptTimeline: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var meetingSessionID: UUID
    var entries: [TimedTranscriptEntry]
    var renderedText: String
    var createdAt: Date

    func validated() throws -> Self {
        guard schemaVersion == Self.currentSchemaVersion,
              !entries.isEmpty,
              Set(entries.map(\.id)).count == entries.count,
              !renderedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TimedTranscriptMergeError.invalidTimeline
        }
        for (offset, entry) in entries.enumerated() {
            guard entry.sourceIndex >= 0,
                  entry.trackStartMilliseconds >= 0,
                  entry.trackEndMilliseconds > entry.trackStartMilliseconds,
                  entry.sessionStartMilliseconds >= 0,
                  entry.sessionEndMilliseconds > entry.sessionStartMilliseconds,
                  !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TimedTranscriptMergeError.invalidTimeline
            }
            guard offset > 0 else { continue }
            let previous = entries[offset - 1]
            guard Self.isOrdered(previous, before: entry) else {
                throw TimedTranscriptMergeError.invalidTimeline
            }
        }
        return self
    }

    private static func isOrdered(
        _ left: TimedTranscriptEntry,
        before right: TimedTranscriptEntry
    ) -> Bool {
        if left.sessionStartMilliseconds != right.sessionStartMilliseconds {
            return left.sessionStartMilliseconds < right.sessionStartMilliseconds
        }
        if roleOrder(left.role) != roleOrder(right.role) {
            return roleOrder(left.role) < roleOrder(right.role)
        }
        return left.sourceIndex <= right.sourceIndex
    }

    private static func roleOrder(_ role: RecordingTrackRole) -> Int {
        switch role {
        case .localSpeaker: 0
        case .systemAudio: 1
        }
    }
}
