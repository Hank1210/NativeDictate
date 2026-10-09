@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

nonisolated enum PCMTrackMetricsError: Error, Sendable, Equatable {
    case noAudioReceived
}

/// Shared timeline and quality accounting for the two lossless mixed-session originals.
/// Callers serialize access; the type itself intentionally owns no synchronization.
nonisolated struct PCMTrackMetrics: Sendable, Equatable {
    static let anchorIntervalMilliseconds: Int64 = 5_000
    static let silenceThreshold: Float = 0.001
    static let clippingThreshold: Float = 0.999

    private(set) var requestedHostTime: UInt64 = 0
    private(set) var sampleRate: Double
    private(set) var totalFrameCount: Int64 = 0
    private(set) var firstHostTime: UInt64?
    private(set) var lastHostTime: UInt64?
    private(set) var firstAnchor: TrackTimestampAnchor?
    private(set) var anchors: [TrackTimestampAnchor] = []
    private(set) var gaps: [TrackGap] = []
    private(set) var peakLevel: Float = 0
    private(set) var clippedFrameCount: Int64 = 0
    private(set) var silentFrameCount: Int64 = 0
    private(set) var droppedBufferCount: Int64 = 0

    private var lastSampleTime: Double?
    private var previousInputFrameCount: Int64?

    init(requestedHostTime: UInt64 = 0, sampleRate: Double) {
        self.requestedHostTime = requestedHostTime
        self.sampleRate = sampleRate
    }

    mutating func record(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        let frameCount = Int64(buffer.frameLength)
        guard frameCount > 0, sampleRate > 0 else { return }
        let callbackHostTime = time.isHostTimeValid ? time.hostTime : mach_continuous_time()
        let framePosition = totalFrameCount
        firstHostTime = firstHostTime ?? callbackHostTime

        if let sampleTime = time.isSampleTimeValid ? Optional(Double(time.sampleTime)) : nil,
           let lastSampleTime,
           let previousInputFrameCount {
            let expectedSampleTime = lastSampleTime + Double(previousInputFrameCount)
            let missingFrames = sampleTime - expectedSampleTime
            if missingFrames > 0.5 {
                droppedBufferCount += 1
                let gapStart = Int64(
                    (Double(framePosition) / sampleRate * 1_000).rounded()
                )
                let gapDuration = max(
                    1,
                    Int64((missingFrames / sampleRate * 1_000).rounded())
                )
                gaps.append(
                    TrackGap(
                        id: UUID(),
                        startMilliseconds: gapStart,
                        endMilliseconds: gapStart + gapDuration,
                        reason: .droppedBuffers
                    )
                )
            }
        }
        if time.isSampleTimeValid {
            lastSampleTime = Double(time.sampleTime)
            previousInputFrameCount = frameCount
        }

        let sessionTime = milliseconds(from: requestedHostTime, to: callbackHostTime)
        if anchors.isEmpty
            || sessionTime - anchors[anchors.count - 1].sessionTimeMilliseconds
                >= Self.anchorIntervalMilliseconds {
            let anchor = TrackTimestampAnchor(
                hostTime: callbackHostTime,
                trackFramePosition: framePosition,
                sessionTimeMilliseconds: sessionTime
            )
            anchors.append(anchor)
            firstAnchor = firstAnchor ?? anchor
        }

        recordQuality(buffer)
        totalFrameCount += frameCount
        let bufferDurationNanoseconds = UInt64(
            (Double(frameCount) / sampleRate * 1_000_000_000).rounded()
        )
        lastHostTime = callbackHostTime + AudioConvertNanosToHostTime(
            bufferDurationNanoseconds
        )
    }

    func captureResult(byteCount: Int64) throws -> MixedTrackCaptureResult {
        guard let firstHostTime,
              let lastHostTime,
              let firstAnchor,
              totalFrameCount > 0,
              byteCount > 0 else {
            throw PCMTrackMetricsError.noAudioReceived
        }
        let audioDuration = Int64(
            (Double(totalFrameCount) / sampleRate * 1_000).rounded()
        )
        let hostDuration = Int64(
            (Double(AudioConvertHostTimeToNanos(lastHostTime - firstHostTime))
                / 1_000_000).rounded()
        )
        let duration = max(
            1,
            max(audioDuration, max(hostDuration, gaps.last?.endMilliseconds ?? 0))
        )
        var finalizedAnchors = anchors
        let finalSessionTime = milliseconds(from: requestedHostTime, to: lastHostTime)
        if let lastAnchor = finalizedAnchors.last,
           lastHostTime > lastAnchor.hostTime,
           totalFrameCount > lastAnchor.trackFramePosition {
            finalizedAnchors.append(
                TrackTimestampAnchor(
                    hostTime: lastHostTime,
                    trackFramePosition: totalFrameCount,
                    sessionTimeMilliseconds: max(
                        finalSessionTime,
                        lastAnchor.sessionTimeMilliseconds
                    )
                )
            )
        }
        if finalizedAnchors.isEmpty { finalizedAnchors = [firstAnchor] }
        return MixedTrackCaptureResult(
            formatIdentifier: "lpcm",
            sampleRate: sampleRate,
            channelCount: 1,
            firstHostTime: firstHostTime,
            lastHostTime: lastHostTime,
            durationMilliseconds: duration,
            byteCount: byteCount,
            timestampAnchors: finalizedAnchors,
            gaps: gaps,
            quality: TrackQualityMetrics(
                peakLevel: peakLevel,
                clippedFrameCount: clippedFrameCount,
                silentDurationMilliseconds: Int64(
                    (Double(silentFrameCount) / sampleRate * 1_000).rounded()
                ),
                droppedBufferCount: droppedBufferCount
            )
        )
    }

    private mutating func recordQuality(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        var bufferPeak: Float = 0
        var isSilent = true
        var clippedFrames: Int64 = 0
        for index in 0..<frameCount {
            let magnitude = abs(samples[index])
            bufferPeak = max(bufferPeak, magnitude)
            if magnitude >= Self.silenceThreshold { isSilent = false }
            if magnitude >= Self.clippingThreshold { clippedFrames += 1 }
        }
        peakLevel = min(max(peakLevel, bufferPeak), 1)
        clippedFrameCount += clippedFrames
        if isSilent { silentFrameCount += Int64(frameCount) }
    }

    private func milliseconds(from start: UInt64, to end: UInt64) -> Int64 {
        guard end >= start else { return 0 }
        return Int64(AudioConvertHostTimeToNanos(end - start) / 1_000_000)
    }
}
