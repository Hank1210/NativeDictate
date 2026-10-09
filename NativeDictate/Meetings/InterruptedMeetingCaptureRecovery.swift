import Foundation

nonisolated protocol MeetingInterruptedCaptureRecovering: Sendable {
    func recover(sessionID: UUID) async throws -> MixedRecordingSession
}

nonisolated enum InterruptedMeetingCaptureRecoveryError: LocalizedError {
    case sessionNotFound(UUID)
    case unsafeAudioPath(RecordingTrackRole)
    case unreadableAudio(RecordingTrackRole, String)

    var errorDescription: String? {
        switch self {
        case let .sessionNotFound(id):
            "Meeting session \(id.uuidString) was not found."
        case let .unsafeAudioPath(role):
            "The preserved \(role.rawValue) track is outside the meeting tracks directory."
        case let .unreadableAudio(role, message):
            "The preserved \(role.rawValue) track could not be recovered: \(message)"
        }
    }
}

/// Rebuilds only the file metadata that could not be persisted when the app
/// stopped during capture. The original track files are opened read-only and
/// remain the authoritative artifacts.
actor InterruptedMeetingCaptureRecovery: MeetingInterruptedCaptureRecovering {
    private let store: any TrackTranscriptionSessionStoring
    private let inspector: AudioAssetInspector
    private let synchronizationAnalyzer: SynchronizationAnalyzer
    private let qualityAnalyzer: MeetingQualityAnalyzer
    private let now: @Sendable () -> Date

    init(
        store: any TrackTranscriptionSessionStoring,
        inspector: AudioAssetInspector = AudioAssetInspector(),
        synchronizationAnalyzer: SynchronizationAnalyzer = SynchronizationAnalyzer(),
        qualityAnalyzer: MeetingQualityAnalyzer = MeetingQualityAnalyzer(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.inspector = inspector
        self.synchronizationAnalyzer = synchronizationAnalyzer
        self.qualityAnalyzer = qualityAnalyzer
        self.now = now
    }

    func recover(sessionID: UUID) async throws -> MixedRecordingSession {
        guard var session = try await store.load(sessionID: sessionID) else {
            throw InterruptedMeetingCaptureRecoveryError.sessionNotFound(sessionID)
        }
        guard Self.canRecover(session.status),
              session.tracks.contains(where: { $0.status == .interrupted }) else {
            return session
        }

        let paths = try await store.prepareSession(id: sessionID)
        var processedTrackCount = 0
        var recoveredIncompleteCaptureMetadata = false

        for index in session.tracks.indices where session.tracks[index].status == .interrupted {
            let track = session.tracks[index]
            guard track.audioRelativePath != nil else {
                markUnavailable(&session.tracks[index], category: .storageUnavailable)
                processedTrackCount += 1
                continue
            }
            let sourceURL = try sourceURL(
                for: track,
                sessionDirectory: paths.sessionDirectory,
                tracksDirectory: paths.tracksDirectory
            )
            let inspection: AudioAssetInspection
            do {
                inspection = try await inspector.inspect(sourceURL)
            } catch {
                markUnavailable(
                    &session.tracks[index],
                    category: FileManager.default.fileExists(atPath: sourceURL.path)
                        ? .audioCorrupt : .storageUnavailable
                )
                processedTrackCount += 1
                continue
            }

            recoveredIncompleteCaptureMetadata = recoveredIncompleteCaptureMetadata
                || track.formatIdentifier?.isEmpty != false
                || track.sampleRate <= 0
                || track.channelCount <= 0
                || track.durationMilliseconds <= 0
                || track.byteCount <= 0

            session.tracks[index].status = .finalized
            session.tracks[index].formatIdentifier = track.formatIdentifier?.isEmpty == false
                ? track.formatIdentifier
                : Self.formatIdentifier(for: sourceURL)
            session.tracks[index].sampleRate = inspection.sampleRate
            session.tracks[index].channelCount = inspection.channelCount
            session.tracks[index].durationMilliseconds = inspection.durationMilliseconds
            session.tracks[index].byteCount = inspection.byteCount
            session.tracks[index].errorCategory = nil
            session.tracks[index].errorMessage = nil
            processedTrackCount += 1
        }

        guard processedTrackCount > 0 else { return session }
        if let unavailable = session.tracks.first(where: { $0.status == .unavailable }) {
            session.lastErrorCategory = unavailable.errorCategory
            session.lastErrorMessage = "At least one preserved meeting track could not be read after capture was interrupted."
        }
        var synchronization = synchronizationAnalyzer.analyze(tracks: session.tracks)
        // A process crash prevents the recorders from persisting their final
        // timing anchors and gap/quality counters. A shared start anchor still
        // gives us a usable timeline, but it must not be reported as pristine.
        if recoveredIncompleteCaptureMetadata, synchronization.quality == .good {
            synchronization.quality = .degraded
        }
        session.synchronization = synchronization
        session.qualityReport = qualityAnalyzer.analyze(
            tracks: session.tracks,
            synchronization: synchronization
        )
        session.updatedAt = max(now(), session.updatedAt)
        try await store.save(session)
        return session
    }

    private func markUnavailable(
        _ track: inout MeetingAudioTrack,
        category: DictationErrorCategory
    ) {
        track.status = .unavailable
        track.errorCategory = category
        track.errorMessage = "The preserved original could not be read after capture was interrupted."
    }

    private func sourceURL(
        for track: MeetingAudioTrack,
        sessionDirectory: URL,
        tracksDirectory: URL
    ) throws -> URL {
        guard let relativePath = track.audioRelativePath else {
            throw InterruptedMeetingCaptureRecoveryError.unreadableAudio(
                track.role,
                "The manifest has no original track path."
            )
        }
        let candidate = sessionDirectory.appendingPathComponent(relativePath)
            .standardizedFileURL.resolvingSymlinksInPath()
        let safeDirectory = tracksDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.isDescendant(candidate, of: safeDirectory) else {
            throw InterruptedMeetingCaptureRecoveryError.unsafeAudioPath(track.role)
        }
        return candidate
    }

    private nonisolated static func canRecover(_ status: MeetingSessionStatus) -> Bool {
        [.queued, .transcribing, .merging, .partial, .paused, .failed].contains(status)
    }

    private nonisolated static func formatIdentifier(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a", "aac": "aac"
        default: "lpcm"
        }
    }

    private nonisolated static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let directoryPath = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return candidate.path.hasPrefix(directoryPath)
    }
}
