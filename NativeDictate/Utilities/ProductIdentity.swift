import Foundation

/// Separates the public product name from identifiers that existing installations rely on.
/// Changing `displayName` must never implicitly change a value under `Legacy`.
nonisolated enum ProductIdentity {
    static let displayName = "NativeDictate"

    nonisolated enum Legacy {
        static let bundleIdentifier = "de.mcc.FlowDictate"
        static let testHostBundleIdentifier = "de.mcc.FlowDictate.TestHost"
        static let keychainService = bundleIdentifier
        static let applicationSupportDirectoryName = "FlowDictate"
        static let recordingDirectoryBookmarkDefaultsKey = "recordingDirectoryBookmark"
        static let recordingDirectoryDisplayPathDefaultsKey = "recordingDirectoryDisplayPath"

        static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
        }

        static func recordingsDirectory(fileManager: FileManager = .default) -> URL {
            applicationSupportDirectory(fileManager: fileManager)
                .appendingPathComponent("Recordings", isDirectory: true)
        }

        static func historyFileURL(fileManager: FileManager = .default) -> URL {
            applicationSupportDirectory(fileManager: fileManager)
                .appendingPathComponent("History", isDirectory: true)
                .appendingPathComponent("dictations.json")
        }

        static func jobsDirectory(fileManager: FileManager = .default) -> URL {
            applicationSupportDirectory(fileManager: fileManager)
                .appendingPathComponent("Jobs", isDirectory: true)
        }

        static func appProfilesFileURL(fileManager: FileManager = .default) -> URL {
            applicationSupportDirectory(fileManager: fileManager)
                .appendingPathComponent("Profiles", isDirectory: true)
                .appendingPathComponent("app-profiles.json")
        }

        static func smartDictationDirectory(fileManager: FileManager = .default) -> URL {
            applicationSupportDirectory(fileManager: fileManager)
                .appendingPathComponent("SmartDictation", isDirectory: true)
        }

        static func dictionaryFileURL(fileManager: FileManager = .default) -> URL {
            smartDictationDirectory(fileManager: fileManager)
                .appendingPathComponent("dictionary.json")
        }

        static func writingStylesFileURL(fileManager: FileManager = .default) -> URL {
            smartDictationDirectory(fileManager: fileManager)
                .appendingPathComponent("styles.json")
        }

        static func modelsDirectory(fileManager: FileManager = .default) -> URL {
            applicationSupportDirectory(fileManager: fileManager)
                .appendingPathComponent("Models", isDirectory: true)
        }

        static func transcriptionSessionsDirectory(
            fileManager: FileManager = .default
        ) -> URL {
            applicationSupportDirectory(fileManager: fileManager)
                .appendingPathComponent("TranscriptionSessions", isDirectory: true)
        }
    }
}
