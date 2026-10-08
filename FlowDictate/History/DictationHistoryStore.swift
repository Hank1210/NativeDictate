import Foundation

enum DictationHistoryError: LocalizedError, Equatable {
    case recordNotFound
    case meetingRequiresAttention
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .recordNotFound:
            "The dictation history entry could not be found."
        case .meetingRequiresAttention:
            "Finish or review the meeting before archiving its History entry."
        case let .unsupportedSchema(schema):
            "The dictation history uses unsupported schema version \(schema)."
        }
    }
}

nonisolated struct HistoryRetentionResult: Equatable, Sendable {
    var removedCount = 0
    var archivedCount = 0
}

actor DictationHistoryStore {
    nonisolated static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        ProductIdentity.Legacy.historyFileURL(fileManager: fileManager)
    }

    private nonisolated struct Envelope: Codable, Sendable {
        var schemaVersion: Int
        var records: [DictationRecord]
    }

    private nonisolated struct LoadSnapshot: Sendable {
        var data: Data
        var envelope: Envelope
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let fileIO = SerialFileIO(label: "de.mcc.NativeDictate.history-file-io", qos: .userInitiated)
    private var recordsByID: [UUID: DictationRecord] = [:]
    private var loaded = false
    private var loadTask: Task<LoadSnapshot?, Error>?

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL(fileManager: fileManager)
        }
    }

    func upsert(_ record: DictationRecord) async throws {
        try await loadIfNeeded()
        recordsByID[record.id] = record
        try await persist()
    }

    /// Updates the in-memory view without rewriting the complete JSON file.
    /// The durable job manifest covers intermediate recovery; the completed
    /// record is flushed after text insertion.
    func stage(_ record: DictationRecord) async throws {
        try await loadIfNeeded()
        recordsByID[record.id] = record
    }

    /// Persists the latest staged snapshot without keeping UI or recording
    /// interaction code on the write path.
    func flush() async throws {
        try await loadIfNeeded()
        try await persist()
    }

    func record(id: UUID) async throws -> DictationRecord? {
        try await loadIfNeeded()
        return recordsByID[id]
    }

    func all(includeArchived: Bool = false) async throws -> [DictationRecord] {
        try await loadIfNeeded()
        return recordsByID.values
            .filter { includeArchived || $0.archivedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func recent(limit: Int) async throws -> [DictationRecord] {
        Array(try await all().prefix(limit))
    }

    func lastInsertable() async throws -> DictationRecord? {
        try await all().first(where: \.canInsert)
    }

    func delete(id: UUID) async throws {
        try await loadIfNeeded()
        recordsByID.removeValue(forKey: id)
        try await persist()
    }

    func archive(id: UUID, now: Date = Date()) async throws {
        try await loadIfNeeded()
        guard var record = recordsByID[id] else { throw DictationHistoryError.recordNotFound }
        if record.meetingSummary?.canArchiveHistoryEntry == false {
            throw DictationHistoryError.meetingRequiresAttention
        }
        compactForArchive(&record, now: now)
        recordsByID[id] = record
        try await persist()
    }

    func knownAudioRelativePaths() async throws -> Set<String> {
        try await loadIfNeeded()
        return Set(recordsByID.values.map(\.audioRelativePath))
    }

    func applyRetention(
        maximumAgeDays: Int,
        maximumRecordCount: Int,
        now: Date = Date()
    ) async throws -> HistoryRetentionResult {
        try await loadIfNeeded()
        var result = HistoryRetentionResult()

        // Archived records only keep the metadata needed to retain their audio.
        // Once that audio has gone, the tombstone is no longer needed either.
        let obsoleteArchiveIDs = recordsByID.values
            .filter {
                $0.archivedAt != nil && $0.audioFileSize <= 0
                    && !$0.isAutomaticallyProtected
            }
            .map(\.id)
        for id in obsoleteArchiveIDs {
            recordsByID.removeValue(forKey: id)
            result.removedCount += 1
        }

        let active = recordsByID.values
            .filter { $0.archivedAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
        let cutoff = maximumAgeDays >= 0
            ? Calendar.current.date(byAdding: .day, value: -maximumAgeDays, to: now)
            : nil
        let countCandidates = maximumRecordCount >= 0
            ? Set(active.dropFirst(maximumRecordCount).map(\.id))
            : []

        for var record in active {
            let expiredByAge = cutoff.map { record.createdAt < $0 } ?? false
            guard expiredByAge || countCandidates.contains(record.id) else { continue }
            guard !record.isAutomaticallyProtected else { continue }

            if record.audioFileSize > 0 {
                compactForArchive(&record, now: now)
                recordsByID[record.id] = record
                result.archivedCount += 1
            } else {
                recordsByID.removeValue(forKey: record.id)
                result.removedCount += 1
            }
        }
        if result != HistoryRetentionResult() { try await persist() }
        return result
    }

    private func compactForArchive(_ record: inout DictationRecord, now: Date) {
        record.archivedAt = now
        record.updatedAt = now
        record.originalTranscript = nil
        record.correctedTranscript = nil
        record.correctionSummary = nil
        record.formattedTranscript = nil
        record.dictionaryTranscript = nil
        record.finalText = nil
        record.partialTranscript = nil
        record.targetApplicationName = nil
        record.targetBundleIdentifier = nil
        record.errorCategory = nil
        record.errorMessage = nil
        record.enhancementErrorCategory = nil
        record.enhancementErrorMessage = nil
    }

    func recoverInterrupted(now: Date = Date()) async throws -> [DictationRecord] {
        try await loadIfNeeded()
        var recovered: [DictationRecord] = []
        for (id, var record) in recordsByID {
            if record.processingStatus == .formatting || record.processingStatus == .formatted {
                record.processingStatus = .notStarted
                record.enhancementErrorCategory = .interrupted
                record.enhancementErrorMessage = "Local Smart Dictation processing was interrupted."
                record.updatedAt = now
                recordsByID[id] = record
                recovered.append(record)
                continue
            }
            if record.processingStatus == .enhancing {
                record.processingStatus = .enhancementFailed
                record.enhancementErrorCategory = .interrupted
                record.enhancementErrorMessage = "Smart Dictation was interrupted when NativeDictate stopped."
                record.updatedAt = now
                recordsByID[id] = record
                recovered.append(record)
                continue
            }
            if record.processingStatus == .enhanced {
                record.processingStatus = .completed
                record.updatedAt = now
                recordsByID[id] = record
                recovered.append(record)
                continue
            }
            switch record.status {
            case .transcribing:
                record.status = .transcriptionFailed
                record.errorCategory = .interrupted
                record.errorMessage = "Transcription was interrupted when NativeDictate stopped."
            case .inserting:
                record.status = .insertionUnknown
                record.errorCategory = .interrupted
                record.errorMessage = "Insertion may have completed before NativeDictate stopped. Review before inserting again."
            default:
                continue
            }
            record.updatedAt = now
            recordsByID[id] = record
            recovered.append(record)
        }
        if !recovered.isEmpty { try await persist() }
        return recovered
    }

    private func loadIfNeeded() async throws {
        guard !loaded else { return }
        let task: Task<LoadSnapshot?, Error>
        if let loadTask {
            task = loadTask
        } else {
            let fileURL = fileURL
            let fileManager = SerialFileManagerReference(fileManager)
            let fileIO = fileIO
            let created: Task<LoadSnapshot?, Error> = Task {
                try await fileIO.perform { () -> LoadSnapshot? in
                    guard fileManager.value.fileExists(atPath: fileURL.path) else { return nil }
                    let data = try Data(contentsOf: fileURL)
                    let envelope = try JSONDecoder.flowDictate.decode(Envelope.self, from: data)
                    return LoadSnapshot(data: data, envelope: envelope)
                }
            }
            loadTask = created
            task = created
        }

        let snapshot: LoadSnapshot?
        do {
            snapshot = try await task.value
        } catch {
            loadTask = nil
            throw error
        }
        guard !loaded else { return }
        loadTask = nil
        guard let snapshot else {
            loaded = true
            return
        }
        guard snapshot.envelope.schemaVersion <= NativeDictateVersion.historySchema else {
            throw DictationHistoryError.unsupportedSchema(snapshot.envelope.schemaVersion)
        }
        loaded = true
        recordsByID = Dictionary(
            uniqueKeysWithValues: snapshot.envelope.records.map { ($0.id, $0) }
        )
        if snapshot.envelope.schemaVersion < NativeDictateVersion.historySchema {
            var backupNames: [String] = []
            if snapshot.envelope.schemaVersion < 4 {
                backupNames += ["dictations-pre-3.2.json", "dictations-pre-3.4.json"]
            } else if snapshot.envelope.schemaVersion < 5 {
                backupNames.append("dictations-pre-3.4.json")
            }
            if snapshot.envelope.schemaVersion < 6 {
                backupNames.append("dictations-pre-4.0.json")
            }
            if snapshot.envelope.schemaVersion < 7 {
                backupNames.append("dictations-pre-4.1.json")
            }
            let fileURL = fileURL
            let fileManager = SerialFileManagerReference(fileManager)
            let data = snapshot.data
            let resolvedBackupNames = backupNames
            try await fileIO.perform {
                for name in resolvedBackupNames {
                    let backupURL = fileURL.deletingLastPathComponent()
                        .appendingPathComponent(name)
                    if !fileManager.value.fileExists(atPath: backupURL.path) {
                        try data.write(to: backupURL, options: .atomic)
                    }
                }
            }
            try await persist()
        }
    }

    private func persist() async throws {
        let fileURL = fileURL
        let fileManager = SerialFileManagerReference(fileManager)
        let directory = fileURL.deletingLastPathComponent()
        let envelope = Envelope(
            schemaVersion: NativeDictateVersion.historySchema,
            records: Array(recordsByID.values)
        )
        try await fileIO.perform {
            try fileManager.value.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.flowDictate.encode(envelope)
            try data.write(to: fileURL, options: .atomic)
        }
    }
}

private extension JSONEncoder {
    nonisolated static var flowDictate: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var flowDictate: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
