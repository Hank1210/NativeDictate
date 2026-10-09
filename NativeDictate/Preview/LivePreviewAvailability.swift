import Foundation
import Speech

nonisolated enum SpeechPermissionState: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted

    var title: String {
        switch self {
        case .notDetermined: "Not requested"
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }
}

nonisolated enum LivePreviewAvailability: Equatable, Sendable {
    case available(localeIdentifier: String)
    case permissionRequired(localeIdentifier: String)
    case unavailable(reason: String)

    var localeIdentifier: String? {
        switch self {
        case let .available(localeIdentifier), let .permissionRequired(localeIdentifier):
            localeIdentifier
        case .unavailable:
            nil
        }
    }

    var statusText: String {
        switch self {
        case let .available(localeIdentifier):
            "Available locally (\(localeIdentifier))"
        case let .permissionRequired(localeIdentifier):
            "Permission required (\(localeIdentifier))"
        case let .unavailable(reason):
            reason
        }
    }
}

@MainActor
enum LivePreviewAvailabilityResolver {
    static func resolve(
        language: TranscriptionLanguage,
        permission: SpeechPermissionState
    ) -> LivePreviewAvailability {
        guard let locale = preferredLocale(for: language) else {
            return .unavailable(reason: "No supported German or English speech locale is installed.")
        }
        switch permission {
        case .denied:
            return .unavailable(reason: "Speech Recognition permission is denied.")
        case .restricted:
            return .unavailable(reason: "Speech Recognition is restricted on this Mac.")
        case .notDetermined:
            return .permissionRequired(localeIdentifier: locale.identifier)
        case .authorized:
            break
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return .unavailable(reason: "Speech recognition is unavailable for \(locale.identifier).")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            return .unavailable(
                reason: "Apple currently reports no on-device recognizer for \(locale.identifier). Verify the language in System Settings → Keyboard → Dictation."
            )
        }
        return .available(localeIdentifier: locale.identifier)
    }

    static func preferredLocale(for language: TranscriptionLanguage) -> Locale? {
        let supported = SFSpeechRecognizer.supportedLocales()
        let preferredIdentifiers: [String]
        switch language {
        case .german:
            preferredIdentifiers = ["de-DE", "de-AT", "de-CH"]
        case .english:
            preferredIdentifiers = ["en-US", "en-GB", "en-AU"]
        case .automatic:
            preferredIdentifiers = Locale.preferredLanguages + [Locale.current.identifier]
        }

        for identifier in preferredIdentifiers {
            let preferred = Locale(identifier: identifier)
            if let exact = supported.first(where: { $0.identifier == preferred.identifier }) {
                return exact
            }
            if let languageCode = preferred.language.languageCode?.identifier,
               ["de", "en"].contains(languageCode),
               let sameLanguage = supported.first(where: {
                   $0.language.languageCode?.identifier == languageCode
               }) {
                return sameLanguage
            }
        }
        return nil
    }
}
