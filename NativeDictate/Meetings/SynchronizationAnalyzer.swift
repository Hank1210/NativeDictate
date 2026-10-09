import Foundation

/// Builds the shared timing summary without changing either original track.
/// A positive initial offset means the microphone started after System Audio.
nonisolated struct SynchronizationAnalyzer: Sendable {
    struct Configuration: Sendable, Equatable {
        var minimumDriftSpanMilliseconds: Double = 30_000
        var goodInitialOffsetMilliseconds: Double = 250
        var maximumReliableInitialOffsetMilliseconds: Double = 2_000
        var goodRelativeDriftPartsPerMillion: Double = 250
        var maximumReliableRelativeDriftPartsPerMillion: Double = 2_000
        var goodResidualMilliseconds: Double = 20
        var maximumReliableResidualMilliseconds: Double = 100
        var maximumReliableGapRatio: Double = 0.10
    }

    private struct LinearFit {
        var slope: Double
        var maximumResidualMilliseconds: Double
        var spanMilliseconds: Double
    }

    private let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func analyze(tracks: [MeetingAudioTrack]) -> SynchronizationReport {
        let microphone = tracks.first { $0.role == .localSpeaker }
        let systemAudio = tracks.first { $0.role == .systemAudio }
        let analyzedAnchorCount = [microphone, systemAudio]
            .compactMap { $0 }
            .reduce(0) { $0 + $1.timestampAnchors.count }

        guard let microphone,
              let systemAudio,
              isAnalyzable(microphone),
              isAnalyzable(systemAudio),
              anchorsAreMonotonic(microphone),
              anchorsAreMonotonic(systemAudio),
              let microphoneStart = microphone.timestampAnchors.first,
              let systemAudioStart = systemAudio.timestampAnchors.first else {
            return SynchronizationReport(
                quality: .notAnalyzed,
                initialOffsetMilliseconds: nil,
                estimatedDriftPartsPerMillion: nil,
                residualDriftMilliseconds: nil,
                analyzedAnchorCount: analyzedAnchorCount
            )
        }

        let initialOffset = Double(
            microphoneStart.sessionTimeMilliseconds
                - systemAudioStart.sessionTimeMilliseconds
        )
        let hasGaps = !microphone.gaps.isEmpty || !systemAudio.gaps.isEmpty
        let gapDuration = microphone.gaps.reduce(Int64(0)) { $0 + $1.durationMilliseconds }
            + systemAudio.gaps.reduce(Int64(0)) { $0 + $1.durationMilliseconds }
        let recordedDuration = max(
            1,
            microphone.durationMilliseconds + systemAudio.durationMilliseconds
        )
        let gapRatio = Double(gapDuration) / Double(recordedDuration)

        var relativeDrift: Double?
        var residual: Double?
        if !hasGaps,
           let microphoneFit = linearFit(for: microphone),
           let systemAudioFit = linearFit(for: systemAudio),
           microphoneFit.spanMilliseconds >= configuration.minimumDriftSpanMilliseconds,
           systemAudioFit.spanMilliseconds >= configuration.minimumDriftSpanMilliseconds,
           systemAudioFit.slope > 0 {
            relativeDrift = (microphoneFit.slope / systemAudioFit.slope - 1) * 1_000_000
            residual = max(
                microphoneFit.maximumResidualMilliseconds,
                systemAudioFit.maximumResidualMilliseconds
            )
        }

        let absoluteOffset = abs(initialOffset)
        let absoluteDrift = abs(relativeDrift ?? 0)
        let measuredResidual = residual ?? 0
        let quality: MeetingSynchronizationQuality
        if absoluteOffset > configuration.maximumReliableInitialOffsetMilliseconds
            || absoluteDrift > configuration.maximumReliableRelativeDriftPartsPerMillion
            || measuredResidual > configuration.maximumReliableResidualMilliseconds
            || gapRatio > configuration.maximumReliableGapRatio {
            quality = .unreliable
        } else if hasGaps
            || absoluteOffset > configuration.goodInitialOffsetMilliseconds
            || absoluteDrift > configuration.goodRelativeDriftPartsPerMillion
            || measuredResidual > configuration.goodResidualMilliseconds {
            quality = .degraded
        } else {
            quality = .good
        }

        return SynchronizationReport(
            quality: quality,
            initialOffsetMilliseconds: initialOffset,
            estimatedDriftPartsPerMillion: relativeDrift,
            residualDriftMilliseconds: residual,
            analyzedAnchorCount: analyzedAnchorCount
        )
    }

    private func isAnalyzable(_ track: MeetingAudioTrack) -> Bool {
        let hasCapturedAudio: Bool
        switch track.status {
        case .finalized, .transcriptionPending, .transcribing, .transcribed:
            hasCapturedAudio = true
        default:
            hasCapturedAudio = false
        }
        return hasCapturedAudio
            && track.sampleRate > 0
            && track.durationMilliseconds > 0
            && !track.timestampAnchors.isEmpty
    }

    private func anchorsAreMonotonic(_ track: MeetingAudioTrack) -> Bool {
        for (index, anchor) in track.timestampAnchors.enumerated() {
            guard anchor.trackFramePosition >= 0,
                  anchor.sessionTimeMilliseconds >= 0 else { return false }
            guard index > 0 else { continue }
            let previous = track.timestampAnchors[index - 1]
            guard anchor.hostTime > previous.hostTime,
                  anchor.trackFramePosition > previous.trackFramePosition,
                  anchor.sessionTimeMilliseconds >= previous.sessionTimeMilliseconds else {
                return false
            }
        }
        return true
    }

    private func linearFit(for track: MeetingAudioTrack) -> LinearFit? {
        guard track.timestampAnchors.count >= 2,
              track.sampleRate > 0,
              let first = track.timestampAnchors.first else { return nil }
        let points = track.timestampAnchors.map { anchor in
            (
                x: Double(anchor.trackFramePosition - first.trackFramePosition)
                    / track.sampleRate * 1_000,
                y: Double(anchor.sessionTimeMilliseconds - first.sessionTimeMilliseconds)
            )
        }
        let meanX = points.reduce(0) { $0 + $1.x } / Double(points.count)
        let meanY = points.reduce(0) { $0 + $1.y } / Double(points.count)
        let denominator = points.reduce(0) { total, point in
            total + pow(point.x - meanX, 2)
        }
        guard denominator > 0 else { return nil }
        let slope = points.reduce(0) { total, point in
            total + (point.x - meanX) * (point.y - meanY)
        } / denominator
        guard slope.isFinite, slope > 0 else { return nil }
        let intercept = meanY - slope * meanX
        let maximumResidual = points.reduce(0) { maximum, point in
            max(maximum, abs(point.y - (intercept + slope * point.x)))
        }
        return LinearFit(
            slope: slope,
            maximumResidualMilliseconds: maximumResidual,
            spanMilliseconds: points.last?.x ?? 0
        )
    }
}

nonisolated struct MeetingQualityAnalyzer: Sendable {
    func analyze(
        tracks: [MeetingAudioTrack],
        synchronization: SynchronizationReport
    ) -> MeetingQualityReport {
        let completeRoles = Set(tracks.compactMap { track -> RecordingTrackRole? in
            switch track.status {
            case .finalized, .transcriptionPending, .transcribing, .transcribed:
                track.role
            default:
                nil
            }
        })
        return MeetingQualityReport(
            synchronizationQuality: synchronization.quality,
            completeTrackRoles: completeRoles,
            totalGapCount: tracks.reduce(0) { $0 + $1.gaps.count },
            totalGapDurationMilliseconds: tracks.reduce(0) { total, track in
                total + track.gaps.reduce(Int64(0)) { $0 + $1.durationMilliseconds }
            },
            totalClippedFrameCount: tracks.reduce(0) {
                $0 + $1.quality.clippedFrameCount
            }
        )
    }
}
