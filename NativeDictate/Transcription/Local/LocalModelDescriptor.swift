import Foundation

nonisolated struct LocalModelDescriptor: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var engineID: String
    var displayName: String
    var version: String
    var languages: [String]
    var downloadBytes: Int64
    var installedBytes: Int64
    var checksum: String?
    var licenseIdentifier: String
    var minimumOSVersion: String
    var supportedArchitectures: [String]
    var sourceURL: URL
}

nonisolated enum LocalModelCatalog {
    static let parakeetV3 = LocalModelDescriptor(
        id: "parakeet-tdt-0.6b-v3-coreml",
        engineID: "fluidaudio-parakeet-v3",
        displayName: "Parakeet TDT 0.6B v3",
        version: "3",
        languages: [
            "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
            "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "uk", "ja"
        ],
        downloadBytes: 650_000_000,
        installedBytes: 750_000_000,
        checksum: nil,
        licenseIdentifier: "CC-BY-4.0",
        minimumOSVersion: "14.0",
        supportedArchitectures: ["arm64"],
        sourceURL: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!
    )
}
