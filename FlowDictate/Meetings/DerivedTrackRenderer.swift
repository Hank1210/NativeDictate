@preconcurrency import AVFoundation
import Foundation
import os

nonisolated struct DerivedTrackArtifact: Sendable, Equatable {
    var role: RecordingTrackRole
    var relativePath: String
    var sampleRate: Double
    var frameCount: Int64
    var durationMilliseconds: Int64
    var byteCount: Int64
    var prependedSilenceMilliseconds: Int64
    var insertedGapDurationMilliseconds: Int64
    var appliedDriftPartsPerMillion: Double?
}

nonisolated struct DerivedTrackRenderResult: Sendable, Equatable {
    var tracks: [DerivedTrackArtifact]
}

nonisolated enum DerivedTrackRendererError: LocalizedError, Equatable {
    case synchronizationUnavailable
    case synchronizationUnreliable
    case missingTrack(RecordingTrackRole)
    case missingSource(RecordingTrackRole)
    case unsafeSourcePath(RecordingTrackRole)
    case unsafeDestinationPath(RecordingTrackRole)
    case destinationOverwritesOriginal(RecordingTrackRole)
    case unsupportedSourceFormat(RecordingTrackRole)
    case invalidDrift(Double)
    case conversionFailed(RecordingTrackRole, String)

    var errorDescription: String? {
        switch self {
        case .synchronizationUnavailable:
            "The meeting has no usable synchronization report."
        case .synchronizationUnreliable:
            "The meeting timeline is too unreliable to render aligned tracks automatically."
        case let .missingTrack(role):
            "The \(role.rawValue) track is missing."
        case let .missingSource(role):
            "The original \(role.rawValue) track is unavailable."
        case let .unsafeSourcePath(role):
            "The original \(role.rawValue) track is outside the meeting tracks directory."
        case let .unsafeDestinationPath(role):
            "The derived \(role.rawValue) destination is outside the meeting derived directory."
        case let .destinationOverwritesOriginal(role):
            "The derived \(role.rawValue) track must not overwrite an original track."
        case let .unsupportedSourceFormat(role):
            "The \(role.rawValue) track does not provide supported Float32 PCM for alignment."
        case let .invalidDrift(partsPerMillion):
            "The requested drift correction is invalid (\(partsPerMillion) ppm)."
        case let .conversionFailed(role, message):
            "The \(role.rawValue) derived track could not be rendered: \(message)"
        }
    }
}

nonisolated final class DerivedTrackRenderer: @unchecked Sendable {
    static let defaultDestinationPaths: [RecordingTrackRole: String] = [
        .localSpeaker: "derived/aligned-microphone.caf",
        .systemAudio: "derived/aligned-system-audio.caf"
    ]

    private let fileManager: FileManager
    private let targetSampleRate: Double
    private let destinationPaths: [RecordingTrackRole: String]

    init(
        fileManager: FileManager = .default,
        targetSampleRate: Double = 48_000,
        destinationPaths: [RecordingTrackRole: String] = DerivedTrackRenderer.defaultDestinationPaths
    ) {
        self.fileManager = fileManager
        self.targetSampleRate = targetSampleRate
        self.destinationPaths = destinationPaths
    }

    func render(
        session: MixedRecordingSession,
        sessionDirectory: URL
    ) async throws -> DerivedTrackRenderResult {
        let validated = try session.validated()
        let signpost = NativeDictateLogger.meetingSignposter.beginInterval(
            "Meeting Derived Render", id: .exclusive,
            "session: \(validated.id.uuidString, privacy: .public)"
        )
        defer { NativeDictateLogger.meetingSignposter.endInterval("Meeting Derived Render", signpost) }
        guard let synchronization = validated.synchronization else {
            throw DerivedTrackRendererError.synchronizationUnavailable
        }
        guard synchronization.quality != .notAnalyzed else {
            throw DerivedTrackRendererError.synchronizationUnavailable
        }
        guard synchronization.quality != .unreliable else {
            throw DerivedTrackRendererError.synchronizationUnreliable
        }
        guard targetSampleRate.isFinite, targetSampleRate > 0 else {
            throw DerivedTrackRendererError.conversionFailed(
                .localSpeaker,
                "The target sample rate is invalid."
            )
        }

        let plans = try makePlans(
            session: validated,
            synchronization: synchronization,
            sessionDirectory: sessionDirectory
        )
        let fileManager = fileManager
        let targetSampleRate = targetSampleRate
        let result = try await Task.detached(priority: .utility) {
            var artifacts: [DerivedTrackArtifact] = []
            for plan in plans {
                try Task.checkCancellation()
                artifacts.append(
                    try Self.render(plan, targetSampleRate: targetSampleRate, fileManager: fileManager)
                )
            }
            return DerivedTrackRenderResult(tracks: artifacts)
        }.value
        for track in result.tracks {
            NativeDictateLogger.meetingSignposter.emitEvent(
                "Meeting Derived Track", id: .exclusive,
                "role: \(track.role.rawValue, privacy: .public), frames: \(track.frameCount), bytes: \(track.byteCount)"
            )
        }
        return result
    }

    private func makePlans(
        session: MixedRecordingSession,
        synchronization: SynchronizationReport,
        sessionDirectory: URL
    ) throws -> [DerivedTrackRenderPlan] {
        let root = sessionDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let tracksDirectory = root.appendingPathComponent("tracks", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let derivedDirectory = root.appendingPathComponent("derived", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        try fileManager.createDirectory(
            at: derivedDirectory,
            withIntermediateDirectories: true
        )

        let initialOffset = synchronization.initialOffsetMilliseconds ?? 0
        let containsGaps = session.tracks.contains { !$0.gaps.isEmpty }
        // A global resampling factor must never conceal a discontinuity. The
        // analyzer normally omits drift for gapped sessions; repeat that guard
        // here because manifests can be imported or recovered independently.
        let relativeDrift = containsGaps
            ? nil
            : synchronization.estimatedDriftPartsPerMillion
        if let relativeDrift,
           !relativeDrift.isFinite || abs(relativeDrift) > 50_000 {
            throw DerivedTrackRendererError.invalidDrift(relativeDrift)
        }

        let originalPaths = Set(session.tracks.compactMap { track -> String? in
            guard let path = track.audioRelativePath else { return nil }
            return root.appendingPathComponent(path).standardizedFileURL.path
        })

        return try RecordingTrackRole.allCases.map { role in
            guard let track = session.tracks.first(where: { $0.role == role }) else {
                throw DerivedTrackRendererError.missingTrack(role)
            }
            guard let sourceRelativePath = track.audioRelativePath else {
                throw DerivedTrackRendererError.missingSource(role)
            }
            let sourceURL = root.appendingPathComponent(sourceRelativePath)
                .standardizedFileURL.resolvingSymlinksInPath()
            guard Self.isDescendant(sourceURL, of: tracksDirectory) else {
                throw DerivedTrackRendererError.unsafeSourcePath(role)
            }
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw DerivedTrackRendererError.missingSource(role)
            }
            guard let destinationRelativePath = destinationPaths[role] else {
                throw DerivedTrackRendererError.unsafeDestinationPath(role)
            }
            let destinationURL = root.appendingPathComponent(destinationRelativePath)
                .standardizedFileURL
            guard !originalPaths.contains(destinationURL.path),
                  destinationURL.path != sourceURL.path else {
                throw DerivedTrackRendererError.destinationOverwritesOriginal(role)
            }
            let resolvedDestinationParent = destinationURL.deletingLastPathComponent()
                .resolvingSymlinksInPath()
            guard Self.isDescendant(resolvedDestinationParent, of: derivedDirectory),
                  destinationURL.pathExtension.lowercased() == "caf" else {
                throw DerivedTrackRendererError.unsafeDestinationPath(role)
            }

            let padding = role == .localSpeaker
                ? max(0, initialOffset)
                : max(0, -initialOffset)
            return DerivedTrackRenderPlan(
                role: role,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                destinationRelativePath: destinationRelativePath,
                prependedSilenceMilliseconds: Int64(padding.rounded()),
                gaps: track.gaps,
                driftPartsPerMillion: role == .localSpeaker ? relativeDrift : nil
            )
        }
    }

    private static func render(
        _ plan: DerivedTrackRenderPlan,
        targetSampleRate: Double,
        fileManager: FileManager
    ) throws -> DerivedTrackArtifact {
        let temporaryURL = plan.destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(plan.destinationURL.lastPathComponent).\(UUID()).tmp.caf")
        try? fileManager.removeItem(at: temporaryURL)
        do {
            let source = try AVAudioFile(forReading: plan.sourceURL)
            let sourceFormat = source.processingFormat
            guard sourceFormat.commonFormat == .pcmFormatFloat32,
                  !sourceFormat.isInterleaved,
                  sourceFormat.sampleRate > 0,
                  sourceFormat.channelCount > 0 else {
                throw DerivedTrackRendererError.unsupportedSourceFormat(plan.role)
            }
            let scale = 1 + (plan.driftPartsPerMillion ?? 0) / 1_000_000
            guard scale.isFinite, scale > 0 else {
                throw DerivedTrackRendererError.invalidDrift(
                    plan.driftPartsPerMillion ?? 0
                )
            }
            guard let effectiveInputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sourceFormat.sampleRate / scale,
                channels: sourceFormat.channelCount,
                interleaved: false
            ), let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            ), let converter = AVAudioConverter(
                from: effectiveInputFormat,
                to: outputFormat
            ) else {
                throw DerivedTrackRendererError.conversionFailed(
                    plan.role,
                    "AVAudioConverter could not create the requested conversion."
                )
            }

            var output: AVAudioFile? = try AVAudioFile(
                forWriting: temporaryURL,
                settings: outputFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            let paddingFrames = AVAudioFramePosition(
                (Double(plan.prependedSilenceMilliseconds) * targetSampleRate / 1_000).rounded()
            )
            try writeSilence(
                frameCount: paddingFrames,
                format: outputFormat,
                output: output!,
                role: plan.role
            )

            let input = try DerivedPCMInputSequence(
                source: source,
                effectiveFormat: effectiveInputFormat,
                gaps: plan.gaps,
                role: plan.role
            )
            var inputError: Error?
            var consecutiveEmptyPasses = 0
            while true {
                try Task.checkCancellation()
                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: 32_768
                ) else {
                    throw DerivedTrackRendererError.conversionFailed(
                        plan.role,
                        "Could not allocate an output buffer."
                    )
                }
                var conversionError: NSError?
                let status = converter.convert(
                    to: outputBuffer,
                    error: &conversionError
                ) { requestedFrames, inputStatus in
                    do {
                        if let buffer = try input.next(maximumFrameCount: requestedFrames) {
                            inputStatus.pointee = .haveData
                            return buffer
                        }
                        inputStatus.pointee = .endOfStream
                        return nil
                    } catch {
                        inputError = error
                        inputStatus.pointee = .noDataNow
                        return nil
                    }
                }
                if let inputError { throw inputError }
                if let conversionError { throw conversionError }
                if outputBuffer.frameLength > 0 {
                    try output?.write(from: outputBuffer)
                    consecutiveEmptyPasses = 0
                } else {
                    consecutiveEmptyPasses += 1
                }
                switch status {
                case .endOfStream:
                    break
                case .error:
                    throw DerivedTrackRendererError.conversionFailed(
                        plan.role,
                        "AVAudioConverter reported an error."
                    )
                case .inputRanDry where consecutiveEmptyPasses > 2:
                    throw DerivedTrackRendererError.conversionFailed(
                        plan.role,
                        "Audio conversion stopped before reaching the end of the source."
                    )
                default:
                    continue
                }
                break
            }
            output = nil

            if fileManager.fileExists(atPath: plan.destinationURL.path) {
                _ = try fileManager.replaceItemAt(
                    plan.destinationURL,
                    withItemAt: temporaryURL
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: plan.destinationURL)
            }
            let rendered = try AVAudioFile(forReading: plan.destinationURL)
            let byteCount = Int64(
                try plan.destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            )
            return DerivedTrackArtifact(
                role: plan.role,
                relativePath: plan.destinationRelativePath,
                sampleRate: rendered.processingFormat.sampleRate,
                frameCount: rendered.length,
                durationMilliseconds: Int64(
                    (Double(rendered.length) / rendered.processingFormat.sampleRate * 1_000)
                        .rounded()
                ),
                byteCount: byteCount,
                prependedSilenceMilliseconds: plan.prependedSilenceMilliseconds,
                insertedGapDurationMilliseconds: plan.gaps.reduce(0) {
                    $0 + $1.durationMilliseconds
                },
                appliedDriftPartsPerMillion: plan.driftPartsPerMillion
            )
        } catch let error as DerivedTrackRendererError {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw DerivedTrackRendererError.conversionFailed(
                plan.role,
                error.localizedDescription
            )
        }
    }

    private static func writeSilence(
        frameCount: AVAudioFramePosition,
        format: AVAudioFormat,
        output: AVAudioFile,
        role: RecordingTrackRole
    ) throws {
        var remaining = frameCount
        while remaining > 0 {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(remaining, 32_768))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: count
            ), let channels = buffer.floatChannelData else {
                throw DerivedTrackRendererError.conversionFailed(
                    role,
                    "Could not allocate a silence buffer."
                )
            }
            buffer.frameLength = count
            for channel in 0..<Int(format.channelCount) {
                channels[channel].initialize(repeating: 0, count: Int(count))
            }
            try output.write(from: buffer)
            remaining -= AVAudioFramePosition(count)
        }
    }

    private static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        candidate.path == directory.path
            || candidate.path.hasPrefix(directory.path + "/")
    }
}

private nonisolated struct DerivedTrackRenderPlan: Sendable {
    var role: RecordingTrackRole
    var sourceURL: URL
    var destinationURL: URL
    var destinationRelativePath: String
    var prependedSilenceMilliseconds: Int64
    var gaps: [TrackGap]
    var driftPartsPerMillion: Double?
}

private nonisolated final class DerivedPCMInputSequence: @unchecked Sendable {
    private struct Gap {
        var sourceFrame: AVAudioFramePosition
        var remainingFrames: AVAudioFramePosition
    }

    private let source: AVAudioFile
    private let sourceFormat: AVAudioFormat
    private let effectiveFormat: AVAudioFormat
    private let role: RecordingTrackRole
    private var gaps: [Gap]
    private var gapIndex = 0

    init(
        source: AVAudioFile,
        effectiveFormat: AVAudioFormat,
        gaps: [TrackGap],
        role: RecordingTrackRole
    ) throws {
        self.source = source
        sourceFormat = source.processingFormat
        self.effectiveFormat = effectiveFormat
        self.role = role
        self.gaps = gaps.map { gap in
            Gap(
                sourceFrame: AVAudioFramePosition(
                    (Double(gap.startMilliseconds) * source.processingFormat.sampleRate / 1_000)
                        .rounded()
                ),
                remainingFrames: AVAudioFramePosition(
                    (Double(gap.durationMilliseconds) * source.processingFormat.sampleRate / 1_000)
                        .rounded()
                )
            )
        }
    }

    func next(maximumFrameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        let capacity = max(1, maximumFrameCount)
        if gapIndex < gaps.count,
           source.framePosition >= gaps[gapIndex].sourceFrame,
           gaps[gapIndex].remainingFrames > 0 {
            let count = AVAudioFrameCount(
                min(AVAudioFramePosition(capacity), gaps[gapIndex].remainingFrames)
            )
            let buffer = try makeBuffer(frameCount: count)
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) {
                    channels[channel].initialize(repeating: 0, count: Int(count))
                }
            }
            gaps[gapIndex].remainingFrames -= AVAudioFramePosition(count)
            if gaps[gapIndex].remainingFrames == 0 { gapIndex += 1 }
            return buffer
        }

        guard source.framePosition < source.length else { return nil }
        var count = AVAudioFramePosition(capacity)
        if gapIndex < gaps.count {
            count = min(count, gaps[gapIndex].sourceFrame - source.framePosition)
        }
        if count <= 0 {
            gapIndex += 1
            return try next(maximumFrameCount: maximumFrameCount)
        }
        count = min(count, source.length - source.framePosition)
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(count)
        ) else {
            throw DerivedTrackRendererError.conversionFailed(
                role,
                "Could not allocate a source buffer."
            )
        }
        try source.read(into: sourceBuffer, frameCount: AVAudioFrameCount(count))
        guard sourceBuffer.frameLength > 0 else { return nil }
        let effectiveBuffer = try makeBuffer(frameCount: sourceBuffer.frameLength)
        guard let sourceChannels = sourceBuffer.floatChannelData,
              let destinationChannels = effectiveBuffer.floatChannelData else {
            throw DerivedTrackRendererError.conversionFailed(
                role,
                "The source buffer is not accessible as Float32 PCM."
            )
        }
        for channel in 0..<Int(sourceFormat.channelCount) {
            destinationChannels[channel].update(
                from: sourceChannels[channel],
                count: Int(sourceBuffer.frameLength)
            )
        }
        return effectiveBuffer
    }

    private func makeBuffer(frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: effectiveFormat,
            frameCapacity: frameCount
        ) else {
            throw DerivedTrackRendererError.conversionFailed(
                role,
                "Could not allocate a drift-correction buffer."
            )
        }
        buffer.frameLength = frameCount
        return buffer
    }
}
