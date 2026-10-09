import Foundation
#if arch(arm64)
import FluidAudio
#endif

actor FluidAudioTranscriptionProvider: TranscriptionProvider {
    private let modelDirectory: URL
    private let modelID: String
    #if arch(arm64)
    private var manager: AsrManager?
    #endif

    init(modelDirectory: URL, modelID: String = LocalModelCatalog.parakeetV3.id) {
        self.modelDirectory = modelDirectory
        self.modelID = modelID
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        #if arch(arm64)
        let manager = try await loadedManager()
        let language: Language?
        if let requested = request.language {
            guard let supported = Language(rawValue: requested) else {
                throw TranscriptionProviderError.unsupportedLanguage(language: requested)
            }
            language = supported
        } else {
            language = nil
        }

        var decoderState = try TdtDecoderState(
            decoderLayers: await manager.decoderLayerCount
        )
        let result: ASRResult
        do {
            result = try await manager.transcribe(
                request.audioURL,
                decoderState: &decoderState,
                language: language
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranscriptionProviderError.localInitializationFailed(
                message: error.localizedDescription
            )
        }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionProviderError.emptyTranscript }
        let timedUnits = buildWordTimings(from: result.tokenTimings ?? []).compactMap {
            timing -> TranscriptionTimedUnit? in
            let word = timing.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let start = Int64((timing.startTime * 1_000).rounded())
            let end = Int64((timing.endTime * 1_000).rounded())
            guard !word.isEmpty, start >= 0, end > start else { return nil }
            return TranscriptionTimedUnit(
                text: word,
                startMilliseconds: start,
                endMilliseconds: end,
                precision: .word
            )
        }
        return TranscriptionResult(
            text: text,
            provider: TranscriptionProviderID.local.rawValue,
            model: modelID,
            timedUnits: timedUnits
        )
        #else
        throw TranscriptionProviderError.providerUnavailable(
            reason: "Local transcription requires an Apple Silicon Mac."
        )
        #endif
    }

    /// Releases the Core ML graph on this provider actor rather than on the
    /// Main Actor that owns the app settings. Core ML teardown can be expensive
    /// after changing providers and must not delay overlay timers or hotkeys.
    func shutdown() {
        #if arch(arm64)
        manager = nil
        #endif
    }

    #if arch(arm64)
    private func loadedManager() async throws -> AsrManager {
        if let manager { return manager }
        guard AsrModels.modelsExist(at: modelDirectory, version: .v3) else {
            throw TranscriptionProviderError.localModelMissing(modelID: modelID)
        }
        do {
            let models = try await AsrModels.load(from: modelDirectory, version: .v3)
            let loaded = AsrManager(config: .default, models: models)
            manager = loaded
            return loaded
        } catch {
            throw TranscriptionProviderError.localInitializationFailed(
                message: error.localizedDescription
            )
        }
    }
    #endif
}
