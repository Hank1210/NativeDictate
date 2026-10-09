import Foundation

actor TranscriptionSessionStore {
    nonisolated static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        ProductIdentity.Legacy.transcriptionSessionsDirectory(fileManager: fileManager)
    }

    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            self.rootURL = Self.defaultRootURL(fileManager: fileManager)
        }
    }

    func save(_ manifest: TranscriptionSessionManifest) throws {
        let validated = try manifest.validated()
        let directory = sessionDirectory(recordID: validated.recordID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = manifestURL(recordID: validated.recordID)
        let temporary = directory.appendingPathComponent("manifest-\(UUID().uuidString).tmp")
        let data = try Self.encoder.encode(validated)
        do {
            try data.write(to: temporary, options: [.atomic])
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    func load(recordID: UUID) throws -> TranscriptionSessionManifest? {
        let url = manifestURL(recordID: recordID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Self.decoder.decode(
            TranscriptionSessionManifest.self,
            from: Data(contentsOf: url)
        ).validated()
    }

    func all() throws -> [TranscriptionSessionManifest] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try directories.compactMap { directory in
            guard UUID(uuidString: directory.lastPathComponent) != nil else { return nil }
            let url = directory.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return try Self.decoder.decode(
                TranscriptionSessionManifest.self,
                from: Data(contentsOf: url)
            ).validated()
        }
    }

    func workURL(recordID: UUID, segmentIndex: Int) throws -> URL {
        guard segmentIndex >= 0 else { throw LongFormTranscriptionError.invalidSegmentPlan }
        let directory = sessionDirectory(recordID: recordID)
            .appendingPathComponent("work", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(
            String(format: "segment-%03d.m4a", segmentIndex)
        )
    }

    func removeWorkFile(recordID: UUID, segmentIndex: Int) {
        guard let url = try? workURL(recordID: recordID, segmentIndex: segmentIndex) else { return }
        try? fileManager.removeItem(at: url)
    }

    func delete(recordID: UUID) throws {
        let directory = sessionDirectory(recordID: recordID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    func normalizeInterruptedSessions(now: Date = Date()) throws -> [TranscriptionSessionManifest] {
        var updated: [TranscriptionSessionManifest] = []
        for var manifest in try all() where manifest.status != .completed {
            let old = manifest
            manifest.normalizeInterruptedWork(now: now)
            if manifest != old {
                try save(manifest)
                updated.append(manifest)
            }
        }
        return updated
    }

    private func sessionDirectory(recordID: UUID) -> URL {
        rootURL.appendingPathComponent(recordID.uuidString, isDirectory: true)
    }

    private func manifestURL(recordID: UUID) -> URL {
        sessionDirectory(recordID: recordID).appendingPathComponent("manifest.json")
    }

    private nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
