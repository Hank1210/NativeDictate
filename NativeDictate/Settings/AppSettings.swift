import Combine
import Foundation

nonisolated enum TranscriptionLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case german = "de"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .german: "German"
        case .english: "English"
        }
    }

    var apiValue: String? {
        self == .automatic ? nil : rawValue
    }
}

nonisolated enum DictationActivationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case toggle
    case pressAndHold

    var id: String { rawValue }
    var title: String { self == .toggle ? "Press to start / stop" : "Press and hold" }
}

@MainActor
final class AppSettings: ObservableObject {
    nonisolated static let currentMeetingRecordingConsentVersion = 1

    private enum Key {
        static let dictationHotKey = "dictationHotKey"
        static let cancelHotKey = "cancelHotKey"
        static let dictationHotKeyData = "dictationHotKeyData"
        static let cancelHotKeyData = "cancelHotKeyData"
        static let restoreHotKeyData = "restoreHotKeyData"
        static let inputDeviceUID = "inputDeviceUID"
        static let recordingAudioSource = "recordingAudioSource"
        static let transcriptionModel = "transcriptionModel"
        static let transcriptionProviderID = "transcriptionProviderID"
        static let localTranscriptionModelID = "localTranscriptionModelID"
        static let privacyMode = "privacyMode"
        static let cloudEnhancementEnabled = "cloudEnhancementEnabled"
        static let transcriptionLanguage = "transcriptionLanguage"
        static let clipboardRestoreDelay = "clipboardRestoreDelay"
        static let onboardingVersion = "onboardingVersion"
        static let automaticRetryEnabled = "automaticRetryEnabled"
        static let audioRetentionDays = "audioRetentionDays"
        static let historyRetentionDays = "historyRetentionDays"
        static let historyMaximumRecordCount = "historyMaximumRecordCount"
        static let livePreviewEnabled = "livePreviewEnabled"
        static let overlaySize = "overlaySize"
        static let livePreviewCharacterLimit = "livePreviewCharacterLimit"
        static let overlayPosition = "overlayPosition"
        static let spokenFormattingEnabled = "spokenFormattingEnabled"
        static let personalDictionaryEnabled = "personalDictionaryEnabled"
        static let writingStyleID = "writingStyleID"
        static let enhancementModel = "enhancementModel"
        static let smartDictationFallback = "smartDictationFallback"
        static let showUsageStatistics = "showUsageStatistics"
        static let typingWordsPerMinute = "typingWordsPerMinute"
        static let usageStatisticsResetDate = "usageStatisticsResetDate"
        static let updateCheckEnabled = "updateCheckEnabled"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let dictationActivationMode = "dictationActivationMode"
        static let meetingRecordingConsentVersion = "meetingRecordingConsentVersion"
    }

    private let defaults: UserDefaults
    private var isApplyingTranscriptionConfiguration = false

    @Published var dictationHotKey: HotKeyConfiguration {
        didSet {
            defaults.set(dictationHotKey.id, forKey: Key.dictationHotKey)
            defaults.set(try? JSONEncoder().encode(dictationHotKey), forKey: Key.dictationHotKeyData)
        }
    }

    @Published var cancelHotKey: HotKeyConfiguration {
        didSet {
            defaults.set(cancelHotKey.id, forKey: Key.cancelHotKey)
            defaults.set(try? JSONEncoder().encode(cancelHotKey), forKey: Key.cancelHotKeyData)
        }
    }

    @Published var restoreHotKey: HotKeyConfiguration {
        didSet {
            defaults.set(try? JSONEncoder().encode(restoreHotKey), forKey: Key.restoreHotKeyData)
        }
    }

    @Published var inputDeviceUID: String? {
        didSet { defaults.set(inputDeviceUID, forKey: Key.inputDeviceUID) }
    }

    @Published var recordingAudioSource: RecordingAudioSource {
        didSet { defaults.set(recordingAudioSource.rawValue, forKey: Key.recordingAudioSource) }
    }

    @Published var transcriptionModel: String {
        didSet { defaults.set(transcriptionModel, forKey: Key.transcriptionModel) }
    }

    @Published var transcriptionProviderID: TranscriptionProviderID {
        didSet {
            defaults.set(transcriptionProviderID.rawValue, forKey: Key.transcriptionProviderID)
            guard !isApplyingTranscriptionConfiguration else { return }
            if transcriptionProviderID == .openAI, privacyMode != .cloudTranscription {
                applyTranscriptionConfiguration(
                    privacyMode: .cloudTranscription,
                    providerID: .openAI
                )
            } else if transcriptionProviderID == .local, privacyMode == .cloudTranscription {
                applyTranscriptionConfiguration(
                    privacyMode: .localWithOptionalCloudEnhancement,
                    providerID: .local
                )
            }
        }
    }

    @Published var localTranscriptionModelID: String {
        didSet { defaults.set(localTranscriptionModelID, forKey: Key.localTranscriptionModelID) }
    }

    @Published var privacyMode: PrivacyMode {
        didSet {
            defaults.set(privacyMode.rawValue, forKey: Key.privacyMode)
            guard !isApplyingTranscriptionConfiguration else { return }
            let compatibleProvider: TranscriptionProviderID = privacyMode == .cloudTranscription
                ? .openAI : .local
            if transcriptionProviderID != compatibleProvider {
                applyTranscriptionConfiguration(
                    privacyMode: privacyMode,
                    providerID: compatibleProvider
                )
            }
        }
    }

    @Published var cloudEnhancementEnabled: Bool {
        didSet { defaults.set(cloudEnhancementEnabled, forKey: Key.cloudEnhancementEnabled) }
    }

    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet { defaults.set(transcriptionLanguage.rawValue, forKey: Key.transcriptionLanguage) }
    }

    @Published var clipboardRestoreDelay: Double {
        didSet { defaults.set(clipboardRestoreDelay, forKey: Key.clipboardRestoreDelay) }
    }

    @Published var onboardingVersion: Int {
        didSet { defaults.set(onboardingVersion, forKey: Key.onboardingVersion) }
    }

    @Published var automaticRetryEnabled: Bool {
        didSet { defaults.set(automaticRetryEnabled, forKey: Key.automaticRetryEnabled) }
    }

    @Published var audioRetentionDays: Int {
        didSet { defaults.set(audioRetentionDays, forKey: Key.audioRetentionDays) }
    }

    @Published var historyRetentionDays: Int {
        didSet { defaults.set(historyRetentionDays, forKey: Key.historyRetentionDays) }
    }

    @Published var historyMaximumRecordCount: Int {
        didSet { defaults.set(historyMaximumRecordCount, forKey: Key.historyMaximumRecordCount) }
    }

    @Published var livePreviewEnabled: Bool {
        didSet { defaults.set(livePreviewEnabled, forKey: Key.livePreviewEnabled) }
    }

    @Published var overlaySize: OverlaySize {
        didSet { defaults.set(overlaySize.rawValue, forKey: Key.overlaySize) }
    }

    @Published var livePreviewCharacterLimit: Int {
        didSet {
            let clamped = min(max(livePreviewCharacterLimit, 50), 800)
            if clamped != livePreviewCharacterLimit {
                livePreviewCharacterLimit = clamped
            }
            defaults.set(clamped, forKey: Key.livePreviewCharacterLimit)
        }
    }

    @Published var overlayPosition: OverlayPosition {
        didSet { defaults.set(overlayPosition.rawValue, forKey: Key.overlayPosition) }
    }

    @Published var spokenFormattingEnabled: Bool {
        didSet { defaults.set(spokenFormattingEnabled, forKey: Key.spokenFormattingEnabled) }
    }

    @Published var personalDictionaryEnabled: Bool {
        didSet { defaults.set(personalDictionaryEnabled, forKey: Key.personalDictionaryEnabled) }
    }

    @Published var writingStyleID: UUID {
        didSet { defaults.set(writingStyleID.uuidString, forKey: Key.writingStyleID) }
    }

    @Published var enhancementModel: String {
        didSet { defaults.set(enhancementModel, forKey: Key.enhancementModel) }
    }

    @Published var smartDictationFallback: SmartDictationFallback {
        didSet { defaults.set(smartDictationFallback.rawValue, forKey: Key.smartDictationFallback) }
    }

    @Published var showUsageStatistics: Bool {
        didSet { defaults.set(showUsageStatistics, forKey: Key.showUsageStatistics) }
    }

    @Published var typingWordsPerMinute: Double {
        didSet { defaults.set(typingWordsPerMinute, forKey: Key.typingWordsPerMinute) }
    }

    @Published var usageStatisticsResetDate: Date? {
        didSet { defaults.set(usageStatisticsResetDate, forKey: Key.usageStatisticsResetDate) }
    }

    @Published var updateCheckEnabled: Bool {
        didSet { defaults.set(updateCheckEnabled, forKey: Key.updateCheckEnabled) }
    }

    @Published var dictationActivationMode: DictationActivationMode {
        didSet { defaults.set(dictationActivationMode.rawValue, forKey: Key.dictationActivationMode) }
    }

    @Published private(set) var meetingRecordingConsentVersion: Int {
        didSet {
            defaults.set(
                meetingRecordingConsentVersion,
                forKey: Key.meetingRecordingConsentVersion
            )
        }
    }

    var hasAcceptedCurrentMeetingRecordingConsent: Bool {
        meetingRecordingConsentVersion == Self.currentMeetingRecordingConsentVersion
    }

    var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: Key.lastUpdateCheck) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let dictationID = defaults.string(forKey: Key.dictationHotKey)
        dictationHotKey = Self.savedHotKey(defaults, key: Key.dictationHotKeyData)
            ?? HotKeyConfiguration.dictationPresets.first { $0.id == dictationID }
            ?? .optionSpace

        let cancelID = defaults.string(forKey: Key.cancelHotKey)
        cancelHotKey = Self.savedHotKey(defaults, key: Key.cancelHotKeyData)
            ?? HotKeyConfiguration.cancelPresets.first { $0.id == cancelID }
            ?? .optionShiftSpace

        restoreHotKey = HotKeyConfiguration.normalizedRestorePreset(
            Self.savedHotKey(defaults, key: Key.restoreHotKeyData)
        )

        inputDeviceUID = defaults.string(forKey: Key.inputDeviceUID)
        recordingAudioSource = RecordingAudioSource(
            rawValue: defaults.string(forKey: Key.recordingAudioSource) ?? ""
        ) ?? .microphone
        transcriptionModel = defaults.string(forKey: Key.transcriptionModel)
            ?? "gpt-4o-mini-transcribe"
        let storedProviderID = TranscriptionProviderID(
            rawValue: defaults.string(forKey: Key.transcriptionProviderID) ?? ""
        ) ?? .openAI
        localTranscriptionModelID = defaults.string(forKey: Key.localTranscriptionModelID)
            ?? LocalModelCatalog.parakeetV3.id
        let resolvedPrivacyMode = PrivacyMode(
            rawValue: defaults.string(forKey: Key.privacyMode) ?? ""
        ) ?? (storedProviderID == .local
            ? .localWithOptionalCloudEnhancement : .cloudTranscription)
        let resolvedProviderID: TranscriptionProviderID = resolvedPrivacyMode == .cloudTranscription
            ? .openAI : .local
        privacyMode = resolvedPrivacyMode
        transcriptionProviderID = resolvedProviderID
        defaults.set(resolvedProviderID.rawValue, forKey: Key.transcriptionProviderID)
        cloudEnhancementEnabled = defaults.object(forKey: Key.cloudEnhancementEnabled) as? Bool
            ?? false

        let languageValue = defaults.string(forKey: Key.transcriptionLanguage)
        transcriptionLanguage = TranscriptionLanguage(rawValue: languageValue ?? "") ?? .automatic

        let storedDelay = defaults.object(forKey: Key.clipboardRestoreDelay) as? Double
        clipboardRestoreDelay = min(max(storedDelay ?? 0.6, 0.3), 2.0)

        let storedOnboardingVersion = defaults.integer(forKey: Key.onboardingVersion)
        onboardingVersion = storedOnboardingVersion
        automaticRetryEnabled = defaults.object(forKey: Key.automaticRetryEnabled) as? Bool ?? true
        let storedRetention = defaults.integer(forKey: Key.audioRetentionDays)
        audioRetentionDays = storedRetention == 0 ? 30 : storedRetention

        let existingInstallation = storedOnboardingVersion > 0
        if let storedHistoryDays = defaults.object(forKey: Key.historyRetentionDays) as? Int {
            historyRetentionDays = storedHistoryDays
        } else {
            historyRetentionDays = existingInstallation ? -1 : 365
        }
        if let storedHistoryMaximum = defaults.object(forKey: Key.historyMaximumRecordCount) as? Int {
            historyMaximumRecordCount = storedHistoryMaximum
        } else {
            historyMaximumRecordCount = existingInstallation ? -1 : 1_000
        }

        if let storedLivePreview = defaults.object(forKey: Key.livePreviewEnabled) as? Bool {
            livePreviewEnabled = storedLivePreview
        } else {
            livePreviewEnabled = !existingInstallation
        }
        let restoredOverlaySize = OverlaySize(
            rawValue: defaults.string(forKey: Key.overlaySize) ?? ""
        ) ?? .standard
        overlaySize = restoredOverlaySize
        let storedPreviewLimit = defaults.object(forKey: Key.livePreviewCharacterLimit) as? Int
        livePreviewCharacterLimit = min(max(storedPreviewLimit ?? 150, 50), 800)
        overlayPosition = OverlayPosition(
            rawValue: defaults.string(forKey: Key.overlayPosition) ?? ""
        ) ?? .bottomTrailing
        spokenFormattingEnabled = defaults.object(forKey: Key.spokenFormattingEnabled) as? Bool ?? false
        personalDictionaryEnabled = defaults.object(forKey: Key.personalDictionaryEnabled) as? Bool ?? true
        writingStyleID = defaults.string(forKey: Key.writingStyleID).flatMap(UUID.init(uuidString:))
            ?? BuiltInWritingStyles.originalID
        enhancementModel = defaults.string(forKey: Key.enhancementModel) ?? "gpt-4o-mini"
        smartDictationFallback = SmartDictationFallback(
            rawValue: defaults.string(forKey: Key.smartDictationFallback) ?? ""
        ) ?? .ask
        showUsageStatistics = defaults.object(forKey: Key.showUsageStatistics) as? Bool ?? true
        typingWordsPerMinute = defaults.object(forKey: Key.typingWordsPerMinute) as? Double ?? 40
        usageStatisticsResetDate = defaults.object(forKey: Key.usageStatisticsResetDate) as? Date
        updateCheckEnabled = defaults.object(forKey: Key.updateCheckEnabled) as? Bool ?? true
        lastUpdateCheck = defaults.object(forKey: Key.lastUpdateCheck) as? Date
        dictationActivationMode = DictationActivationMode(
            rawValue: defaults.string(forKey: Key.dictationActivationMode) ?? ""
        ) ?? .toggle
        meetingRecordingConsentVersion = defaults.integer(
            forKey: Key.meetingRecordingConsentVersion
        )
    }

    func acceptCurrentMeetingRecordingConsent() {
        meetingRecordingConsentVersion = Self.currentMeetingRecordingConsentVersion
    }

    func resetMeetingRecordingConsent() {
        meetingRecordingConsentVersion = 0
    }

    /// Changes the two coupled settings as one normalized operation. Individual
    /// property assignments remain migration-compatible, but the Settings UI
    /// uses this method to avoid recursive provider/privacy transitions.
    func selectPrivacyMode(_ mode: PrivacyMode) {
        applyTranscriptionConfiguration(
            privacyMode: mode,
            providerID: mode == .cloudTranscription ? .openAI : .local
        )
    }

    func selectTranscriptionProvider(_ providerID: TranscriptionProviderID) {
        let mode: PrivacyMode = providerID == .openAI
            ? .cloudTranscription
            : (privacyMode == .offline ? .offline : .localWithOptionalCloudEnhancement)
        applyTranscriptionConfiguration(privacyMode: mode, providerID: providerID)
    }

    private func applyTranscriptionConfiguration(
        privacyMode newPrivacyMode: PrivacyMode,
        providerID newProviderID: TranscriptionProviderID
    ) {
        guard privacyMode != newPrivacyMode || transcriptionProviderID != newProviderID else {
            return
        }
        isApplyingTranscriptionConfiguration = true
        if privacyMode != newPrivacyMode {
            privacyMode = newPrivacyMode
        }
        if transcriptionProviderID != newProviderID {
            transcriptionProviderID = newProviderID
        }
        isApplyingTranscriptionConfiguration = false
    }

    private static func savedHotKey(_ defaults: UserDefaults, key: String) -> HotKeyConfiguration? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKeyConfiguration.self, from: data)
    }
}
