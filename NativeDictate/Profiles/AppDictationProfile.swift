import Foundation

nonisolated enum InsertionPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case accessibility
    case clipboard

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic (recommended)"
        case .accessibility: "Direct Accessibility first"
        case .clipboard: "Clipboard only"
        }
    }

    var attemptsDirectAccessibility: Bool { self != .clipboard }
}

nonisolated struct AppDictationProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var bundleIdentifier: String
    var displayName: String
    var writingStyleID: UUID?
    var language: TranscriptionLanguage?
    var transcriptionProviderID: TranscriptionProviderID?
    var transcriptionModel: String?
    var spokenFormattingEnabled: Bool?
    var insertionPreference: InsertionPreference
    var isEnabled: Bool
    var schemaVersion: Int

    static func new(bundleIdentifier: String, displayName: String) -> Self {
        Self(
            id: UUID(),
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            writingStyleID: nil,
            language: nil,
            transcriptionProviderID: nil,
            transcriptionModel: nil,
            spokenFormattingEnabled: nil,
            insertionPreference: .automatic,
            isEnabled: true,
            schemaVersion: 2
        )
    }
}

actor AppProfileStore {
    nonisolated static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        ProductIdentity.Legacy.appProfilesFileURL(fileManager: fileManager)
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var profiles: [AppDictationProfile]
    }

    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func all() throws -> [AppDictationProfile] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(
            Envelope.self,
            from: Data(contentsOf: fileURL)
        )
        guard envelope.schemaVersion <= 2 else {
            throw CocoaError(.coderReadCorrupt)
        }
        return envelope.profiles.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func upsert(_ profile: AppDictationProfile) throws {
        var profiles = try all()
        profiles.removeAll { $0.id == profile.id || $0.bundleIdentifier == profile.bundleIdentifier }
        profiles.append(profile)
        try persist(profiles)
    }

    func delete(id: UUID) throws {
        var profiles = try all()
        profiles.removeAll { $0.id == id }
        try persist(profiles)
    }

    private func persist(_ profiles: [AppDictationProfile]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let migrated = profiles.map { profile in
            var profile = profile
            profile.schemaVersion = 2
            return profile
        }
        try encoder.encode(Envelope(schemaVersion: 2, profiles: migrated))
            .write(to: fileURL, options: .atomic)
    }
}

nonisolated struct EffectiveDictationConfiguration: Sendable {
    var providerID: TranscriptionProviderID
    var engineID: String
    var language: TranscriptionLanguage
    var transcriptionModel: String
    var privacyMode: PrivacyMode
    var writingStyleID: UUID
    var spokenFormattingEnabled: Bool
    var insertionPreference: InsertionPreference
    var profileID: UUID?
}
