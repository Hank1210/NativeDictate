import Foundation

nonisolated enum DictationFailureClassifier {
    static func category(for error: Error) -> DictationErrorCategory {
        if let error = error as? SystemAudioRecorderError {
            return switch error {
            case .permissionDenied: .systemAudioPermission
            case .unavailable, .noAudioReceived: .systemAudioUnavailable
            case .interrupted, .writerFailed: .systemAudioInterrupted
            }
        }
        if let error = error as? DirectInsertionError {
            return switch error {
            case .unsupported, .protectedField: .directInsertionUnsupported
            case .writeFailed: .directInsertionUnknown
            }
        }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return .timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed: return .network
            default: return .network
            }
        }
        if let error = error as? TranscriptionProviderError {
            switch error {
            case .missingAPIKey: return .credentialMissing
            case .audioTooShort: return .transcriptionPreflight
            case .audioFileContainsNoSamples, .audioFileTooLarge: return .providerPermanent
            case let .server(statusCode, _):
                switch statusCode {
                case 401, 403: return .authentication
                case 429: return .rateLimit
                case 500...599: return .providerTemporary
                default: return .providerPermanent
                }
            case .invalidResponse, .emptyTranscript: return .providerPermanent
            case .providerUnavailable: return .providerUnavailable
            case .localModelMissing: return .localModelMissing
            case .localModelCorrupt: return .localModelCorrupt
            case .unsupportedLanguage: return .unsupportedLanguage
            case .localInitializationFailed: return .localInitialization
            case .networkBlocked: return .networkBlocked
            }
        }
        if error is RecordingLocationError || error is AudioStoreError { return .storageUnavailable }
        if error is AudioRecorderError || error is AudioDeviceServiceError { return .audioDevice }
        if error is TextInsertionError { return .insertion }
        if error is FlowPermissionError { return .permission }
        return .unknown
    }

    static func isRetryable(_ error: Error) -> Bool {
        [.network, .timeout, .rateLimit, .providerTemporary].contains(category(for: error))
    }
}
