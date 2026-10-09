import Foundation
#if arch(arm64)
import FluidAudio
#endif

nonisolated enum LocalModelState: Equatable, Sendable {
    case unavailable(reason: String)
    case notInstalled
    case downloading(progress: Double)
    case installed
    case failed(message: String)
}

actor LocalModelManager {
    nonisolated static func defaultModelsRoot(fileManager: FileManager = .default) -> URL {
        ProductIdentity.Legacy.modelsDirectory(fileManager: fileManager)
    }

    typealias StateHandler = @MainActor @Sendable (LocalModelState) -> Void

    let descriptor: LocalModelDescriptor
    private let fileManager: FileManager
    private let modelsRoot: URL
    private(set) var state: LocalModelState
    private var installationInProgress = false

    init(
        descriptor: LocalModelDescriptor = LocalModelCatalog.parakeetV3,
        modelsRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.descriptor = descriptor
        self.fileManager = fileManager
        self.modelsRoot = modelsRoot ?? Self.defaultModelsRoot(fileManager: fileManager)

        if RuntimeArchitecture.current != "arm64" {
            state = .unavailable(reason: "Local transcription requires an Apple Silicon Mac.")
        } else {
            state = .notInstalled
        }
    }

    var activeDirectory: URL {
        modelsRoot
            .appendingPathComponent(descriptor.id, isDirectory: true)
            .appendingPathComponent("active", isDirectory: true)
    }

    private var repositoryFolderName: String {
        #if arch(arm64)
        Repo.parakeetV3.folderName
        #else
        "parakeet-tdt-0.6b-v3"
        #endif
    }

    /// FluidAudio treats `activeDirectory` as an anchor and stores the actual
    /// repository in a sibling directory named after the Hugging Face repo.
    var repositoryDirectory: URL {
        activeDirectory.deletingLastPathComponent()
            .appendingPathComponent(repositoryFolderName, isDirectory: true)
    }

    func refreshState() -> LocalModelState {
        guard RuntimeArchitecture.current == "arm64" else {
            state = .unavailable(reason: "Local transcription requires an Apple Silicon Mac.")
            return state
        }
        if installationInProgress { return state }
        #if arch(arm64)
        state = AsrModels.modelsExist(at: activeDirectory, version: .v3)
            ? .installed : .notInstalled
        #else
        state = .unavailable(reason: "Local transcription requires an Apple Silicon Mac.")
        #endif
        return state
    }

    func install(
        policy: NetworkPolicy,
        stateHandler: StateHandler? = nil
    ) async throws {
        guard !installationInProgress else { return }
        installationInProgress = true
        defer { installationInProgress = false }
        try policy.requirePermission(for: .modelDownload)
        guard RuntimeArchitecture.current == "arm64" else {
            throw TranscriptionProviderError.providerUnavailable(
                reason: "Local transcription requires an Apple Silicon Mac."
            )
        }
        let modelParent = try prepareModelStorage()
        let stagingRoot = modelParent.appendingPathComponent(
            "staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let stagingAnchor = stagingRoot.appendingPathComponent("anchor", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        await publish(.downloading(progress: 0), handler: stateHandler)
        do {
            #if arch(arm64)
            _ = try await AsrModels.downloadAndLoad(
                to: stagingAnchor,
                version: .v3,
                progressHandler: { [weak self] progress in
                    guard let self else { return }
                    Task {
                        await self.publish(
                            .downloading(progress: progress.fractionCompleted),
                            handler: stateHandler
                        )
                    }
                }
            )
            guard AsrModels.modelsExist(at: stagingAnchor, version: .v3) else {
                throw TranscriptionProviderError.localModelCorrupt(modelID: descriptor.id)
            }
            try promoteDownloadedModel(from: stagingRoot)
            await publish(.installed, handler: stateHandler)
            #else
            throw TranscriptionProviderError.providerUnavailable(
                reason: "Local transcription requires an Apple Silicon Mac."
            )
            #endif
        } catch {
            await publish(.failed(message: error.localizedDescription), handler: stateHandler)
            throw error
        }
    }

    func remove() throws {
        guard !installationInProgress else { return }
        guard fileManager.fileExists(atPath: repositoryDirectory.path) else {
            state = .notInstalled
            return
        }
        try fileManager.removeItem(at: repositoryDirectory)
        if fileManager.fileExists(atPath: activeDirectory.path) {
            try? fileManager.removeItem(at: activeDirectory)
        }
        state = .notInstalled
    }

    /// Promotes the actual repository created by FluidAudio, not the logical
    /// anchor passed to its API. Kept internal so the filesystem transaction can
    /// be verified without downloading the model in unit tests.
    func promoteDownloadedModel(from stagingRoot: URL) throws {
        let stagedRepository = stagingRoot.appendingPathComponent(
            repositoryFolderName,
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: stagedRepository.path) else {
            throw CocoaError(
                .fileNoSuchFile,
                userInfo: [
                    NSFilePathErrorKey: stagedRepository.path,
                    NSLocalizedDescriptionKey: "The downloaded model repository is missing. Please try the download again."
                ]
            )
        }

        let backup = repositoryDirectory.deletingLastPathComponent().appendingPathComponent(
            "previous-\(UUID().uuidString)",
            isDirectory: true
        )
        let hadActiveModel = fileManager.fileExists(atPath: repositoryDirectory.path)
        if hadActiveModel {
            try fileManager.moveItem(at: repositoryDirectory, to: backup)
        }
        do {
            try fileManager.moveItem(at: stagedRepository, to: repositoryDirectory)
            if hadActiveModel { try? fileManager.removeItem(at: backup) }
        } catch {
            if hadActiveModel,
               !fileManager.fileExists(atPath: repositoryDirectory.path) {
                try? fileManager.moveItem(at: backup, to: repositoryDirectory)
            }
            throw error
        }
    }

    /// A fresh user's Application Support/FlowDictate directory does not exist
    /// yet. Create the model destination before querying its volume capacity.
    func prepareModelStorage() throws -> URL {
        let modelParent = activeDirectory.deletingLastPathComponent()
        try fileManager.createDirectory(at: modelParent, withIntermediateDirectories: true)
        let values = try modelParent.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < descriptor.installedBytes * 2 {
            throw CocoaError(
                .fileWriteOutOfSpace,
                userInfo: [NSLocalizedDescriptionKey: "At least \(byteCount(descriptor.installedBytes * 2)) of free storage is required for the model download."]
            )
        }
        return modelParent
    }

    private func byteCount(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func publish(_ newState: LocalModelState, handler: StateHandler?) async {
        state = newState
        if let handler { await handler(newState) }
    }
}
