import AppKit
import Foundation

enum RecordingLocationError: LocalizedError {
    case notConfigured
    case bookmarkInvalid
    case accessDenied
    case selectionCancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Choose a recordings folder before starting dictation."
        case .bookmarkInvalid:
            "The saved recordings folder is no longer available. Choose it again."
        case .accessDenied:
            "FlowDictate no longer has permission to write to the recordings folder."
        case .selectionCancelled:
            "No recordings folder was selected."
        }
    }
}

nonisolated final class RecordingLocationStore: @unchecked Sendable {
    static let bookmarkDefaultsKey = ProductIdentity.Legacy.recordingDirectoryBookmarkDefaultsKey
    static let displayPathDefaultsKey = ProductIdentity.Legacy.recordingDirectoryDisplayPathDefaultsKey

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let lock = NSLock()
    private var activeDirectory: URL?
    private var activeDirectoryUsesSecurityScope = false

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    deinit {
        if activeDirectoryUsesSecurityScope {
            activeDirectory?.stopAccessingSecurityScopedResource()
        }
    }

    var isConfigured: Bool {
        defaults.data(forKey: Self.bookmarkDefaultsKey) != nil
    }

    var displayPath: String? {
        defaults.string(forKey: Self.displayPathDefaultsKey)
    }

    func resolvedDirectory() throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        if let activeDirectory {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: activeDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                if activeDirectoryUsesSecurityScope {
                    activeDirectory.stopAccessingSecurityScopedResource()
                }
                self.activeDirectory = nil
                activeDirectoryUsesSecurityScope = false
                throw RecordingLocationError.bookmarkInvalid
            }
            return activeDirectory
        }

        guard let data = defaults.data(forKey: Self.bookmarkDefaultsKey) else {
            throw RecordingLocationError.notConfigured
        }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw RecordingLocationError.bookmarkInvalid
        }

        let usesSecurityScope = url.startAccessingSecurityScopedResource()

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            if usesSecurityScope { url.stopAccessingSecurityScopedResource() }
            throw RecordingLocationError.bookmarkInvalid
        }
        guard fileManager.isWritableFile(atPath: url.path) else {
            if usesSecurityScope { url.stopAccessingSecurityScopedResource() }
            throw RecordingLocationError.accessDenied
        }
        do {
            if isStale { try saveBookmark(for: url) }
        } catch {
            if usesSecurityScope { url.stopAccessingSecurityScopedResource() }
            throw error
        }
        activeDirectory = url
        activeDirectoryUsesSecurityScope = usesSecurityScope
        return url
    }

    func configure(directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard fileManager.isWritableFile(atPath: directory.path) else {
            throw RecordingLocationError.accessDenied
        }
        try saveBookmark(for: directory)
        deactivateDirectoryAccess()
        _ = try resolvedDirectory()
    }

    func withAccess<T>(to directory: URL? = nil, _ operation: (URL) throws -> T) throws -> T {
        guard let directory else {
            return try operation(resolvedDirectory())
        }
        let accessed = directory.startAccessingSecurityScopedResource()
        defer {
            if accessed { directory.stopAccessingSecurityScopedResource() }
        }
        return try operation(directory)
    }

    @MainActor
    func chooseDirectory(
        recommended: Bool,
        beforeConfigure: (_ previousDirectory: URL?, _ selectedDirectory: URL) throws -> Void = { _, _ in }
    ) throws -> URL {
        let previousDirectory = try? resolvedDirectory()
        let panel = NSOpenPanel()
        panel.title = recommended ? "Choose Documents to create Recordings" : "Choose Recordings Folder"
        panel.message = recommended
            ? "Select your Documents folder. FlowDictate will create and use a Recordings folder inside it."
            : "Choose the folder where FlowDictate should store audio recordings."
        panel.prompt = recommended ? "Use Documents" : "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let selected = panel.url else {
            throw RecordingLocationError.selectionCancelled
        }

        let directory = recommended
            ? selected.appendingPathComponent("Recordings", isDirectory: true)
            : selected
        let accessed = selected.startAccessingSecurityScopedResource()
        defer {
            if accessed { selected.stopAccessingSecurityScopedResource() }
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try beforeConfigure(previousDirectory, directory)
        try configure(directory: directory)
        return directory
    }

    func clear() {
        deactivateDirectoryAccess()
        defaults.removeObject(forKey: Self.bookmarkDefaultsKey)
        defaults.removeObject(forKey: Self.displayPathDefaultsKey)
    }

    private func deactivateDirectoryAccess() {
        lock.lock()
        let directory = activeDirectory
        let usesSecurityScope = activeDirectoryUsesSecurityScope
        activeDirectory = nil
        activeDirectoryUsesSecurityScope = false
        lock.unlock()
        if usesSecurityScope {
            directory?.stopAccessingSecurityScopedResource()
        }
    }

    private func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: Self.bookmarkDefaultsKey)
        defaults.set(url.path, forKey: Self.displayPathDefaultsKey)
    }
}
