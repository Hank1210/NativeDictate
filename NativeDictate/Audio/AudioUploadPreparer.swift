@preconcurrency import AVFoundation
import Foundation
import OSLog

nonisolated struct PreparedAudioUpload: Sendable {
    let fileURL: URL
    let filename: String
    let mimeType: String
    let temporaryFileURL: URL?

    func cleanup(fileManager: FileManager = .default) {
        guard let temporaryFileURL else { return }
        try? fileManager.removeItem(at: temporaryFileURL)
    }
}

nonisolated protocol AudioUploadPreparing: AnyObject, Sendable {
    func prepare(_ sourceURL: URL) async throws -> PreparedAudioUpload
}

nonisolated enum AudioUploadPreparationError: LocalizedError {
    case sourceUnavailable
    case conversionUnavailable
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "The saved recording could not be opened for upload."
        case .conversionUnavailable:
            "This recording could not be converted to a compact upload format."
        case let .conversionFailed(message):
            "Audio conversion failed: \(message)"
        }
    }
}

nonisolated final class AudioUploadPreparer: AudioUploadPreparing, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        cleanupStaleTemporaryFiles()
    }

    func prepare(_ sourceURL: URL) async throws -> PreparedAudioUpload {
        // AVAudioFile and the AAC encoder may perform substantial synchronous
        // work. Explicitly move the whole preparation off the caller's actor so
        // a MainActor coordinator cannot stall the overlay or hotkey handling.
        try await Task.detached(priority: .userInitiated) { [self] in
            try prepareOnWorker(sourceURL)
        }.value
    }

    private func prepareOnWorker(_ sourceURL: URL) throws -> PreparedAudioUpload {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AudioUploadPreparationError.sourceUnavailable
        }

        if sourceURL.pathExtension.lowercased() == "m4a" {
            return PreparedAudioUpload(
                fileURL: sourceURL,
                filename: sourceURL.lastPathComponent,
                mimeType: "audio/m4a",
                temporaryFileURL: nil
            )
        }

        do {
            return try prepareCompactUploadOnWorker(sourceURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            NativeDictateLogger.audio.notice(
                "Compact upload conversion unavailable; using the original recording: \(error.localizedDescription, privacy: .public)"
            )
            return PreparedAudioUpload(
                fileURL: sourceURL,
                filename: sourceURL.lastPathComponent,
                mimeType: Self.mimeType(for: sourceURL),
                temporaryFileURL: nil
            )
        }
    }

    func prepareCompactUpload(_ sourceURL: URL) async throws -> PreparedAudioUpload {
        try await Task.detached(priority: .userInitiated) { [self] in
            try prepareCompactUploadOnWorker(sourceURL)
        }.value
    }

    private func prepareCompactUploadOnWorker(_ sourceURL: URL) throws -> PreparedAudioUpload {
        let convertedURL = try convertToM4A(sourceURL)
        return PreparedAudioUpload(
            fileURL: convertedURL,
            filename: sourceURL.deletingPathExtension().lastPathComponent + ".m4a",
            mimeType: "audio/m4a",
            temporaryFileURL: convertedURL
        )
    }

    private func cleanupStaleTemporaryFiles(now: Date = Date()) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let prefixes = [
            "NativeDictate-Upload-",
            "NativeDictate-Multipart-",
            "FlowDictate-Upload-",
            "FlowDictate-Multipart-"
        ]
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        for file in files where prefixes.contains(where: file.lastPathComponent.hasPrefix) {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            if modified.map({ $0 < cutoff }) ?? false {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func convertToM4A(_ sourceURL: URL) throws -> URL {
        let destination = fileManager.temporaryDirectory
            .appendingPathComponent("NativeDictate-Upload-\(UUID().uuidString).m4a")
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let sourceFormat = sourceFile.processingFormat
            let bitRate = min(
                128_000,
                max(24_000, Int(sourceFormat.sampleRate * Double(sourceFormat.channelCount) * 2))
            )
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sourceFormat.sampleRate,
                AVNumberOfChannelsKey: sourceFormat.channelCount,
                AVEncoderBitRateKey: bitRate,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let outputFile = try AVAudioFile(forWriting: destination, settings: outputSettings)
            let buffer = try AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: 32_768
            ).unwrapped(or: AudioUploadPreparationError.conversionUnavailable)

            while sourceFile.framePosition < sourceFile.length {
                try Task.checkCancellation()
                try sourceFile.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                try outputFile.write(from: buffer)
            }
            return destination
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a": "audio/m4a"
        case "mp3": "audio/mpeg"
        case "mp4": "audio/mp4"
        case "webm": "audio/webm"
        default: "audio/wav"
        }
    }
}

private extension Optional {
    nonisolated func unwrapped(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let value = self else { throw error() }
        return value
    }
}
