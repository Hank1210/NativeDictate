import Foundation

nonisolated enum SmartDictationStoreError: LocalizedError {
    case duplicateDictionaryEntry
    case builtInStyleCannotBeChanged
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .duplicateDictionaryEntry: "An identical dictionary entry already exists."
        case .builtInStyleCannotBeChanged: "Built-in writing styles cannot be changed. Duplicate the style first."
        case .itemNotFound: "The Smart Dictation item could not be found."
        }
    }
}

actor DictionaryStore {
    nonisolated static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        ProductIdentity.Legacy.dictionaryFileURL(fileManager: fileManager)
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var entries: [DictionaryEntry]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private var cached: [DictionaryEntry]?

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func all() throws -> [DictionaryEntry] {
        try load().sorted { $0.spokenForm.localizedCaseInsensitiveCompare($1.spokenForm) == .orderedAscending }
    }

    func upsert(_ entry: DictionaryEntry) throws {
        var entries = try load()
        try Self.validate(entry, excluding: entry.id, in: entries)
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        try persist(entries)
    }

    func delete(id: UUID) throws {
        var entries = try load()
        guard entries.contains(where: { $0.id == id }) else { throw SmartDictationStoreError.itemNotFound }
        entries.removeAll { $0.id == id }
        try persist(entries)
    }

    func export(to destination: URL) throws {
        let envelope = Envelope(schemaVersion: 1, entries: try load())
        try encode(envelope).write(to: destination, options: .atomic)
    }

    func importFile(from source: URL) throws {
        let data = try Data(contentsOf: source)
        guard data.count <= 5_000_000,
              let envelope = try? JSONDecoder.smartDictation.decode(Envelope.self, from: data),
              envelope.schemaVersion == 1 else {
            throw SmartDictationValidationError.invalidImport
        }
        var merged = try load()
        for entry in envelope.entries {
            try Self.validate(entry, excluding: entry.id, in: merged)
            if let index = merged.firstIndex(where: { $0.id == entry.id }) { merged[index] = entry }
            else { merged.append(entry) }
        }
        try persist(merged)
    }

    private func load() throws -> [DictionaryEntry] {
        if let cached { return cached }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            cached = []
            return []
        }
        let envelope = try JSONDecoder.smartDictation.decode(Envelope.self, from: Data(contentsOf: fileURL))
        cached = envelope.entries
        return envelope.entries
    }

    private func persist(_ entries: [DictionaryEntry]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(Envelope(schemaVersion: 1, entries: entries)).write(to: fileURL, options: .atomic)
        cached = entries
    }

    private func encode(_ envelope: Envelope) throws -> Data {
        try JSONEncoder.smartDictation.encode(envelope)
    }

    private static func validate(
        _ entry: DictionaryEntry,
        excluding id: UUID,
        in entries: [DictionaryEntry]
    ) throws {
        let spoken = entry.spokenForm.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty, !replacement.isEmpty else {
            throw SmartDictationValidationError.emptyDictionaryValue
        }
        let duplicate = entries.contains {
            $0.id != id
                && $0.spokenForm.compare(spoken, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                && $0.replacement == replacement
                && $0.language == entry.language
                && $0.caseSensitive == entry.caseSensitive
                && $0.matchWholeWordsOnly == entry.matchWholeWordsOnly
        }
        guard !duplicate else { throw SmartDictationStoreError.duplicateDictionaryEntry }
    }

}

actor WritingStyleStore {
    nonisolated static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        ProductIdentity.Legacy.writingStylesFileURL(fileManager: fileManager)
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var styles: [WritingStyleProfile]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private var cachedCustom: [WritingStyleProfile]?

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func all() throws -> [WritingStyleProfile] {
        BuiltInWritingStyles.all + (try loadCustom()).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func profile(id: UUID) throws -> WritingStyleProfile? {
        try all().first { $0.id == id }
    }

    func upsert(_ style: WritingStyleProfile) throws {
        guard !style.isBuiltIn, BuiltInWritingStyles.profile(id: style.id) == nil else {
            throw SmartDictationStoreError.builtInStyleCannotBeChanged
        }
        try Self.validate(style)
        var styles = try loadCustom()
        if let index = styles.firstIndex(where: { $0.id == style.id }) { styles[index] = style }
        else { styles.append(style) }
        try persist(styles)
    }

    func duplicate(_ style: WritingStyleProfile, now: Date = Date()) throws -> WritingStyleProfile {
        var copy = WritingStyleProfile(
            id: UUID(),
            name: String("\(style.name) Copy".prefix(60)),
            instruction: style.instruction.isEmpty
                ? "Rewrite the text without adding or removing factual content."
                : style.instruction,
            isBuiltIn: false,
            isEnabled: true,
            schemaVersion: 1
        )
        if copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { copy.name = "Custom Style" }
        try upsert(copy)
        return copy
    }

    func delete(id: UUID) throws {
        guard BuiltInWritingStyles.profile(id: id) == nil else {
            throw SmartDictationStoreError.builtInStyleCannotBeChanged
        }
        var styles = try loadCustom()
        guard styles.contains(where: { $0.id == id }) else { throw SmartDictationStoreError.itemNotFound }
        styles.removeAll { $0.id == id }
        try persist(styles)
    }

    func export(to destination: URL) throws {
        try JSONEncoder.smartDictation.encode(
            Envelope(schemaVersion: 1, styles: try loadCustom())
        ).write(to: destination, options: .atomic)
    }

    func importFile(from source: URL) throws {
        let data = try Data(contentsOf: source)
        guard data.count <= 5_000_000,
              let envelope = try? JSONDecoder.smartDictation.decode(Envelope.self, from: data),
              envelope.schemaVersion == 1 else {
            throw SmartDictationValidationError.invalidImport
        }
        var merged = try loadCustom()
        for var style in envelope.styles {
            style.isBuiltIn = false
            try Self.validate(style)
            if BuiltInWritingStyles.profile(id: style.id) != nil { style = WritingStyleProfile(
                id: UUID(), name: style.name, instruction: style.instruction,
                isBuiltIn: false, isEnabled: style.isEnabled, schemaVersion: 1
            ) }
            if let index = merged.firstIndex(where: { $0.id == style.id }) { merged[index] = style }
            else { merged.append(style) }
        }
        try persist(merged)
    }

    private func loadCustom() throws -> [WritingStyleProfile] {
        if let cachedCustom { return cachedCustom }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            cachedCustom = []
            return []
        }
        let envelope = try JSONDecoder.smartDictation.decode(Envelope.self, from: Data(contentsOf: fileURL))
        cachedCustom = envelope.styles.filter { !$0.isBuiltIn }
        return cachedCustom ?? []
    }

    private func persist(_ styles: [WritingStyleProfile]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.smartDictation.encode(Envelope(schemaVersion: 1, styles: styles))
        try data.write(to: fileURL, options: .atomic)
        cachedCustom = styles
    }

    private static func validate(_ style: WritingStyleProfile) throws {
        let name = style.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = style.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SmartDictationValidationError.emptyName }
        guard name.count <= 60 else { throw SmartDictationValidationError.nameTooLong }
        guard !instruction.isEmpty else { throw SmartDictationValidationError.emptyInstruction }
        guard instruction.count <= 4_000 else { throw SmartDictationValidationError.instructionTooLong }
    }
}

private extension JSONEncoder {
    nonisolated static var smartDictation: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var smartDictation: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
