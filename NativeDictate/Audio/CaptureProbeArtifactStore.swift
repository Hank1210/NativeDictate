import Darwin
import Foundation

/// Keeps development capture-probe files separate from user recordings and
/// removes only artifacts whose owning process is no longer running.
nonisolated struct CaptureProbeArtifactStore {
    static let filePrefix = "screen-capture-kit-probe-"

    let directoryURL: URL
    let fileManager: FileManager

    init(
        directoryURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDictateCaptureProbes", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func makeURL(
        processID: pid_t = getpid(),
        id: UUID = UUID()
    ) throws -> URL {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL.appendingPathComponent(
            "\(Self.filePrefix)\(processID)-\(id.uuidString).m4a"
        )
    }

    @discardableResult
    func removeAbandonedArtifacts(
        isProcessRunning: (pid_t) -> Bool = Self.isProcessRunning
    ) throws -> [URL] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let candidates = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        var removed: [URL] = []
        for candidate in candidates {
            let values = try candidate.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let processID = Self.processID(from: candidate.lastPathComponent),
                  !isProcessRunning(processID) else { continue }
            try fileManager.removeItem(at: candidate)
            removed.append(candidate)
        }
        return removed
    }

    func removeArtifact(at url: URL) throws {
        guard url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            == directoryURL.resolvingSymlinksInPath().standardizedFileURL,
              Self.processID(from: url.lastPathComponent) != nil else { return }
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    static func processID(from filename: String) -> pid_t? {
        guard filename.hasPrefix(filePrefix), filename.hasSuffix(".m4a") else {
            return nil
        }
        let remainder = filename.dropFirst(filePrefix.count)
        guard let separator = remainder.firstIndex(of: "-") else { return nil }
        guard let processID = pid_t(remainder[..<separator]), processID > 0 else {
            return nil
        }
        let uuidStart = remainder.index(after: separator)
        guard UUID(uuidString: String(remainder[uuidStart...].dropLast(4))) != nil else {
            return nil
        }
        return processID
    }

    private static func isProcessRunning(_ processID: pid_t) -> Bool {
        guard processID > 0 else { return false }
        if Darwin.kill(processID, 0) == 0 { return true }
        return errno == EPERM
    }
}
