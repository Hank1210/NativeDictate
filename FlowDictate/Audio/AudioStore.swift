import Foundation

enum AudioStoreError: LocalizedError {
    case applicationSupportUnavailable
    case recordingDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "The local application support folder is unavailable."
        case .recordingDirectoryUnavailable:
            "The selected recordings folder is unavailable."
        }
    }
}

struct AudioStore: Sendable {
    nonisolated static func defaultRecordingsDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        ProductIdentity.Legacy.recordingsDirectory(fileManager: fileManager)
    }

    let fileManager: FileManager
    private let locationStore: RecordingLocationStore?

    init(
        fileManager: FileManager = .default,
        locationStore: RecordingLocationStore? = nil
    ) {
        self.fileManager = fileManager
        self.locationStore = locationStore
    }

    func makeRecordingURL(
        id: UUID = UUID(),
        date: Date = Date(),
        fileExtension: String = "wav"
    ) throws -> URL {
        let directory = try recordingsDirectory()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent(
            "\(timestamp)-\(id.uuidString).\(fileExtension)"
        )
    }

    func recordingsDirectory() throws -> URL {
        if let locationStore {
            return try locationStore.withAccess { root in
                let audioDirectory = root.appendingPathComponent("Audio", isDirectory: true)
                try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
                return audioDirectory
            }
        }

        guard fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first != nil else {
            throw AudioStoreError.applicationSupportUnavailable
        }
        let directory = Self.defaultRecordingsDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func relativePath(for url: URL) throws -> String {
        let root = try recordingsDirectory()
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    func url(forRelativePath relativePath: String) throws -> URL {
        try recordingsDirectory().appendingPathComponent(relativePath)
    }

    static func legacyRecordingsDirectory(fileManager: FileManager = .default) -> URL? {
        guard fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first != nil else { return nil }
        return defaultRecordingsDirectory(fileManager: fileManager)
    }
}
