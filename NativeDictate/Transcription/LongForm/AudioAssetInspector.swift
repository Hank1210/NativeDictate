@preconcurrency import AVFoundation
import Foundation

nonisolated final class AudioAssetInspector: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func inspect(_ url: URL) async throws -> AudioAssetInspection {
        let fileManager = fileManager
        return try await Task.detached(priority: .utility) {
            guard fileManager.fileExists(atPath: url.path) else {
                throw LongFormTranscriptionError.sourceUnavailable
            }
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard file.length > 0, format.sampleRate > 0, format.channelCount > 0 else {
                throw LongFormTranscriptionError.sourceContainsNoSamples
            }
            let duration = Double(file.length) / format.sampleRate
            let durationMilliseconds = max(Int64((duration * 1_000).rounded()), 1)
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = Int64(values.fileSize ?? 0)
            guard byteCount > 0 else {
                throw LongFormTranscriptionError.sourceContainsNoSamples
            }
            let channels = Int(format.channelCount)
            let bitrate = channels == 1 ? 64_000.0 : 128_000.0
            let estimated = Int64((duration * bitrate / 8).rounded(.up)) + 64_000
            return AudioAssetInspection(
                byteCount: byteCount,
                durationMilliseconds: durationMilliseconds,
                sampleRate: format.sampleRate,
                channelCount: channels,
                estimatedCompactByteCount: estimated,
                isCompactM4A: url.pathExtension.lowercased() == "m4a"
            )
        }.value
    }

    func fingerprint(
        url: URL,
        relativePath: String,
        inspection: AudioAssetInspection
    ) throws -> TranscriptionSourceFingerprint {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return TranscriptionSourceFingerprint(
            audioRelativePath: relativePath,
            byteCount: inspection.byteCount,
            durationMilliseconds: inspection.durationMilliseconds,
            modificationDate: values.contentModificationDate
        )
    }

    func availableCapacity(at url: URL) throws -> Int64 {
        let values = try fileManager.attributesOfFileSystem(forPath: url.path)
        return (values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }
}

nonisolated struct TranscriptionModeResolver: Sendable {
    let configuration: LongFormConfiguration

    init(configuration: LongFormConfiguration = .default) {
        self.configuration = configuration
    }

    func mode(for inspection: AudioAssetInspection, hasExistingSession: Bool = false) -> TranscriptionPreparationMode {
        if hasExistingSession { return .longForm(reason: .resumedSession) }
        if inspection.durationMilliseconds > configuration.targetDurationMilliseconds {
            return .longForm(reason: .duration)
        }
        if inspection.estimatedCompactByteCount > configuration.softUploadByteLimit {
            return .longForm(reason: .estimatedUploadSize)
        }
        return .singleFile
    }

    func requiredWorkingBytes(for inspection: AudioAssetInspection) -> Int64 {
        min(
            max(inspection.estimatedCompactByteCount, configuration.softUploadByteLimit),
            configuration.hardUploadByteLimit
        ) * 2 + configuration.workingStorageReserveBytes
    }
}
