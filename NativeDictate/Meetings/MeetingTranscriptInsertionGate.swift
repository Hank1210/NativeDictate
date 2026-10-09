import Foundation

nonisolated enum MeetingTranscriptInsertionDecision: Sendable, Equatable {
    case authorized(String)
    case alreadyCompleted
    case deferred
    case requiresReview
}

nonisolated enum MeetingTranscriptInsertionError: LocalizedError, Equatable {
    case sessionNotFound(UUID)
    case transcriptNotReady
    case invalidTransition(MeetingTranscriptInsertionState?)

    var errorDescription: String? {
        switch self {
        case let .sessionNotFound(id):
            "Meeting session \(id.uuidString) was not found."
        case .transcriptNotReady:
            "The merged meeting transcript is not ready for insertion."
        case let .invalidTransition(state):
            "Meeting transcript insertion cannot continue from \(state?.rawValue ?? "no state")."
        }
    }
}

nonisolated protocol MeetingTranscriptInsertionGating: Sendable {
    func begin(
        sessionID: UUID,
        targetIsAvailable: Bool
    ) async throws -> MeetingTranscriptInsertionDecision
    func markCompleted(sessionID: UUID) async throws
    func markDeferred(sessionID: UUID) async throws
}

/// Persists the insertion boundary before external UI automation begins. If
/// FlowDictate stops after that boundary, a restart reports `requiresReview`
/// instead of risking a duplicate paste.
actor MeetingTranscriptInsertionGate {
    private let store: any MeetingTranscriptMergeSessionStoring
    private let now: @Sendable () -> Date

    init(
        store: any MeetingTranscriptMergeSessionStoring,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
    }

    func begin(
        sessionID: UUID,
        targetIsAvailable: Bool
    ) async throws -> MeetingTranscriptInsertionDecision {
        guard var session = try await store.load(sessionID: sessionID) else {
            throw MeetingTranscriptInsertionError.sessionNotFound(sessionID)
        }
        guard session.status == .completed,
              let text = session.finalTranscript,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeetingTranscriptInsertionError.transcriptNotReady
        }

        switch session.transcriptInsertionState ?? .ready {
        case .completed:
            return .alreadyCompleted
        case .attempting:
            session.transcriptInsertionState = .unknown
            updateTimestamp(&session)
            try await store.save(session)
            return .requiresReview
        case .unknown:
            return .requiresReview
        case .deferred:
            return .deferred
        case .ready:
            guard targetIsAvailable else {
                session.transcriptInsertionState = .deferred
                session.transcriptInsertionAttemptCount = 0
                updateTimestamp(&session)
                try await store.save(session)
                return .deferred
            }
            session.transcriptInsertionState = .attempting
            session.transcriptInsertionAttemptCount = 1
            updateTimestamp(&session)
            try await store.save(session)
            return .authorized(text)
        }
    }

    func markCompleted(sessionID: UUID) async throws {
        guard var session = try await store.load(sessionID: sessionID) else {
            throw MeetingTranscriptInsertionError.sessionNotFound(sessionID)
        }
        guard session.transcriptInsertionState == .attempting,
              session.transcriptInsertionAttemptCount == 1 else {
            throw MeetingTranscriptInsertionError.invalidTransition(
                session.transcriptInsertionState
            )
        }
        session.transcriptInsertionState = .completed
        updateTimestamp(&session)
        try await store.save(session)
    }

    func markDeferred(sessionID: UUID) async throws {
        guard var session = try await store.load(sessionID: sessionID) else {
            throw MeetingTranscriptInsertionError.sessionNotFound(sessionID)
        }
        guard session.transcriptInsertionState == .attempting else {
            throw MeetingTranscriptInsertionError.invalidTransition(
                session.transcriptInsertionState
            )
        }
        session.transcriptInsertionState = .deferred
        updateTimestamp(&session)
        try await store.save(session)
    }

    private func updateTimestamp(_ session: inout MixedRecordingSession) {
        session.updatedAt = max(now(), session.updatedAt)
    }
}

extension MeetingTranscriptInsertionGate: MeetingTranscriptInsertionGating {}
