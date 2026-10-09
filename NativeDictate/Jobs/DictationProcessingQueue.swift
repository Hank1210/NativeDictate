import Foundation

actor DictationProcessingQueue {
    let maximumWaitingJobs: Int
    private let store: DictationJobStore
    private var reservations = 0
    private var activeJobID: UUID?
    private var activeMeetingSessionID: UUID?

    init(store: DictationJobStore, maximumWaitingJobs: Int = 5) {
        self.store = store
        self.maximumWaitingJobs = maximumWaitingJobs
    }

    func reserveRecordingSlot() async throws -> DictationQueueSnapshot {
        guard activeMeetingSessionID == nil else {
            throw DictationQueueError.meetingProcessingBusy
        }
        let jobs = try await store.all()
        let queued = jobs.filter { $0.status == .queued }.count
        let processing = activeJobID == nil ? 0 : 1
        guard queued + reservations < maximumWaitingJobs else {
            throw DictationQueueError.full(maximumWaiting: maximumWaitingJobs)
        }
        reservations += 1
        return DictationQueueSnapshot(
            processingCount: processing,
            queuedCount: queued,
            reservationCount: reservations
        )
    }

    func releaseRecordingSlot() async throws -> DictationQueueSnapshot {
        guard reservations > 0 else { throw DictationQueueError.reservationMissing }
        reservations -= 1
        return try await snapshot()
    }

    func commit(_ job: DictationJob) async throws -> DictationQueueSnapshot {
        guard reservations > 0 else { throw DictationQueueError.reservationMissing }
        try await store.create(job)
        reservations -= 1
        return try await snapshot()
    }

    func next() async throws -> DictationJob? {
        guard activeJobID == nil, activeMeetingSessionID == nil else { return nil }
        guard var job = try await store.all().first(where: { $0.status == .queued }) else { return nil }
        job.status = .preparing
        job.updatedAt = Date()
        try await store.update(job)
        activeJobID = job.id
        return job
    }

    func didFinish(_ job: DictationJob) async throws -> DictationQueueSnapshot {
        try await store.update(job)
        if activeJobID == job.id { activeJobID = nil }
        return try await snapshot()
    }

    /// Releases a successfully inserted job immediately. Its existing recovery
    /// manifest is deleted only after the completed History snapshot is durable.
    func releaseAfterInsertion(id: UUID) {
        if activeJobID == id { activeJobID = nil }
    }

    func cancelQueued(id: UUID) async throws -> DictationQueueSnapshot {
        guard var job = try await store.job(id: id), job.status == .queued else {
            throw DictationQueueError.jobNotCancellable
        }
        job.status = .cancelled
        job.updatedAt = Date()
        try await store.update(job)
        return try await snapshot()
    }

    /// Meeting track processing owns the same exclusive resource lane as a
    /// normal transcription job. It starts only when no recording reservation,
    /// queued dictation, or active job exists.
    func beginMeetingProcessing(sessionID: UUID) async throws -> DictationQueueSnapshot {
        let jobs = try await store.all()
        guard activeMeetingSessionID == nil,
              activeJobID == nil,
              reservations == 0,
              !jobs.contains(where: { $0.status == .queued }) else {
            throw DictationQueueError.meetingProcessingBusy
        }
        activeMeetingSessionID = sessionID
        return try await snapshot()
    }

    /// Idempotent for stale cleanup calls, but never releases another meeting's
    /// slot when an old task completes late.
    func finishMeetingProcessing(sessionID: UUID) async -> DictationQueueSnapshot {
        if activeMeetingSessionID == sessionID {
            activeMeetingSessionID = nil
        }
        return (try? await snapshot()) ?? DictationQueueSnapshot(
            processingCount: activeJobID == nil && activeMeetingSessionID == nil ? 0 : 1,
            queuedCount: 0,
            reservationCount: reservations
        )
    }

    func snapshot() async throws -> DictationQueueSnapshot {
        let jobs = try await store.all()
        return DictationQueueSnapshot(
            processingCount: activeJobID == nil && activeMeetingSessionID == nil ? 0 : 1,
            queuedCount: jobs.filter { $0.status == .queued }.count,
            reservationCount: reservations
        )
    }
}
