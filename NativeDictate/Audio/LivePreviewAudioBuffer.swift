import AVFoundation
import Foundation
import OSLog

nonisolated struct LivePreviewAudioBuffer: Sendable {
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
    let channelSamples: [[Float]]

    nonisolated init(
        sampleRate: Double,
        channelCount: Int,
        frameCount: Int,
        channelSamples: [[Float]]
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.frameCount = frameCount
        self.channelSamples = channelSamples
    }

    nonisolated init?(copying buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return nil }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return nil }
        sampleRate = buffer.format.sampleRate
        self.channelCount = channelCount
        self.frameCount = frameCount
        channelSamples = (0..<channelCount).map { channel in
            Array(UnsafeBufferPointer(start: channels[channel], count: frameCount))
        }
    }

    // Rebuild the Speech buffer on the feed task, outside the real-time audio
    // callback. Immutable samples cannot be overwritten by a later tap.
    nonisolated func makePCMBuffer() -> AVAudioPCMBuffer? {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            ),
            let channels = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        for channel in 0..<channelCount {
            channelSamples[channel].withUnsafeBufferPointer { samples in
                guard let address = samples.baseAddress else { return }
                channels[channel].update(from: address, count: frameCount)
            }
        }
        return buffer
    }
}

nonisolated final class LivePreviewBufferChannel: @unchecked Sendable {
    let stream: AsyncStream<LivePreviewAudioBuffer>
    private let continuation: AsyncStream<LivePreviewAudioBuffer>.Continuation
    private let lock = NSLock()
    private var droppedBufferCountStorage = 0
    private var didLogDroppedBufferStorage = false

    init(limit: Int = 8) {
        var capturedContinuation: AsyncStream<LivePreviewAudioBuffer>.Continuation!
        stream = AsyncStream(bufferingPolicy: .bufferingNewest(max(limit, 1))) {
            capturedContinuation = $0
        }
        continuation = capturedContinuation
    }

    var droppedBufferCount: Int {
        lock.withLock { droppedBufferCountStorage }
    }

    nonisolated func yield(_ buffer: LivePreviewAudioBuffer) {
        if case .dropped = continuation.yield(buffer) {
            let shouldLog = lock.withLock {
                droppedBufferCountStorage += 1
                if didLogDroppedBufferStorage { return false }
                didLogDroppedBufferStorage = true
                return true
            }
            if shouldLog {
                NativeDictateLogger.audio.notice("Live Preview audio buffer dropped; keeping newest buffered audio")
            }
        }
    }

    nonisolated func finish() {
        continuation.finish()
    }
}
