import Foundation
import OSLog
import Speech

@MainActor
final class AppleSpeechLivePreviewProvider: LivePreviewProviding {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var feedTask: Task<Void, Never>?
    private var feeder: SpeechPreviewAudioFeeder?

    var isAvailable: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func start(
        buffers: AsyncStream<LivePreviewAudioBuffer>,
        localeIdentifier: String,
        eventHandler: @escaping @MainActor (LivePreviewEvent) -> Void
    ) throws {
        cancel()
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw LivePreviewProviderError.permissionDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw LivePreviewProviderError.recognizerUnavailable
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let error {
                Task { @MainActor in eventHandler(.failed(error.localizedDescription)) }
                return
            }
            guard let result else { return }
            let event: LivePreviewEvent = result.isFinal
                ? .finalSegment(result.bestTranscription.formattedString)
                : .partial(result.bestTranscription.formattedString)
            Task { @MainActor in eventHandler(event) }
        }

        let feeder = SpeechPreviewAudioFeeder(request: request)
        self.feeder = feeder
        // Speech's append/conversion can stall. Keep it off the Main Actor so
        // hotkeys, queue handoff, focus activation and overlay timers can run.
        feedTask = Task.detached(priority: .userInitiated) { [feeder] in
            var didLogFirstBuffer = false
            for await buffer in buffers {
                guard !Task.isCancelled else { break }
                if !didLogFirstBuffer {
                    didLogFirstBuffer = true
                    NativeDictateLogger.audio.info(
                        "Live Preview received audio: \(buffer.sampleRate, privacy: .public) Hz, \(buffer.channelCount, privacy: .public) channel(s)"
                    )
                }
                await feeder.append(buffer)
            }
            await feeder.finish()
        }
    }

    func finish() {
        cleanup()
    }

    func cancel() {
        cleanup()
    }

    private func cleanup() {
        feedTask?.cancel()
        feedTask = nil
        if let feeder {
            Task.detached(priority: .userInitiated) { await feeder.finish() }
        }
        feeder = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
    }

    deinit {
        feedTask?.cancel()
        recognitionTask?.cancel()
    }
}

/// Serializes Speech request operations on a non-UI executor. Finishing is
/// idempotent because both stream completion and cancellation can reach it.
private actor SpeechPreviewAudioFeeder {
    private var request: SFSpeechAudioBufferRecognitionRequest?

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: LivePreviewAudioBuffer) {
        guard let request, let speechBuffer = buffer.makePCMBuffer() else { return }
        request.append(speechBuffer)
    }

    func finish() {
        request?.endAudio()
        request = nil
    }
}
