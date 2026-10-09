@preconcurrency import AVFoundation
import Foundation

nonisolated struct AudioSegmentPlanner: Sendable {
    typealias BoundaryResolver = @Sendable (
        _ nominalMilliseconds: Int64,
        _ lowerBoundMilliseconds: Int64,
        _ upperBoundMilliseconds: Int64
    ) async throws -> Int64?

    let configuration: LongFormConfiguration

    init(configuration: LongFormConfiguration = .default) {
        self.configuration = configuration
    }

    func plan(
        durationMilliseconds: Int64,
        boundaryResolver: BoundaryResolver? = nil
    ) async throws -> [TranscriptionSegment] {
        guard durationMilliseconds > 0 else {
            throw LongFormTranscriptionError.invalidSegmentPlan
        }
        if durationMilliseconds <= configuration.targetDurationMilliseconds {
            return [Self.segment(index: 0, start: 0, end: durationMilliseconds, overlap: 0)]
        }

        var boundaries: [Int64] = [0]
        var previousBoundary: Int64 = 0
        while durationMilliseconds - previousBoundary > configuration.maximumDurationMilliseconds {
            try Task.checkCancellation()
            let nominal = min(
                previousBoundary + configuration.targetDurationMilliseconds,
                durationMilliseconds
            )
            let lower = max(
                previousBoundary + configuration.minimumDurationMilliseconds,
                nominal - configuration.boundarySearchRadiusMilliseconds
            )
            let upper = min(
                previousBoundary + configuration.maximumDurationMilliseconds,
                nominal + configuration.boundarySearchRadiusMilliseconds,
                durationMilliseconds - 1
            )
            let resolved = try await boundaryResolver?(nominal, lower, upper)
            let boundary = min(max(resolved ?? nominal, lower), upper)
            guard boundary > previousBoundary else {
                throw LongFormTranscriptionError.invalidSegmentPlan
            }
            boundaries.append(boundary)
            previousBoundary = boundary
        }
        boundaries.append(durationMilliseconds)

        var result: [TranscriptionSegment] = []
        for index in 0..<(boundaries.count - 1) {
            let logicalStart = boundaries[index]
            let overlap = index == 0 ? 0 : min(
                configuration.fallbackOverlapMilliseconds,
                logicalStart
            )
            let actualStart = logicalStart - overlap
            result.append(Self.segment(
                index: index,
                start: actualStart,
                end: boundaries[index + 1],
                overlap: overlap
            ))
        }
        return try Self.validate(result, durationMilliseconds: durationMilliseconds)
    }

    static func validate(
        _ segments: [TranscriptionSegment],
        durationMilliseconds: Int64
    ) throws -> [TranscriptionSegment] {
        guard !segments.isEmpty,
              segments.first?.startMilliseconds == 0,
              segments.last?.endMilliseconds == durationMilliseconds else {
            throw LongFormTranscriptionError.invalidSegmentPlan
        }
        for (index, segment) in segments.enumerated() {
            guard segment.index == index,
                  segment.endMilliseconds > segment.startMilliseconds else {
                throw LongFormTranscriptionError.invalidSegmentPlan
            }
            if index > 0 {
                let previous = segments[index - 1]
                guard previous.endMilliseconds - segment.startMilliseconds
                        == segment.overlapBeforeMilliseconds else {
                    throw LongFormTranscriptionError.invalidSegmentPlan
                }
            }
        }
        return segments
    }

    private static func segment(
        index: Int,
        start: Int64,
        end: Int64,
        overlap: Int64
    ) -> TranscriptionSegment {
        TranscriptionSegment(
            id: UUID(),
            index: index,
            startMilliseconds: start,
            endMilliseconds: end,
            overlapBeforeMilliseconds: overlap,
            status: .pending,
            preparedRelativePath: nil,
            preparedByteCount: nil,
            transcript: nil,
            attemptCount: 0,
            lastAttemptAt: nil,
            errorCategory: nil,
            errorMessage: nil
        )
    }
}

nonisolated final class SilenceBoundaryDetector: @unchecked Sendable {
    private let maximumNormalizedRMS: Double

    init(maximumNormalizedRMS: Double = 0.025) {
        self.maximumNormalizedRMS = maximumNormalizedRMS
    }

    func boundary(
        in url: URL,
        nominalMilliseconds: Int64,
        lowerBoundMilliseconds: Int64,
        upperBoundMilliseconds: Int64
    ) async throws -> Int64? {
        let maximumNormalizedRMS = maximumNormalizedRMS
        return try await Task.detached(priority: .utility) {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard format.sampleRate > 0, upperBoundMilliseconds > lowerBoundMilliseconds else {
                return nil
            }
            let lowerFrame = AVAudioFramePosition(
                Double(lowerBoundMilliseconds) * format.sampleRate / 1_000
            )
            let upperFrame = min(
                AVAudioFramePosition(Double(upperBoundMilliseconds) * format.sampleRate / 1_000),
                file.length
            )
            file.framePosition = min(max(lowerFrame, 0), file.length)
            let capacity: AVAudioFrameCount = 4_096
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                return nil
            }
            var best: (score: Double, milliseconds: Int64, rms: Double)?
            while file.framePosition < upperFrame {
                try Task.checkCancellation()
                let remaining = upperFrame - file.framePosition
                let requested = AVAudioFrameCount(min(Int64(capacity), remaining))
                try file.read(into: buffer, frameCount: requested)
                guard buffer.frameLength > 0 else { break }
                let rms = Self.rms(buffer)
                let midpointFrame = file.framePosition - AVAudioFramePosition(buffer.frameLength / 2)
                let milliseconds = Int64(
                    (Double(midpointFrame) / format.sampleRate * 1_000).rounded()
                )
                let distance = abs(Double(milliseconds - nominalMilliseconds))
                    / max(Double(upperBoundMilliseconds - lowerBoundMilliseconds), 1)
                let score = rms + distance * 0.01
                if best == nil || score < best!.score {
                    best = (score, milliseconds, rms)
                }
            }
            guard let best, best.rms <= maximumNormalizedRMS else { return nil }
            return min(max(best.milliseconds, lowerBoundMilliseconds), upperBoundMilliseconds)
        }.value
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData else { return 1 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 1 }
        var sum = 0.0
        var count = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<frameCount {
                let value = Double(channels[channel][frame])
                sum += value * value
            }
            count += frameCount
        }
        return count > 0 ? sqrt(sum / Double(count)) : 1
    }
}

/// A provider's empty response is only treated as an intentional no-speech
/// segment when every original PCM sample is below the capture silence floor.
/// Checking the original (not the lossy working copy) keeps this conservative.
nonisolated final class SilentAudioSegmentDetector: @unchecked Sendable {
    func isSilent(in url: URL) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            let file = try AVAudioFile(forReading: url)
            return try Self.isSilent(file, from: 0, to: file.length)
        }.value
    }

    func isSilent(in url: URL, segment: TranscriptionSegment) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard format.sampleRate > 0,
                  segment.endMilliseconds > segment.startMilliseconds else {
                return false
            }
            let startFrame = min(max(AVAudioFramePosition(
                Double(segment.startMilliseconds) * format.sampleRate / 1_000
            ), 0), file.length)
            let endFrame = min(max(AVAudioFramePosition(
                Double(segment.endMilliseconds) * format.sampleRate / 1_000
            ), startFrame), file.length)
            return try Self.isSilent(file, from: startFrame, to: endFrame)
        }.value
    }

    private static func isSilent(
        _ file: AVAudioFile,
        from startFrame: AVAudioFramePosition,
        to endFrame: AVAudioFramePosition
    ) throws -> Bool {
        let format = file.processingFormat
        guard endFrame > startFrame,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else {
            return false
        }
        file.framePosition = startFrame
        while file.framePosition < endFrame {
            try Task.checkCancellation()
            let remaining = endFrame - file.framePosition
            try file.read(
                into: buffer,
                frameCount: AVAudioFrameCount(min(Int64(buffer.frameCapacity), remaining))
            )
            guard buffer.frameLength > 0,
                  let channels = buffer.floatChannelData else { return false }
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    if abs(channels[channel][frame]) >= PCMTrackMetrics.silenceThreshold {
                        return false
                    }
                }
            }
        }
        return true
    }
}
