@preconcurrency import AVFoundation
import Foundation

nonisolated final class AudioSegmentExporter: @unchecked Sendable {
    private let fileManager: FileManager
    private let configuration: LongFormConfiguration

    init(
        fileManager: FileManager = .default,
        configuration: LongFormConfiguration = .default
    ) {
        self.fileManager = fileManager
        self.configuration = configuration
    }

    func export(
        sourceURL: URL,
        segment: TranscriptionSegment,
        destinationURL: URL
    ) async throws -> Int64 {
        let fileManager = fileManager
        let hardLimit = configuration.hardUploadByteLimit
        return try await Task.detached(priority: .utility) {
            try? fileManager.removeItem(at: destinationURL)
            do {
                let source = try AVAudioFile(forReading: sourceURL)
                let format = source.processingFormat
                guard format.sampleRate > 0 else {
                    throw LongFormTranscriptionError.sourceContainsNoSamples
                }
                let startFrame = min(
                    max(AVAudioFramePosition(
                        Double(segment.startMilliseconds) * format.sampleRate / 1_000
                    ), 0),
                    source.length
                )
                let endFrame = min(
                    max(AVAudioFramePosition(
                        Double(segment.endMilliseconds) * format.sampleRate / 1_000
                    ), startFrame),
                    source.length
                )
                guard endFrame > startFrame else {
                    throw LongFormTranscriptionError.invalidSegmentPlan
                }
                let targetBitRate = format.channelCount == 1
                    ? min(64_000, max(24_000, Int(format.sampleRate * 2)))
                    : min(128_000, max(48_000, Int(format.sampleRate * Double(format.channelCount) * 2)))
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVEncoderBitRateKey: targetBitRate,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                let output = try AVAudioFile(forWriting: destinationURL, settings: settings)
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: 32_768
                ) else {
                    throw LongFormTranscriptionError.segmentExportFailed(segment.index)
                }
                source.framePosition = startFrame
                while source.framePosition < endFrame {
                    try Task.checkCancellation()
                    let remaining = endFrame - source.framePosition
                    let count = AVAudioFrameCount(min(Int64(buffer.frameCapacity), remaining))
                    try source.read(into: buffer, frameCount: count)
                    guard buffer.frameLength > 0 else { break }
                    try output.write(from: buffer)
                }
                let values = try destinationURL.resourceValues(forKeys: [.fileSizeKey])
                let byteCount = Int64(values.fileSize ?? 0)
                guard byteCount >= OpenAITranscriptionProvider.minimumAudioFileBytes else {
                    throw LongFormTranscriptionError.segmentExportFailed(segment.index)
                }
                guard byteCount <= hardLimit else {
                    throw LongFormTranscriptionError.segmentTooLarge(
                        index: segment.index,
                        actualBytes: byteCount,
                        maximumBytes: hardLimit
                    )
                }
                return byteCount
            } catch {
                try? fileManager.removeItem(at: destinationURL)
                throw error
            }
        }.value
    }
}
