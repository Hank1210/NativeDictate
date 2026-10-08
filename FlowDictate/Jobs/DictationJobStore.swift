import Foundation

actor DictationJobStore {
    nonisolated static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        ProductIdentity.Legacy.jobsDirectory(fileManager: fileManager)
    }

    private nonisolated struct SequenceEnvelope: Codable, Sendable {
        var schemaVersion: Int
        var lastSequence: Int64
    }

    private let directory: URL
    private let sequenceURL: URL
    private let fileManager: FileManager
    private let fileIO = SerialFileIO(label: "de.mcc.NativeDictate.job-file-io", qos: .userInitiated)

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let resolved = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.directory = resolved
        sequenceURL = resolved.appendingPathComponent("sequence.json")
    }

    func nextSequence() async throws -> Int64 {
        let directory = directory
        let sequenceURL = sequenceURL
        let fileManager = SerialFileManagerReference(fileManager)
        return try await fileIO.perform {
            try fileManager.value.createDirectory(at: directory, withIntermediateDirectories: true)
            let previous: Int64
            if fileManager.value.fileExists(atPath: sequenceURL.path) {
                let envelope = try Self.decoder.decode(
                    SequenceEnvelope.self,
                    from: Data(contentsOf: sequenceURL)
                )
                previous = envelope.lastSequence
            } else {
                previous = try Self.allJobs(
                    directory: directory,
                    sequenceURL: sequenceURL,
                    fileManager: fileManager.value
                ).map(\.queueSequence).max() ?? 0
            }
            let next = previous + 1
            try Self.encoder.encode(SequenceEnvelope(schemaVersion: 1, lastSequence: next))
                .write(to: sequenceURL, options: .atomic)
            return next
        }
    }

    func create(_ job: DictationJob) async throws {
        guard job.schemaVersion == DictationJob.currentSchemaVersion else {
            throw DictationQueueError.unsupportedSchema(job.schemaVersion)
        }
        let url = manifestURL(for: job.id)
        let directory = directory
        let fileManager = SerialFileManagerReference(fileManager)
        try await fileIO.perform {
            guard !fileManager.value.fileExists(atPath: url.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try fileManager.value.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(job).write(to: url, options: .atomic)
        }
    }

    func update(_ job: DictationJob) async throws {
        guard job.schemaVersion == DictationJob.currentSchemaVersion else {
            throw DictationQueueError.unsupportedSchema(job.schemaVersion)
        }
        let url = manifestURL(for: job.id)
        let directory = directory
        let fileManager = SerialFileManagerReference(fileManager)
        try await fileIO.perform {
            try fileManager.value.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(job).write(to: url, options: .atomic)
        }
    }

    func job(id: UUID) async throws -> DictationJob? {
        let url = manifestURL(for: id)
        let fileManager = SerialFileManagerReference(fileManager)
        return try await fileIO.perform {
            guard fileManager.value.fileExists(atPath: url.path) else { return nil }
            return try Self.decodeJob(at: url)
        }
    }

    func all() async throws -> [DictationJob] {
        let directory = directory
        let sequenceURL = sequenceURL
        let fileManager = SerialFileManagerReference(fileManager)
        return try await fileIO.perform {
            try Self.allJobs(
                directory: directory,
                sequenceURL: sequenceURL,
                fileManager: fileManager.value
            )
        }
    }

    func normalizeInterrupted(now: Date = Date()) async throws -> [DictationJob] {
        let directory = directory
        let sequenceURL = sequenceURL
        let fileManager = SerialFileManagerReference(fileManager)
        return try await fileIO.perform {
            var normalized: [DictationJob] = []
            for var job in try Self.allJobs(
                directory: directory,
                sequenceURL: sequenceURL,
                fileManager: fileManager.value
            ) {
                switch job.status {
                case .preparing, .transcribing, .correcting, .formatting, .enhancing:
                    job.status = .failed
                    job.lastErrorCategory = .interrupted
                    job.lastErrorMessage = "Processing was interrupted when NativeDictate stopped. Retry from History."
                case .readyToInsert:
                    job.status = .insertionDeferred
                    job.lastErrorCategory = .interrupted
                    job.lastErrorMessage = "The completed text is ready in History. Restore it deliberately after restart."
                case .inserting:
                    job.status = .insertionDeferred
                    job.lastErrorCategory = .interrupted
                    job.lastErrorMessage = "Insertion may already have completed. Review the text before restoring it."
                default:
                    continue
                }
                job.updatedAt = now
                try Self.encoder.encode(job).write(
                    to: directory.appendingPathComponent("\(job.id.uuidString).json"),
                    options: .atomic
                )
                normalized.append(job)
            }
            return normalized
        }
    }

    func delete(id: UUID) async throws {
        let url = manifestURL(for: id)
        let fileManager = SerialFileManagerReference(fileManager)
        try await fileIO.perform {
            if fileManager.value.fileExists(atPath: url.path) {
                try fileManager.value.removeItem(at: url)
            }
        }
    }

    private nonisolated static func decodeJob(at url: URL) throws -> DictationJob {
        let job = try decoder.decode(DictationJob.self, from: Data(contentsOf: url))
        guard job.schemaVersion <= DictationJob.currentSchemaVersion else {
            throw DictationQueueError.unsupportedSchema(job.schemaVersion)
        }
        return job
    }

    private nonisolated static func allJobs(
        directory: URL,
        sequenceURL: URL,
        fileManager: FileManager
    ) throws -> [DictationJob] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter {
            $0.pathExtension == "json" && $0.lastPathComponent != sequenceURL.lastPathComponent
        }
        .map { try decodeJob(at: $0) }
        .sorted { $0.queueSequence < $1.queueSequence }
    }

    private func manifestURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
