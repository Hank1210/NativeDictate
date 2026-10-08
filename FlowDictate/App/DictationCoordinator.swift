import AppKit
import AVFoundation
import Combine
import CoreAudio
import Foundation
import OSLog
import os
import UniformTypeIdentifiers

@MainActor
protocol ProcessActivityManaging: AnyObject {
    func beginUserInitiatedActivity(reason: String) -> NSObjectProtocol
    func endActivity(_ activity: NSObjectProtocol)
}

@MainActor
final class SystemProcessActivityManager: ProcessActivityManaging {
    func beginUserInitiatedActivity(reason: String) -> NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: reason)
    }

    func endActivity(_ activity: NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(activity)
    }
}

@MainActor
protocol ApplicationRestarting: AnyObject {
    func openNewInstance() async throws
    func terminateCurrentInstance()
}

@MainActor
final class WorkspaceApplicationRestarter: ApplicationRestarting {
    func openNewInstance() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        _ = try await NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        )
    }

    func terminateCurrentInstance() {
        NSApplication.shared.terminate(nil)
    }
}

/// Prevents a freshly signed XCTest host from presenting a macOS Keychain
/// authorization dialog before the test bundle can materialize. Normal app
/// launches continue to use `KeychainCredentialStore`.
private struct TestHostCredentialStore: CredentialStoring {
    func readAPIKey() throws -> String? { nil }
    func saveAPIKey(_ value: String) throws {}
    func deleteAPIKey() throws {}
}

@MainActor
final class DictationCoordinator: ObservableObject {
    static let currentOnboardingVersion = NativeDictateVersion.onboardingSchema
    private static let minimumTranscribableRecordingDuration: TimeInterval = 0.300

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var apiKeyConfigured = false
    @Published private(set) var microphonePermissionGranted = false
    @Published private(set) var accessibilityPermissionGranted = false
    @Published private(set) var speechPermissionState: SpeechPermissionState = .notDetermined
    @Published private(set) var livePreviewAvailability: LivePreviewAvailability =
        .unavailable(reason: "Checking local Live Preview availability…")
    @Published private(set) var systemAudioPermissionGranted = false
    @Published private(set) var systemAudioPermissionStatus = SystemAudioPermissionStatus.resolve(
        for: .microphone,
        screenCaptureAuthorized: false,
        coreAudioTapSucceededThisSession: false
    )
    @Published private(set) var recordingLocationConfigured = false
    @Published private(set) var recordingLocationPath: String?
    @Published private(set) var historyRecords: [DictationRecord] = []
    @Published private(set) var retryingRecordIDs: Set<UUID> = []
    @Published private(set) var retryingEnhancementRecordIDs: Set<UUID> = []
    @Published private(set) var dictionaryEntries: [DictionaryEntry] = []
    @Published private(set) var writingStyles: [WritingStyleProfile] = BuiltInWritingStyles.all
    @Published private(set) var appProfiles: [AppDictationProfile] = []
    @Published private(set) var setupMessage: String?
    @Published private(set) var isPreviewTestRunning = false
    @Published private(set) var isSystemAudioTestRunning = false
    @Published private(set) var systemAudioTestMessage: String?
    @Published private(set) var isSmartDictationTestRunning = false
    @Published private(set) var smartDictationTestOutput: String?
    @Published private(set) var availableRelease: GitHubReleaseInfo?
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var updateCheckMessage: String?
    @Published private(set) var latestOutputNotice: String?
    @Published private(set) var latestOutputURL: URL?
    @Published private(set) var localModelState: LocalModelState = .notInstalled
    @Published private(set) var isLocalTranscriptionTestRunning = false
    @Published private(set) var localTranscriptionTestMessage: String?
    @Published private(set) var transcriptionRestartRequired = false
    @Published private(set) var isMeetingRecordingConsentPresented = false
    @Published private(set) var isCoreAudioTapProbeRunning = false
    @Published private(set) var coreAudioTapProbeMessage: String?
    @Published private(set) var isMixedCaptureTestRunning = false
    @Published private(set) var mixedCaptureTestMessage: String?
#if DEBUG
    @Published private(set) var debugNextMeetingTrackFailureRole: RecordingTrackRole?
#endif
    @Published private(set) var queueSnapshot = DictationQueueSnapshot(
        processingCount: 0,
        queuedCount: 0,
        reservationCount: 0
    )

    let settings: AppSettings
    let launchAtLogin: LaunchAtLoginManager
    let recordingLocationStore: RecordingLocationStore
    let dictationHotKeys = HotKeyConfiguration.dictationPresets
    let cancelHotKeys = HotKeyConfiguration.cancelPresets
    let restoreHotKeys = HotKeyConfiguration.restorePresets

    private let dictationHotKeyRegistrar: HotKeyRegistering
    private let cancelHotKeyRegistrar: HotKeyRegistering
    private let restoreHotKeyRegistrar: HotKeyRegistering
    private let applicationRestarter: any ApplicationRestarting
    private let permissionManager: PermissionManaging
    private let microphoneRecorder: AudioRecording
    private let systemAudioRecorder: AudioRecording
    private let injectedProvider: (any TranscriptionProvider)?
    private let injectedInserter: TextInserting?
    private let credentialStore: CredentialStoring
    private let audioDeviceService: AudioDeviceServing
    private let environment: [String: String]
    private let overlay: RecordingOverlayPresenting
    private let focusTargetProvider: @MainActor () -> FocusTarget?
    private let historyStore: DictationHistoryStore
    private let audioStore: AudioStore
    private let transcriptionRunner: TranscriptionRunner
    private let dictionaryStore: DictionaryStore
    private let writingStyleStore: WritingStyleStore
    private let appProfileStore: AppProfileStore
    private let smartDictationPipeline: SmartDictationPipeline
    private let injectedEnhancer: (any TranscriptEnhancing)?
    private let transcriptEnhancerFactory: @MainActor (String) -> any TranscriptEnhancing
    private let livePreviewCoordinator: LivePreviewCoordinator
    private let livePreviewAvailabilityProvider:
        @MainActor (TranscriptionLanguage, SpeechPermissionState) -> LivePreviewAvailability
    private let providerRegistry: TranscriptionProviderRegistry
    private let localModelManager: LocalModelManager
    private var cachedLocalProvider: FluidAudioTranscriptionProvider?
    private var cachedOpenAIProvider: OpenAITranscriptionProvider?
    private var cachedOpenAIProviderModel: String?
    private var cachedOpenAIEnhancer: (any TranscriptEnhancing)?
    private var activeTranscriptionRuntimeSignature: String?
    private let jobStore: DictationJobStore
    private let processingQueue: DictationProcessingQueue
    private let processActivityManager: ProcessActivityManaging
    private let captureProbeArtifactStore = CaptureProbeArtifactStore()
    private let meetingRecordingConsentPresenter: any MeetingRecordingConsentPresenting
    private let coreAudioTapCaptureProbe = CoreAudioTapCaptureProbe()
    private let meetingSessionStore: MeetingSessionStore
    private let meetingHistorySynchronizer: MeetingHistorySynchronizer
    private let injectedMeetingProcessingWorkflow: (any MeetingProcessingRunning)?
    private let meetingTranscriptInsertionGate: any MeetingTranscriptInsertionGating
    private let mixedRecordingCoordinatorFactory:
        @MainActor (AudioDeviceID?) -> any MixedRecordingSessionCoordinating
    private let mixedCaptureTestDuration: Duration

    private var focusTarget: FocusTarget?
    private var lastExternalFocusTarget: FocusTarget?
    private var isHandlingToggle = false
    private var isRestarting = false
    private var lastHotKeyDate = Date.distantPast
    private var overlayDismissTask: Task<Void, Never>?
    private var onboardingWindowController: NSWindowController?
    private var historyWindowController: HistoryWindowController?
    private var audioPlayer: AVAudioPlayer?
    private var previewTestTask: Task<Void, Never>?
    private var systemAudioTestTask: Task<Void, Never>?
    private var coreAudioTapProbeTask: Task<Void, Never>?
    private var mixedCaptureTestTask: Task<Void, Never>?
    private var activeMixedRecordingCoordinator:
        (any MixedRecordingSessionCoordinating)?
    private var mixedMicrophoneLevel: Float = 0
    private var mixedSystemAudioLevel: Float = 0
    private var mixedCaptureWarningState = MixedCaptureWarningState()
    private var mixedClippingWarningExpiryTask: Task<Void, Never>?
    private var localModelInstallTask: Task<Void, Never>?
    private var didLogLivePreviewText = false
    private var cachedAPIKey: String?
    private var didLoadAPIKeyFromKeychain = false
    private var sessionRecorder: AudioRecording?
    private var sessionConfiguration: EffectiveDictationConfiguration?
    private var holdHotKeyIsDown = false
    private var holdReleaseTask: Task<Void, Never>?
    private var activeDictationTask: Task<Void, Never>?
    private var retryTranscriptionTasks: [UUID: Task<Void, Never>] = [:]
    private var jobProcessingTask: Task<Void, Never>?
    private var hasQueueReservation = false
    private var allowsRecordingDuringCompletionPersistence = false
    private var jobInteractionWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var stagedCompletionJobIDs: Set<UUID> = []
    private var pendingCompletionPersistenceJobIDs: Set<UUID> = []
    private var completionPersistenceTask: Task<Void, Never>?
    private var inMemoryJobTargets: [UUID: FocusTarget] = [:]
    private var settingsCancellables: Set<AnyCancellable> = []
    private var hasSessionMeetingRecordingConsent = false
    private var hasVerifiedCoreAudioTapAccess = false
    private var hasResolvedLivePreviewAvailability = false
    private var criticalInteractionActivity: NSObjectProtocol?
    private lazy var pasteboardInserter = PasteboardTextInserter(
        pasteboard: .general,
        restoreDelay: .milliseconds(Int(settings.clipboardRestoreDelay * 1_000))
    )

    private var recorder: AudioRecording {
        if let sessionRecorder { return sessionRecorder }
        return settings.recordingAudioSource == .systemAudio
            ? systemAudioRecorder
            : microphoneRecorder
    }

    convenience init() {
        let environment = ProcessInfo.processInfo.environment
        let isUITesting = environment["FLOWDICTATE_UI_TESTING"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        let credentialStore: any CredentialStoring = isUITesting
            ? TestHostCredentialStore()
            : KeychainCredentialStore()
        let settings = AppSettings()
        let locationStore = RecordingLocationStore()
        let audioStore = AudioStore(locationStore: locationStore)
        self.init(
            settings: settings,
            dictationHotKeyRegistrar: isUITesting ? DisabledHotKeyRegistrar() : GlobalHotKeyRegistrar(registrationID: 1),
            cancelHotKeyRegistrar: isUITesting ? DisabledHotKeyRegistrar() : GlobalHotKeyRegistrar(registrationID: 2),
            restoreHotKeyRegistrar: isUITesting ? DisabledHotKeyRegistrar() : GlobalHotKeyRegistrar(registrationID: 3),
            permissionManager: PermissionManager(),
            recorder: MicrophoneRecorder(store: audioStore),
            provider: nil,
            inserter: nil,
            credentialStore: credentialStore,
            audioDeviceService: AudioDeviceService(),
            launchAtLogin: LaunchAtLoginManager(automaticallyEnableOnFirstLaunch: !isUITesting),
            overlay: RecordingOverlayController(),
            focusTargetProvider: { FocusTarget.capture() },
            environment: environment,
            recordingLocationStore: locationStore,
            historyStore: DictationHistoryStore(),
            audioStore: audioStore,
            automaticallyPresentOnboarding: !isUITesting
        )
    }

    init(
        settings: AppSettings,
        dictationHotKeyRegistrar: HotKeyRegistering,
        cancelHotKeyRegistrar: HotKeyRegistering,
        restoreHotKeyRegistrar: HotKeyRegistering,
        applicationRestarter: (any ApplicationRestarting)? = nil,
        permissionManager: PermissionManaging,
        recorder: AudioRecording,
        systemAudioRecorder: AudioRecording? = nil,
        provider: (any TranscriptionProvider)?,
        inserter: TextInserting?,
        credentialStore: CredentialStoring,
        audioDeviceService: AudioDeviceServing,
        launchAtLogin: LaunchAtLoginManager,
        overlay: RecordingOverlayPresenting,
        focusTargetProvider: @escaping @MainActor () -> FocusTarget?,
        environment: [String: String],
        recordingLocationStore: RecordingLocationStore,
        historyStore: DictationHistoryStore = DictationHistoryStore(),
        audioStore: AudioStore? = nil,
        livePreviewProvider: (any LivePreviewProviding)? = nil,
        dictionaryStore: DictionaryStore? = nil,
        writingStyleStore: WritingStyleStore? = nil,
        appProfileStore: AppProfileStore? = nil,
        transcriptEnhancer: (any TranscriptEnhancing)? = nil,
        transcriptEnhancerFactory: @escaping @MainActor (String) -> any TranscriptEnhancing = {
            OpenAITranscriptEnhancer(apiKey: $0)
        },
        providerRegistry: TranscriptionProviderRegistry = TranscriptionProviderRegistry(),
        localModelManager: LocalModelManager? = nil,
        jobStore: DictationJobStore? = nil,
        processActivityManager: ProcessActivityManaging? = nil,
        meetingRecordingConsentPresenter: (any MeetingRecordingConsentPresenting)? = nil,
        mixedRecordingCoordinatorFactory:
            (@MainActor (AudioDeviceID?) -> any MixedRecordingSessionCoordinating)? = nil,
        meetingProcessingWorkflow: (any MeetingProcessingRunning)? = nil,
        meetingTranscriptInsertionGate:
            (any MeetingTranscriptInsertionGating)? = nil,
        mixedCaptureTestDuration: Duration = .seconds(5),
        livePreviewAvailabilityProvider:
            (@MainActor (TranscriptionLanguage, SpeechPermissionState) -> LivePreviewAvailability)? = nil,
        automaticallyPresentOnboarding: Bool = false
    ) {
        self.settings = settings
        self.dictationHotKeyRegistrar = dictationHotKeyRegistrar
        self.cancelHotKeyRegistrar = cancelHotKeyRegistrar
        self.restoreHotKeyRegistrar = restoreHotKeyRegistrar
        self.applicationRestarter = applicationRestarter ?? WorkspaceApplicationRestarter()
        self.permissionManager = permissionManager
        microphoneRecorder = recorder
        self.systemAudioRecorder = systemAudioRecorder
            ?? SystemAudioRecorder(store: audioStore ?? AudioStore(locationStore: recordingLocationStore))
        injectedProvider = provider
        injectedInserter = inserter
        self.credentialStore = credentialStore
        self.audioDeviceService = audioDeviceService
        self.launchAtLogin = launchAtLogin
        self.overlay = overlay
        self.focusTargetProvider = focusTargetProvider
        self.environment = environment
        self.recordingLocationStore = recordingLocationStore
        self.historyStore = historyStore
        self.audioStore = audioStore ?? AudioStore(locationStore: recordingLocationStore)
        transcriptionRunner = TranscriptionRunner(historyStore: historyStore)
        self.dictionaryStore = dictionaryStore ?? DictionaryStore()
        self.writingStyleStore = writingStyleStore ?? WritingStyleStore()
        self.appProfileStore = appProfileStore ?? AppProfileStore()
        smartDictationPipeline = SmartDictationPipeline(historyStore: historyStore)
        injectedEnhancer = transcriptEnhancer
        self.transcriptEnhancerFactory = transcriptEnhancerFactory
        self.providerRegistry = providerRegistry
        self.localModelManager = localModelManager ?? LocalModelManager()
        let resolvedJobStore = jobStore ?? DictationJobStore()
        self.jobStore = resolvedJobStore
        processingQueue = DictationProcessingQueue(store: resolvedJobStore)
        self.processActivityManager = processActivityManager ?? SystemProcessActivityManager()
        self.meetingRecordingConsentPresenter = meetingRecordingConsentPresenter
            ?? MeetingRecordingConsentWindowController()
        let resolvedMeetingSessionStore = MeetingSessionStore(
            recordingLocationStore: recordingLocationStore
        )
        meetingSessionStore = resolvedMeetingSessionStore
        meetingHistorySynchronizer = MeetingHistorySynchronizer(
            sessionStore: resolvedMeetingSessionStore,
            historyStore: historyStore
        )
        injectedMeetingProcessingWorkflow = meetingProcessingWorkflow
        self.meetingTranscriptInsertionGate = meetingTranscriptInsertionGate
            ?? MeetingTranscriptInsertionGate(store: resolvedMeetingSessionStore)
        self.mixedRecordingCoordinatorFactory = mixedRecordingCoordinatorFactory
            ?? { inputDeviceID in
                MixedRecordingSessionCoordinator(
                    microphoneRecorder: MicrophoneTrackRecorder(
                        inputDeviceID: inputDeviceID
                    ),
                    systemAudioRecorder: SystemAudioTrackRecorder(),
                    store: resolvedMeetingSessionStore
                )
            }
        self.mixedCaptureTestDuration = mixedCaptureTestDuration
        livePreviewCoordinator = LivePreviewCoordinator(
            provider: livePreviewProvider ?? AppleSpeechLivePreviewProvider()
        )
        self.livePreviewAvailabilityProvider = livePreviewAvailabilityProvider
            ?? { language, permission in
                LivePreviewAvailabilityResolver.resolve(
                    language: language,
                    permission: permission
                )
            }

        do {
            let removed = try captureProbeArtifactStore.removeAbandonedArtifacts()
            if !removed.isEmpty {
                FlowLogger.audio.notice(
                    "Removed \(removed.count, privacy: .public) abandoned capture-probe artifact(s)"
                )
            }
        } catch {
            FlowLogger.audio.error(
                "Could not clean capture-probe artifacts: \(error.localizedDescription, privacy: .public)"
            )
        }

        for candidate in [microphoneRecorder, self.systemAudioRecorder] {
            candidate.levelHandler = { [weak self, weak candidate] level in
                let activeLevel = candidate?.isRecording == true ? level : 0
                self?.audioLevel = activeLevel
                self?.overlay.updateLevel(activeLevel)
            }
        }
        livePreviewCoordinator.stateDidChange = { [weak self] state in
            self?.overlay.updatePreview(state)
            switch state {
            case .waiting:
                FlowLogger.audio.info("Live Preview recognition started")
            case .active:
                if self?.didLogLivePreviewText == false {
                    self?.didLogLivePreviewText = true
                    FlowLogger.audio.info("Live Preview produced provisional text")
                }
            case let .unavailable(message):
                self?.recorder.previewBufferHandler = nil
                FlowLogger.audio.notice(
                    "Live Preview unavailable: \(message, privacy: .public)"
                )
            case let .failed(message):
                self?.recorder.previewBufferHandler = nil
                FlowLogger.audio.error(
                    "Live Preview recognition failed: \(message, privacy: .public)"
                )
            case .disabled:
                break
            }
        }

        observeRuntimeSettingChanges()

        registerInitialHotKeys()
        refreshInputDevices()
        refreshConfigurationStatus()
        refreshPermissionStatus()
        Task { [weak self] in
            await self?.refreshSmartDictationData()
            await self?.refreshAppProfiles()
            await self?.refreshLocalModelState()
            if self?.injectedProvider == nil {
                await self?.recoverJobQueue()
            }
            await self?.recoverAndRefreshHistory()
            if self?.settings.updateCheckEnabled == true,
               self?.settings.lastUpdateCheck?.timeIntervalSinceNow ?? -.infinity < -86_400 {
                await self?.checkForUpdates(manual: false)
            }
            guard automaticallyPresentOnboarding, let self, self.needsOnboarding else { return }
            try? await Task.sleep(for: .milliseconds(400))
            self.showOnboarding()
        }
        FlowLogger.app.info("NativeDictate \(NativeDictateVersion.displayString, privacy: .public) started")
    }

    deinit {
        overlayDismissTask?.cancel()
        previewTestTask?.cancel()
        systemAudioTestTask?.cancel()
        coreAudioTapProbeTask?.cancel()
        mixedCaptureTestTask?.cancel()
        localModelInstallTask?.cancel()
        jobProcessingTask?.cancel()
    }

    var primaryActionTitle: String {
        switch state {
        case .recording: "Stop Dictation"
        case .finalizing: "Finalizing…"
        default: "Start Dictation"
        }
    }
    private var isCaptureActive: Bool {
        recorder.isRecording || activeMixedRecordingCoordinator != nil
    }
    var isRecording: Bool { isCaptureActive }
    var canCancel: Bool { state == .recording && isCaptureActive }
    var isProcessing: Bool {
        switch state {
        case .finalizing, .transcribing, .enhancing, .inserting: true
        default: false
        }
    }
    var canStartNewRecording: Bool {
        !isCaptureActive
            && !transcriptionRestartRequired
            && state.acceptsStart
            && !isPreviewTestRunning
            && !isSystemAudioTestRunning
            && !isCoreAudioTapProbeRunning
            && !isMixedCaptureTestRunning
            && !hasQueueReservation
            && (
                queueSnapshot.totalActiveCount == 0
                    || (
                        allowsRecordingDuringCompletionPersistence
                            && queueSnapshot.processingCount == 1
                            && queueSnapshot.queuedCount == 0
                            && queueSnapshot.reservationCount == 0
                    )
            )
    }
    var canPerformPrimaryAction: Bool {
        isCaptureActive ? state == .recording : canStartNewRecording
    }
    var hasCurrentMeetingRecordingConsent: Bool {
        settings.hasAcceptedCurrentMeetingRecordingConsent
            || hasSessionMeetingRecordingConsent
    }
    var latestEnhancementFailure: DictationRecord? {
        historyRecords.first { $0.processingStatus == .enhancementFailed }
    }
    var needsOnboarding: Bool {
        settings.onboardingVersion < Self.currentOnboardingVersion
            || (settings.transcriptionProviderID == .openAI && !apiKeyConfigured)
            || !recordingLocationConfigured
    }
    var transcriptionSetupReady: Bool {
        switch settings.transcriptionProviderID {
        case .openAI:
            apiKeyConfigured
        case .local:
            if case .installed = localModelState { true } else { false }
        }
    }

    var transcriptionLocationSummary: String {
        settings.transcriptionProviderID == .local
            ? "On this Mac · \(LocalModelCatalog.parakeetV3.displayName)"
            : "OpenAI · \(settings.transcriptionModel)"
    }

    var improvementLocationSummary: String {
        let style = selectedWritingStyle
        guard style.usesAI else { return "Off · current style is \(style.name)" }
        if settings.privacyMode == .offline {
            return "Off · Fully offline"
        }
        if settings.privacyMode == .localWithOptionalCloudEnhancement,
           !settings.cloudEnhancementEnabled {
            return "Off · OpenAI permission disabled"
        }
        return "OpenAI · \(style.name)"
    }

    func refreshLocalModelState() async {
        localModelState = await localModelManager.refreshState()
    }

    func installLocalModel() {
        guard localModelInstallTask == nil else { return }
        localModelInstallTask = Task { [weak self] in
            guard let self else { return }
            defer { localModelInstallTask = nil }
            do {
                try await localModelManager.install(
                    policy: NetworkPolicy(
                        mode: settings.privacyMode,
                        cloudEnhancementEnabled: settings.cloudEnhancementEnabled
                    ),
                    stateHandler: { [weak self] state in self?.localModelState = state }
                )
                localModelState = await localModelManager.refreshState()
            } catch {
                setupMessage = error.localizedDescription
                localModelState = .failed(message: error.localizedDescription)
            }
        }
    }

    func removeLocalModel() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let dependentJobs = try await jobStore.all().filter {
                    $0.providerID == TranscriptionProviderID.local.rawValue
                        && ![DictationJobStatus.completed, .cancelled, .insertionDeferred]
                            .contains($0.status)
                }
                guard dependentJobs.isEmpty else {
                    setupMessage = "The local model is still required by \(dependentJobs.count) queued or recoverable dictation(s)."
                    return
                }
                cachedLocalProvider = nil
                try await localModelManager.remove()
                localModelState = await localModelManager.refreshState()
            } catch {
                setupMessage = error.localizedDescription
            }
        }
    }

    func testLocalTranscription() {
        guard settings.transcriptionProviderID == .local,
              case .installed = localModelState,
              !isLocalTranscriptionTestRunning else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Audio for a Local Transcription Test"
        panel.prompt = "Test Locally"
        panel.message = "Choose an existing audio file. NativeDictate will transcribe it locally without inserting text or creating a History entry."
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isLocalTranscriptionTestRunning = true
        localTranscriptionTestMessage = "Transcribing the selected file locally…"
        Task { [weak self] in
            guard let self else { return }
            defer { isLocalTranscriptionTestRunning = false }
            do {
                let provider = try await activeProvider(
                    providerID: .local,
                    model: settings.localTranscriptionModelID,
                    policy: NetworkPolicy(
                        mode: settings.privacyMode,
                        cloudEnhancementEnabled: settings.cloudEnhancementEnabled
                    )
                )
                let result = try await provider.transcribe(
                    TranscriptionRequest(
                        audioURL: url,
                        language: settings.transcriptionLanguage.apiValue
                    )
                )
                localTranscriptionTestMessage = "Local test succeeded (\(result.text.count) characters). Nothing was inserted and no History entry was created."
            } catch {
                localTranscriptionTestMessage = "Local test failed: \(error.localizedDescription)"
            }
        }
    }

    func requestToggle() {
        let now = Date()
        guard activeDictationTask == nil else {
            FlowLogger.hotkey.notice("Ignored duplicate toggle while a recording transition is still running")
            return
        }
        guard now.timeIntervalSince(lastHotKeyDate) >= 0.12 else {
            FlowLogger.hotkey.notice("Ignored duplicate toggle inside the debounce interval")
            return
        }
        lastHotKeyDate = now
        FlowLogger.hotkey.info(
            "Accepted toggle request; recording=\(self.isCaptureActive, privacy: .public)"
        )
        if isCaptureActive {
            // Acknowledge the shortcut immediately. System Audio may need a moment
            // to close a long M4A, but the user should never have to press twice.
            state = .finalizing
            audioLevel = 0
            overlay.show(status: .finalizing)
        } else if state.acceptsStart {
            // A success/error banner can outlive its timer when AppKit's main
            // run loop is busy. Never let that stale result cover the next
            // recording interaction.
            overlay.hide()
        }
        activeDictationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.activeDictationTask = nil }
            await self.toggleDictation()
        }
    }

    func requestCancel() {
        if isMixedCaptureTestRunning {
            mixedCaptureTestTask?.cancel()
            return
        }
        if isPreviewTestRunning {
            previewTestTask?.cancel()
            return
        }
        if isSystemAudioTestRunning {
            systemAudioTestTask?.cancel()
            return
        }
        if state == .transcribing {
            activeDictationTask?.cancel()
            for task in retryTranscriptionTasks.values { task.cancel() }
            return
        }
        guard isCaptureActive else { return }
        Task { await cancelRecording() }
    }

    private func cancelRecording() async {
        if let mixedCoordinator = activeMixedRecordingCoordinator {
            await cancelMixedRecording(using: mixedCoordinator)
            return
        }
        do {
            let recording = try await recorder.stop()
            recorder.previewBufferHandler = nil
            livePreviewCoordinator.cancel()
            let target = focusTarget
            focusTarget = nil
            state = .idle
            audioLevel = 0
            overlay.hide()
            sessionRecorder = nil
            sessionConfiguration = nil
            await releaseQueueReservation()
            endCriticalInteractionActivityIfNeeded()
            Task {
                var record = makeRecord(from: recording, target: target, status: .cancelled)
                record.cancelled = true
                await persistBestEffort(record, context: "cancelled recording")
                await refreshHistory()
            }
        } catch {
            sessionRecorder = nil
            sessionConfiguration = nil
            await releaseQueueReservation()
            fail(error, retainedAudioURL: nil)
        }
    }

    func selectDictationHotKey(id: String) {
        if let value = dictationHotKeys.first(where: { $0.id == id }) { setDictationHotKey(value) }
    }

    func setDictationHotKey(_ value: HotKeyConfiguration) {
        guard value != settings.dictationHotKey else { return }
        let old = settings.dictationHotKey
        do { try registerDictationHotKey(value); settings.dictationHotKey = value }
        catch { try? registerDictationHotKey(old); fail(error, retainedAudioURL: nil) }
    }

    func selectCancelHotKey(id: String) {
        if let value = cancelHotKeys.first(where: { $0.id == id }) { setCancelHotKey(value) }
    }

    func setCancelHotKey(_ value: HotKeyConfiguration) {
        guard value != settings.cancelHotKey else { return }
        let old = settings.cancelHotKey
        do { try registerCancelHotKey(value); settings.cancelHotKey = value }
        catch { try? registerCancelHotKey(old); fail(error, retainedAudioURL: nil) }
    }

    func setRestoreHotKey(_ value: HotKeyConfiguration) {
        guard value != settings.restoreHotKey else { return }
        let old = settings.restoreHotKey
        do { try registerRestoreHotKey(value); settings.restoreHotKey = value }
        catch { try? registerRestoreHotKey(old); fail(error, retainedAudioURL: nil) }
    }

    func selectInputDevice(uid: String?) {
        guard !isCaptureActive else { return }
        settings.inputDeviceUID = uid
        objectWillChange.send()
    }

    func refreshInputDevices() {
        // Core Audio device enumeration can briefly contend with the active input graph.
        // Keep the running recording untouched when Settings becomes active.
        guard !isCaptureActive else { return }
        do {
            inputDevices = try audioDeviceService.inputDevices()
            if let uid = settings.inputDeviceUID, !inputDevices.contains(where: { $0.uid == uid }) {
                settings.inputDeviceUID = nil
            }
        } catch {
            inputDevices = []
            FlowLogger.audio.error("Could not enumerate input devices: \(error.localizedDescription, privacy: .public)")
        }
    }

    func restoreRecordingOverlayAfterSettingsActivation() {
        guard isCaptureActive else { return }
        // Opening a Settings scene can reorder auxiliary AppKit panels. Reassert the
        // existing overlay without restarting the recorder or Speech recognition.
        overlay.show(status: .recording, level: audioLevel, reposition: false)
        overlay.updateSource(settings.recordingAudioSource)
        overlay.updatePreview(livePreviewCoordinator.state)
    }

    func saveAPIKey(_ value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try credentialStore.saveAPIKey(value)
            cachedAPIKey = value
            didLoadAPIKeyFromKeychain = true
            invalidateCachedOpenAIRuntime()
            setupMessage = "API key stored securely in Keychain."
            refreshConfigurationStatus()
            if case .failed = state { state = .idle }
        } catch { fail(error, retainedAudioURL: nil) }
    }

    func validateAndSaveAPIKey(_ value: String) async -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { setupMessage = "Enter an API key."; return false }
        do {
            try await OpenAICredentialValidator().validate(apiKey: value)
            try credentialStore.saveAPIKey(value)
            cachedAPIKey = value
            didLoadAPIKeyFromKeychain = true
            invalidateCachedOpenAIRuntime()
            setupMessage = "Connection verified. API key stored securely in Keychain."
            refreshConfigurationStatus()
            return true
        } catch { setupMessage = error.localizedDescription; return false }
    }

    func deleteAPIKey() {
        do {
            try credentialStore.deleteAPIKey()
            cachedAPIKey = nil
            didLoadAPIKeyFromKeychain = true
            invalidateCachedOpenAIRuntime()
            refreshConfigurationStatus()
        }
        catch { fail(error, retainedAudioURL: nil) }
    }

    func quitAndRestart() {
        guard !isRecording, !isProcessing else {
            setupMessage = "Finish or cancel the current dictation before restarting NativeDictate."
            return
        }
        guard !isRestarting else { return }
        isRestarting = true
        unregisterAllHotKeys()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await applicationRestarter.openNewInstance()
                applicationRestarter.terminateCurrentInstance()
            } catch let launchError {
                isRestarting = false
                do {
                    try registerConfiguredHotKeys()
                    setupMessage = "NativeDictate could not restart: \(launchError.localizedDescription)"
                } catch let restoreError {
                    state = .failed(message: restoreError.localizedDescription, retainedAudioURL: nil)
                    setupMessage = "NativeDictate could not restart (\(launchError.localizedDescription)) or restore its hotkeys: \(restoreError.localizedDescription)"
                }
            }
        }
    }

    func refreshConfigurationStatus() {
        let environmentKey = environment["OPENAI_API_KEY"]
        if environmentKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            apiKeyConfigured = true
        } else {
            apiKeyConfigured = (try? keychainAPIKey())?.isEmpty == false
        }
        recordingLocationConfigured = (try? recordingLocationStore.resolvedDirectory()) != nil
        recordingLocationPath = recordingLocationStore.displayPath
    }

    func refreshPermissionStatus() {
        let previousSpeechPermission = speechPermissionState
        microphonePermissionGranted = permissionManager.hasMicrophoneAccess
        accessibilityPermissionGranted = permissionManager.hasEventPostingAccess
        speechPermissionState = permissionManager.speechRecognitionStatus
        let screenCaptureAuthorized = SystemAudioPermissionService().isAuthorized
        systemAudioPermissionStatus = SystemAudioPermissionStatus.resolve(
            for: settings.recordingAudioSource,
            screenCaptureAuthorized: screenCaptureAuthorized,
            coreAudioTapSucceededThisSession: hasVerifiedCoreAudioTapAccess
        )
        systemAudioPermissionGranted = systemAudioPermissionStatus.readiness == .authorized
        if !hasResolvedLivePreviewAvailability
            || previousSpeechPermission != speechPermissionState {
            refreshLivePreviewAvailability()
        }
    }

    private func observeRuntimeSettingChanges() {
        settings.$transcriptionLanguage
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshLivePreviewAvailability()
            }
            .store(in: &settingsCancellables)

        settings.$transcriptionProviderID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.requireRestartForTranscriptionChange()
            }
            .store(in: &settingsCancellables)

        Publishers.Merge3(
            settings.$privacyMode.map { _ in () },
            settings.$transcriptionModel.map { _ in () },
            settings.$localTranscriptionModelID.map { _ in () }
        )
        .dropFirst(3)
        .sink { [weak self] _ in
            self?.requireRestartForTranscriptionChange()
        }
        .store(in: &settingsCancellables)

        settings.$livePreviewCharacterLimit
            .removeDuplicates()
            .sink { [weak self] limit in
                guard let self else { return }
                livePreviewCoordinator.updateCharacterLimit(
                    settings.overlaySize.clampedLivePreviewCharacterLimit(limit)
                )
            }
            .store(in: &settingsCancellables)

        settings.$overlaySize
            .combineLatest(settings.$overlayPosition)
            .sink { [weak self] configuration in
                guard let self else { return }
                let (size, position) = configuration
                overlay.configure(size: size, position: position)
                if !size.showsLivePreviewText {
                    recorder.previewBufferHandler = nil
                    livePreviewCoordinator.cancel()
                    overlay.updatePreview(.disabled)
                    return
                }
                if state == .recording,
                   settings.recordingAudioSource == .microphone,
                   recorder.isRecording,
                   recorder.previewBufferHandler == nil,
                   livePreviewCoordinator.state == .disabled,
                   settings.livePreviewEnabled {
                    startLivePreviewIfAvailable(size: size)
                    return
                }
                livePreviewCoordinator.updateCharacterLimit(
                    size.clampedLivePreviewCharacterLimit(settings.livePreviewCharacterLimit)
                )
            }
            .store(in: &settingsCancellables)
    }

    private func requireRestartForTranscriptionChange() {
        guard !transcriptionRestartRequired else { return }
        transcriptionRestartRequired = true
        setupMessage = "Transcription settings changed. Quit & Restart is required before the next dictation."
        FlowLogger.transcription.notice(
            "Transcription configuration changed; restart required before recording"
        )
    }

    private func beginCriticalInteractionActivityIfNeeded() {
        guard criticalInteractionActivity == nil else { return }
        criticalInteractionActivity = processActivityManager.beginUserInitiatedActivity(
            reason: "Recording and completing a NativeDictate dictation"
        )
        FlowLogger.app.notice("Critical dictation activity began")
    }

    private func endCriticalInteractionActivityIfNeeded() {
        guard let activity = criticalInteractionActivity else { return }
        criticalInteractionActivity = nil
        processActivityManager.endActivity(activity)
        FlowLogger.app.notice("Critical dictation activity ended")
    }

    private func refreshLivePreviewAvailability() {
        livePreviewAvailability = livePreviewAvailabilityProvider(
            settings.transcriptionLanguage,
            speechPermissionState
        )
        hasResolvedLivePreviewAvailability = true
    }

    func chooseRecordingDirectory(recommended: Bool) {
        do {
            var copiedExistingAudio = false
            let url = try recordingLocationStore.chooseDirectory(recommended: recommended) { previous, selected in
                guard let previous,
                      previous.standardizedFileURL != selected.standardizedFileURL else { return }
                copiedExistingAudio = try copyExistingRecordings(from: previous, to: selected)
            }
            recordingLocationConfigured = true
            recordingLocationPath = url.path
            setupMessage = copiedExistingAudio
                ? "Recordings will be stored in \(url.path). Existing audio was copied safely."
                : "Recordings will be stored in \(url.path)."
        } catch RecordingLocationError.selectionCancelled { return }
        catch { setupMessage = error.localizedDescription }
    }

    func completeOnboarding() {
        guard transcriptionSetupReady, recordingLocationConfigured else {
            setupMessage = settings.transcriptionProviderID == .local
                ? "Install the local model and configure a recordings folder first."
                : "Configure an API key and a recordings folder first."
            return
        }
        settings.onboardingVersion = Self.currentOnboardingVersion
        setupMessage = "NativeDictate is ready."
        onboardingWindowController?.close()
    }

    func showOnboarding() {
        if let window = onboardingWindowController?.window { window.makeKeyAndOrderFront(nil) }
        else {
            onboardingWindowController = OnboardingWindowController(coordinator: self)
            onboardingWindowController?.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func showHistory() {
        if let window = historyWindowController?.window { window.makeKeyAndOrderFront(nil) }
        else {
            let controller = HistoryWindowController(coordinator: self)
            controller.onClose = { [weak self, weak controller] in
                guard let self, self.historyWindowController === controller else { return }
                self.historyWindowController = nil
            }
            historyWindowController = controller
            controller.showWindow(nil)
        }
        Task { await refreshHistory() }
        NSApp.activate(ignoringOtherApps: true)
    }

    func revealRetainedAudio() {
        if case let .failed(_, url?) = state { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    func revealLatestOutput() {
        guard let latestOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([latestOutputURL])
    }
    func revealRecordingsFolder() {
        do { NSWorkspace.shared.open(try recordingLocationStore.resolvedDirectory()) }
        catch { fail(error, retainedAudioURL: nil) }
    }
    func revealAudio(for record: DictationRecord) {
        do { NSWorkspace.shared.activateFileViewerSelecting([try audioURL(for: record)]) }
        catch { fail(error, retainedAudioURL: nil) }
    }
    func revealMeetingSession(for record: DictationRecord) {
        guard let summary = record.meetingSummary else { return }
        do {
            NSWorkspace.shared.activateFileViewerSelecting([
                try meetingSessionDirectory(for: summary.sessionID)
            ])
        } catch {
            fail(error, retainedAudioURL: nil)
        }
    }
    func playAudio(for record: DictationRecord) {
        do { audioPlayer = try AVAudioPlayer(contentsOf: audioURL(for: record)); audioPlayer?.play() }
        catch { fail(error, retainedAudioURL: nil) }
    }
    func playMeetingTrack(for record: DictationRecord, role: RecordingTrackRole) {
        guard let meeting = record.meetingSummary else { return }
        Task {
            do {
                let url = try await meetingSessionStore.audioURL(
                    sessionID: meeting.sessionID,
                    role: role
                )
                audioPlayer?.stop()
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
            } catch {
                fail(error, retainedAudioURL: nil)
            }
        }
    }
    func copyText(from record: DictationRecord) {
        guard let text = record.finalText ?? record.originalTranscript else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }

    func copyOriginalText(from record: DictationRecord) {
        guard let text = record.originalTranscript else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }

    func insertOriginalText(_ record: DictationRecord) {
        guard let text = record.originalTranscript, let target = insertionTarget(for: record) else {
            fail(TextInsertionError.targetUnavailable, retainedAudioURL: try? audioURL(for: record)); return
        }
        var resolved = record
        resolved.finalText = text
        resolved.processingStatus = .completed
        resolved.enhancementFallback = .useOriginal
        Task { await insertStoredText(text, record: resolved, target: target) }
    }

    func exportText(from record: DictationRecord) {
        guard let text = record.finalText ?? record.originalTranscript else { return }
        let panel = NSSavePanel()
        panel.title = "Export Dictation Text"
        panel.nameFieldStringValue = "NativeDictate-\(record.id.uuidString).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { fail(error, retainedAudioURL: nil) }
    }

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "Export NativeDictate Diagnostics"
        panel.nameFieldStringValue = "NativeDictate-Diagnostics.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let statusCounts = Dictionary(grouping: historyRecords, by: { $0.status.rawValue })
            .mapValues(\.count)
        let processingStatusCounts = Dictionary(
            grouping: historyRecords,
            by: { $0.processingStatus.rawValue }
        ).mapValues(\.count)
        let payload: [String: Any] = [
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "apiKeyConfigured": apiKeyConfigured,
            "transcriptionProvider": settings.transcriptionProviderID.rawValue,
            "privacyMode": settings.privacyMode.rawValue,
            "localModelState": String(describing: localModelState),
            "queueProcessingCount": queueSnapshot.processingCount,
            "queueWaitingCount": queueSnapshot.queuedCount,
            "recordingLocationConfigured": recordingLocationConfigured,
            "microphonePermission": microphonePermissionGranted,
            "accessibilityPermission": accessibilityPermissionGranted,
            "historyStatusCounts": statusCounts,
            "smartProcessingStatusCounts": processingStatusCounts,
            "spokenFormattingEnabled": settings.spokenFormattingEnabled,
            "personalDictionaryEnabled": settings.personalDictionaryEnabled,
            "dictionaryEntryCount": dictionaryEntries.count,
            "customWritingStyleCount": writingStyles.filter { !$0.isBuiltIn }.count,
            "onboardingVersion": settings.onboardingVersion
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch { fail(error, retainedAudioURL: nil) }
    }

    func deleteHistoryRecord(_ record: DictationRecord, deleteAudio: Bool) {
        guard record.meetingSummary == nil
            || (!deleteAudio && record.meetingSummary?.canArchiveHistoryEntry == true) else {
            return
        }
        Task {
            do {
                if deleteAudio {
                    if let url = try? audioURL(for: record), FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try await historyStore.delete(id: record.id)
                    await transcriptionRunner.deleteLongFormSession(recordID: record.id)
                } else if record.audioFileSize > 0 {
                    try await historyStore.archive(id: record.id)
                    await transcriptionRunner.deleteLongFormSession(recordID: record.id)
                } else {
                    try await historyStore.delete(id: record.id)
                    await transcriptionRunner.deleteLongFormSession(recordID: record.id)
                }
                if let jobID = record.jobID {
                    try await jobStore.delete(id: jobID)
                }
            } catch {
                FlowLogger.app.error("History deletion failed: \(error.localizedDescription, privacy: .public)")
            }
            await refreshHistory()
        }
    }

    func deleteMeetingSession(_ record: DictationRecord) {
        guard let meeting = record.meetingSummary,
              meeting.canDeleteSession,
              !retryingRecordIDs.contains(record.id) else { return }
        Task {
            do {
                audioPlayer?.stop()
                try await historyStore.delete(id: record.id)
                do {
                    try await meetingSessionStore.delete(sessionID: meeting.sessionID)
                } catch {
                    // Restore discoverability if the irreversible file step did
                    // not succeed. The original session remains authoritative.
                    try? await historyStore.upsert(record)
                    throw error
                }
                if let jobID = record.jobID {
                    try? await jobStore.delete(id: jobID)
                }
                let deletedDirectory = try? meetingSessionDirectory(for: meeting.sessionID)
                if latestOutputURL == deletedDirectory {
                    latestOutputURL = nil
                    latestOutputNotice = nil
                }
                setupMessage = "Meeting session and both original tracks were deleted."
            } catch {
                setupMessage = error.localizedDescription
            }
            await refreshHistory()
        }
    }

    func cancelQueuedDictation(_ record: DictationRecord) {
        guard let jobID = record.jobID, record.jobStatus == .queued else { return }
        Task {
            do {
                queueSnapshot = try await processingQueue.cancelQueued(id: jobID)
                var updated = record
                updated.jobStatus = .cancelled
                updated.status = .cancelled
                updated.cancelled = true
                updated.updatedAt = Date()
                try await historyStore.upsert(updated)
                try await jobStore.delete(id: jobID)
                await refreshHistory()
            } catch {
                setupMessage = error.localizedDescription
            }
        }
    }

    func retryTranscription(_ record: DictationRecord) {
        guard record.canRetry, !retryingRecordIDs.contains(record.id) else { return }
        retryingRecordIDs.insert(record.id)
        retryTranscriptionTasks[record.id] = Task {
            defer {
                retryingRecordIDs.remove(record.id)
                retryTranscriptionTasks[record.id] = nil
                if retryTranscriptionTasks.isEmpty, state == .transcribing {
                    state = .idle
                    overlay.hide()
                }
            }
            var updated = record
            do {
                let url = try audioURL(for: record)
                updated = try await transcriptionRunner.run(
                    record: updated,
                    audioURL: url,
                    language: updated.language,
                    maximumAttempts: settings.automaticRetryEnabled ? 3 : 1,
                    provider: try await activeProvider(
                        providerID: TranscriptionProviderID(rawValue: updated.providerID),
                        model: updated.modelID
                    ),
                    progress: { [weak self] progress in
                        self?.state = .transcribing
                        self?.overlay.show(status: .longForm(progress.statusText))
                    }
                )
                let correctionResult = InlineCorrectionProcessor().process(
                    updated.originalTranscript ?? "",
                    language: updated.language,
                    protectedTerms: settings.personalDictionaryEnabled
                        ? configurationDictionaryTerms(for: updated.language) : []
                )
                updated.correctedTranscript = correctionResult.text
                updated.correctionSummary = correctionResult.summary
                updated.updatedAt = Date()
                try await historyStore.upsert(updated)
                let style = selectedWritingStyle
                let enhancementPolicy = NetworkPolicy(
                    mode: settings.privacyMode,
                    cloudEnhancementEnabled: settings.cloudEnhancementEnabled
                )
                let enhancementAllowed = enhancementPolicy.allows(.enhancement)
                updated = try await smartDictationPipeline.run(
                    record: updated,
                    spokenFormattingEnabled: settings.spokenFormattingEnabled,
                    dictionaryEntries: settings.personalDictionaryEnabled ? dictionaryEntries : [],
                    style: style,
                    enhancementModel: settings.enhancementModel,
                    fallback: settings.smartDictationFallback,
                    enhancer: style.usesAI && enhancementAllowed
                        ? try activeEnhancer(policy: enhancementPolicy) : nil,
                    enhancementAllowed: enhancementAllowed
                )
            } catch let failure as TranscriptionRunFailure {
                updated = failure.record
            } catch let failure as TranscriptionPersistenceFailure {
                FlowLogger.app.error("Retry history persistence failed: \(failure.localizedDescription, privacy: .public)")
                fail(failure, retainedAudioURL: try? audioURL(for: record))
            } catch let failure as SmartDictationRunFailure {
                updated = failure.record
                setupMessage = "Transcription recovered, but Smart Dictation still needs attention."
            } catch {
                if updated.originalTranscript == nil {
                    updated.status = .transcriptionFailed
                    updated.errorCategory = DictationFailureClassifier.category(for: error)
                    updated.errorMessage = error.localizedDescription
                } else {
                    updated.processingStatus = .enhancementFailed
                    updated.enhancementErrorCategory = DictationFailureClassifier.category(for: error)
                    updated.enhancementErrorMessage = error.localizedDescription
                }
                updated.updatedAt = Date()
                await persistBestEffort(updated, context: "transcription retry failure")
            }
            await refreshHistory()
        }
    }

    func continueMeetingProcessing(_ record: DictationRecord) {
        guard let meeting = record.meetingSummary,
              meeting.canResumeProcessing,
              !retryingRecordIDs.contains(record.id) else { return }
        guard !isCaptureActive, state.acceptsStart else {
            setupMessage = "Finish the current dictation before continuing this meeting."
            return
        }

        retryingRecordIDs.insert(record.id)
        retryTranscriptionTasks[record.id] = Task {
            defer {
                retryingRecordIDs.remove(record.id)
                retryTranscriptionTasks[record.id] = nil
            }
            state = .transcribing
            overlay.show(status: .processing)
            do {
                let completed = try await makeMeetingProcessingWorkflow().run(
                    sessionID: meeting.sessionID
                )
                guard completed.status == .completed else {
                    state = .idle
                    overlay.hide()
                    setupMessage = completed.lastErrorMessage
                        ?? "Meeting processing paused. The original tracks remain in History."
                    await refreshHistory()
                    return
                }

                // A resumed session has no trustworthy foreground target. Keep
                // the result in History and require an explicit later insert.
                _ = try await meetingTranscriptInsertionGate.begin(
                    sessionID: completed.id,
                    targetIsAvailable: false
                )
                try await syncLatestMeetingSessionIfAvailable(sessionID: completed.id)
                latestOutputURL = try meetingSessionDirectory(for: completed.id)
                latestOutputNotice =
                    "Meeting processing completed. The transcript is ready in History."
                setupMessage = latestOutputNotice
                state = .idle
                overlay.hide()
                await refreshHistory()
            } catch is CancellationError {
                state = .idle
                overlay.hide()
                await refreshHistory()
            } catch {
                if let latest = try? await meetingSessionStore.load(sessionID: meeting.sessionID) {
                    _ = try? await meetingHistorySynchronizer.sync(latest)
                }
                state = .idle
                overlay.hide()
                setupMessage = error.localizedDescription
                await refreshHistory()
            }
        }
    }

    func reinsert(_ record: DictationRecord) {
        guard let text = record.finalText ?? record.originalTranscript,
              let target = insertionTarget(for: record) else {
            fail(TextInsertionError.targetUnavailable, retainedAudioURL: nil); return
        }
        Task { await insertStoredText(text, record: record, target: target) }
    }

    func restoreLastDictation() {
        guard !isCaptureActive, !isHandlingToggle, state.acceptsStart else {
            setupMessage = "Finish the current dictation before restoring an earlier one."
            return
        }
        Task {
            do {
                guard let record = try await historyStore.lastInsertable() else {
                    failMessage("No successful dictation is available to restore."); return
                }
                reinsert(record)
            } catch {
                FlowLogger.app.error("History restore lookup failed: \(error.localizedDescription, privacy: .public)")
                fail(error, retainedAudioURL: nil)
            }
        }
    }

    func migrateLegacyRecordings() {
        Task {
            guard let legacy = AudioStore.legacyRecordingsDirectory(),
                  let files = try? FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: [.fileSizeKey]),
                  !files.isEmpty else { setupMessage = "No Phase 1 recordings were found."; return }
            do {
                let destination = try audioStore.recordingsDirectory()
                for source in files where source.pathExtension.lowercased() == "wav" {
                    let target = destination.appendingPathComponent(source.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: source, to: target) }
                    let values = try target.resourceValues(forKeys: [.fileSizeKey])
                    let record = DictationRecord.migratedLegacyRecording(
                        relativePath: try audioStore.relativePath(for: target),
                        fileSize: Int64(values.fileSize ?? 0)
                    )
                    try await historyStore.upsert(record)
                }
                setupMessage = "Phase 1 recordings were copied into the selected folder."
                await refreshHistory()
            } catch { setupMessage = error.localizedDescription }
        }
    }

    func openMicrophoneSettings() { permissionManager.openMicrophoneSettings() }
    func openAccessibilitySettings() { permissionManager.openAccessibilitySettings() }
    func openSpeechRecognitionSettings() { permissionManager.openSpeechRecognitionSettings() }
    func openKeyboardSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func requestSpeechRecognitionPermission() {
        Task {
            speechPermissionState = await permissionManager.requestSpeechRecognitionAccess()
            refreshLivePreviewAvailability()
            switch speechPermissionState {
            case .authorized:
                setupMessage = "Speech Recognition is enabled for local Live Preview."
            case .denied:
                setupMessage = "Speech Recognition was denied. You can enable it later in System Settings."
            case .restricted:
                setupMessage = "Speech Recognition is restricted on this Mac."
            case .notDetermined:
                setupMessage = "Speech Recognition permission has not been decided yet."
            }
        }
    }

    func testLivePreview() {
        guard !isPreviewTestRunning, !isCaptureActive, state.acceptsStart else { return }
        guard settings.livePreviewEnabled else {
            setupMessage = "Enable Live Preview before starting the test."
            return
        }
        isPreviewTestRunning = true
        previewTestTask = Task { [weak self] in
            guard let self else { return }
            var testAudioURL: URL?
            do {
                try await permissionManager.ensureMicrophoneAccess()
                if permissionManager.speechRecognitionStatus == .notDetermined {
                    speechPermissionState = await permissionManager.requestSpeechRecognitionAccess()
                    refreshLivePreviewAvailability()
                } else {
                    refreshPermissionStatus()
                }
                guard speechPermissionState == .authorized else {
                    throw FlowPermissionError.speechRecognitionDenied
                }
                recorder.selectInputDevice(
                    try audioDeviceService.deviceID(forUID: settings.inputDeviceUID)
                )
                sessionRecorder = microphoneRecorder
                try await startRecorderWithPreview()
                guard recorder.previewBufferHandler != nil else {
                    throw LivePreviewProviderError.recognizerUnavailable
                }
                overlay.show(status: .recording, reposition: true)
                setupMessage = "Live Preview test is running for 5 seconds…"
                try await Task.sleep(for: .seconds(5))
            } catch is CancellationError {
                setupMessage = "Live Preview test cancelled."
            } catch {
                setupMessage = error.localizedDescription
                FlowLogger.audio.error(
                    "Live Preview test could not start: \(error.localizedDescription, privacy: .public)"
                )
            }

            if recorder.isRecording {
                do {
                    testAudioURL = try await recorder.stop().url
                } catch {
                    FlowLogger.audio.error(
                        "Preview test recorder cleanup failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            recorder.previewBufferHandler = nil
            livePreviewCoordinator.cancel()
            overlay.hide()
            if let testAudioURL {
                do { try FileManager.default.removeItem(at: testAudioURL) }
                catch {
                    FlowLogger.audio.error(
                        "Preview test audio cleanup failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            if setupMessage?.hasPrefix("Live Preview test is running") == true {
                setupMessage = "Live Preview test completed."
            }
            isPreviewTestRunning = false
            previewTestTask = nil
            sessionRecorder = nil
        }
    }

    func selectRecordingAudioSource(_ source: RecordingAudioSource) {
        guard !isCaptureActive,
              !isProcessing,
              !isSystemAudioTestRunning,
              !isCoreAudioTapProbeRunning,
              !isMixedCaptureTestRunning else { return }
        guard settings.recordingAudioSource != source else { return }
        if MixedRecordingConsentGate.requirement(
            for: source,
            hasCurrentConsent: hasCurrentMeetingRecordingConsent
        ) == .confirmationRequired {
            presentMeetingRecordingConsent { [weak self] in
                self?.applyRecordingAudioSource(source)
            }
            return
        }
        applyRecordingAudioSource(source)
    }

    func resetMeetingRecordingConsent() {
        settings.resetMeetingRecordingConsent()
        hasSessionMeetingRecordingConsent = false
        setupMessage = "Mixed recording confirmation was reset."
    }

    func requestMeetingRecordingConsent() {
        presentMeetingRecordingConsent()
    }

#if DEBUG
    func armNextSystemAudioTranscriptionFailure() {
        guard !isCaptureActive, !isProcessing else { return }
        debugNextMeetingTrackFailureRole = .systemAudio
        setupMessage = "The next mixed session will simulate one System Audio transcription failure. Its original track will remain intact."
    }

    func clearNextMeetingTrackTranscriptionFailure() {
        guard !isCaptureActive, !isProcessing else { return }
        debugNextMeetingTrackFailureRole = nil
        setupMessage = "The simulated meeting track failure was cancelled."
    }
#endif

    func runMixedCaptureTest() {
        guard !isMixedCaptureTestRunning,
              !isCoreAudioTapProbeRunning,
              !isSystemAudioTestRunning,
              settings.recordingAudioSource == .mixed,
              activeDictationTask == nil,
              canStartNewRecording else { return }
        guard hasCurrentMeetingRecordingConsent else {
            presentMeetingRecordingConsent()
            return
        }
        refreshConfigurationStatus()
        guard recordingLocationConfigured else {
            showOnboarding()
            setupMessage = RecordingLocationError.notConfigured.localizedDescription
            return
        }

        isMixedCaptureTestRunning = true
        latestOutputNotice = nil
        latestOutputURL = nil
        let runningMessage = "Mixed capture test is preparing two original tracks…"
        setupMessage = runningMessage
        mixedCaptureTestMessage = runningMessage
        mixedCaptureTestTask = Task { [weak self] in
            guard let self else { return }
            let activity = processActivityManager.beginUserInitiatedActivity(
                reason: "Testing synchronized NativeDictate mixed capture"
            )
            defer {
                processActivityManager.endActivity(activity)
                isMixedCaptureTestRunning = false
                mixedCaptureTestTask = nil
                audioLevel = 0
                resetMixedCaptureLevels()
                overlay.hide()
                refreshPermissionStatus()
            }

            var coordinator: (any MixedRecordingSessionCoordinating)?
            do {
                try await permissionManager.ensureMicrophoneAccess()
                let inputDeviceID: AudioDeviceID?
                do {
                    inputDeviceID = try audioDeviceService.deviceID(
                        forUID: settings.inputDeviceUID
                    )
                } catch AudioDeviceServiceError.selectedDeviceUnavailable {
                    settings.inputDeviceUID = nil
                    inputDeviceID = nil
                }

                let createdCoordinator = mixedRecordingCoordinatorFactory(inputDeviceID)
                coordinator = createdCoordinator
                resetMixedCaptureLevels()
                await createdCoordinator.setLevelHandler { [weak self] role, level in
                    Task { @MainActor [weak self] in
                        self?.updateMixedCaptureLevel(level, for: role)
                    }
                }
                await createdCoordinator.setWarningHandler { [weak self] warning in
                    Task { @MainActor [weak self] in
                        self?.handleMixedCaptureWarning(warning)
                    }
                }
                let provider = settings.transcriptionProviderID
                let engineID = provider == .local
                    ? TranscriptionProviderRegistry.local.capabilities.engineID
                    : TranscriptionProviderRegistry.openAI.capabilities.engineID
                let modelID = provider == .local
                    ? settings.localTranscriptionModelID
                    : settings.transcriptionModel
                let session = try await createdCoordinator.start(
                    MixedRecordingSessionRequest(
                        providerID: provider.rawValue,
                        engineID: engineID,
                        modelID: modelID,
                        language: settings.transcriptionLanguage.apiValue,
                        privacyMode: settings.privacyMode,
                        profileID: nil
                    )
                )
                latestOutputURL = try meetingSessionDirectory(for: session.id)
                overlay.updateSource(.mixed)
                overlay.show(status: .recording, reposition: true)
                let recordingMessage = "Mixed capture test is recording microphone and System Audio for 5 seconds…"
                setupMessage = recordingMessage
                mixedCaptureTestMessage = recordingMessage
                try await Task.sleep(for: mixedCaptureTestDuration)

                overlay.show(status: .finalizing)
                let completed = try await createdCoordinator.stop()
                let message = mixedCaptureSummary(completed)
                setupMessage = message
                mixedCaptureTestMessage = message
                latestOutputNotice = message
                FlowLogger.audio.notice(
                    "Mixed capture test completed for session \(completed.id, privacy: .public) with status \(completed.status.rawValue, privacy: .public)"
                )
            } catch is CancellationError {
                if let coordinator {
                    _ = try? await coordinator.cancel()
                }
                let message = "Mixed capture test cancelled. Any finalized original tracks were preserved."
                setupMessage = message
                mixedCaptureTestMessage = message
                if latestOutputURL != nil { latestOutputNotice = message }
            } catch {
                if let coordinator {
                    _ = try? await coordinator.cancel()
                }
                let message = "Mixed capture test failed: \(error.localizedDescription)"
                setupMessage = message
                mixedCaptureTestMessage = message
                if latestOutputURL != nil { latestOutputNotice = message }
                FlowLogger.audio.error(
                    "Mixed capture test failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func cancelMixedCaptureTest() {
        mixedCaptureTestTask?.cancel()
    }

    private func updateMixedCaptureLevel(
        _ level: Float,
        for role: RecordingTrackRole
    ) {
        switch role {
        case .localSpeaker:
            mixedMicrophoneLevel = level
        case .systemAudio:
            mixedSystemAudioLevel = level
        }
        overlay.updateMeetingLevels(
            microphone: mixedMicrophoneLevel,
            systemAudio: mixedSystemAudioLevel
        )
    }

    private func resetMixedCaptureLevels() {
        mixedMicrophoneLevel = 0
        mixedSystemAudioLevel = 0
        overlay.updateMeetingLevels(microphone: 0, systemAudio: 0)
        mixedClippingWarningExpiryTask?.cancel()
        mixedClippingWarningExpiryTask = nil
        mixedCaptureWarningState.reset()
        overlay.updateMeetingWarnings([])
    }

    private func handleMixedCaptureWarning(_ warning: MixedRecordingWarning) {
        let isNew = mixedCaptureWarningState.receive(
            warning,
            at: ProcessInfo.processInfo.systemUptime
        )
        if warning.isTransientClipping, mixedClippingWarningExpiryTask == nil {
            mixedClippingWarningExpiryTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let self else { return }
                    if self.mixedCaptureWarningState.expire(
                        at: ProcessInfo.processInfo.systemUptime
                    ) {
                        self.overlay.updateMeetingWarnings(
                            self.mixedCaptureWarningState.warnings
                        )
                    }
                    if !self.mixedCaptureWarningState.hasTransientWarnings {
                        self.mixedClippingWarningExpiryTask = nil
                        return
                    }
                }
            }
        }
        guard isNew else { return }
        overlay.updateMeetingWarnings(mixedCaptureWarningState.warnings)
        FlowLogger.audio.warning(
            "Mixed capture warning: \(warning.message, privacy: .public)"
        )
    }

#if DEBUG
    func showDebugMicrophoneClippingWarning() {
        guard isCaptureActive, settings.recordingAudioSource == .mixed else { return }
        handleMixedCaptureWarning(
            MixedRecordingWarning(role: .localSpeaker, kind: .clipping)
        )
    }

    func showDebugSystemAudioLostWarning() {
        guard isCaptureActive, settings.recordingAudioSource == .mixed else { return }
        handleMixedCaptureWarning(
            MixedRecordingWarning(role: .systemAudio, kind: .sourceLost)
        )
    }
#endif

    private func meetingSessionDirectory(for id: UUID) throws -> URL {
        try recordingLocationStore.resolvedDirectory()
            .appendingPathComponent("MeetingSessions", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func mixedCaptureSummary(_ session: MixedRecordingSession) -> String {
        let trackSummary = RecordingTrackRole.allCases.compactMap { role in
            session.tracks.first(where: { $0.role == role }).map { track in
                let title = role == .localSpeaker ? "Microphone" : "System Audio"
                let seconds = Double(track.durationMilliseconds) / 1_000
                let peak = track.quality.peakLevel ?? 0
                return String(
                    format: "%@: %.1f s, %d gap(s), peak %.3f",
                    title,
                    seconds,
                    track.gaps.count,
                    peak
                )
            }
        }.joined(separator: "; ")
        return "Mixed capture test completed (\(trackSummary)). Two original tracks and the session manifest were saved; no transcription was started."
    }

    func runCoreAudioTapCaptureProbe(
        duration: SystemAudioProbeDuration = .fiveSeconds
    ) {
        guard !isCoreAudioTapProbeRunning,
              !isSystemAudioTestRunning,
              !isMixedCaptureTestRunning,
              !isCaptureActive,
              !isProcessing else { return }
        isCoreAudioTapProbeRunning = true
        let runningMessage = "Audio-only capture probe is running for \(duration.title.lowercased()). Play System Audio…"
        setupMessage = runningMessage
        coreAudioTapProbeMessage = runningMessage
        coreAudioTapProbeTask = Task { [weak self] in
            guard let self else { return }
            let activity = processActivityManager.beginUserInitiatedActivity(
                reason: "Measuring NativeDictate audio-only capture"
            )
            defer {
                processActivityManager.endActivity(activity)
                isCoreAudioTapProbeRunning = false
                coreAudioTapProbeTask = nil
            }
            do {
                let report = try await coreAudioTapCaptureProbe.run(for: duration.duration)
                if report.hasCapturedSignal {
                    hasVerifiedCoreAudioTapAccess = true
                    refreshPermissionStatus()
                    let message = String(
                        format: "Audio-only probe succeeded: %.1f s requested, %.1f s wall, %.1f s audio, %d callbacks (%d with signal), %d gap(s), largest gap %lld frame(s), timestamps %@, cleanup %@.",
                        report.requestedDuration,
                        report.wallDuration,
                        report.capturedDuration,
                        report.callbackCount,
                        report.nonSilentCallbackCount,
                        report.sampleDiscontinuityCount,
                        report.largestPositiveSampleGapFrames,
                        report.hasMonotonicTimeline ? "monotonic" : "need review",
                        report.cleanup.succeeded ? "passed" : "failed"
                    )
                    setupMessage = message
                    coreAudioTapProbeMessage = message
                } else {
                    let message = "Audio-only probe was inconclusive: no System Audio signal was received. Play audio and retry, or review access in System Settings."
                    setupMessage = message
                    coreAudioTapProbeMessage = message
                }
                FlowLogger.audio.notice(
                    "Core Audio tap probe completed: requested=\(report.requestedDuration, privacy: .public)s wall=\(report.wallDuration, privacy: .public)s audio=\(report.capturedDuration, privacy: .public)s stopDelay=\(report.stopDelay, privacy: .public)s callbacks=\(report.callbackCount, privacy: .public) signalCallbacks=\(report.nonSilentCallbackCount, privacy: .public) signalVerified=\(report.hasCapturedSignal, privacy: .public) sampleRate=\(report.sampleRate, privacy: .public) channels=\(report.channelCount, privacy: .public) hostRegressions=\(report.hostTimeRegressionCount, privacy: .public) sampleRegressions=\(report.sampleTimeRegressionCount, privacy: .public) discontinuities=\(report.sampleDiscontinuityCount, privacy: .public) largestGapFrames=\(report.largestPositiveSampleGapFrames, privacy: .public) cleanup=\(report.cleanup.succeeded, privacy: .public)"
                )
            } catch is CancellationError {
                let message = "Audio-only capture probe cancelled."
                setupMessage = message
                coreAudioTapProbeMessage = message
            } catch {
                let message = "Audio-only capture probe failed: \(error.localizedDescription)"
                setupMessage = message
                coreAudioTapProbeMessage = message
                FlowLogger.audio.error(
                    "Core Audio tap probe failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func runCoreAudioTapRepeatedCaptureProbe() {
        guard !isCoreAudioTapProbeRunning,
              !isSystemAudioTestRunning,
              !isMixedCaptureTestRunning,
              !isCaptureActive,
              !isProcessing else { return }
        isCoreAudioTapProbeRunning = true
        let runningMessage = "Audio-only capture probe is running 10 start/stop cycles…"
        setupMessage = runningMessage
        coreAudioTapProbeMessage = runningMessage
        coreAudioTapProbeTask = Task { [weak self] in
            guard let self else { return }
            let activity = processActivityManager.beginUserInitiatedActivity(
                reason: "Measuring repeated NativeDictate audio-only capture"
            )
            defer {
                processActivityManager.endActivity(activity)
                isCoreAudioTapProbeRunning = false
                coreAudioTapProbeTask = nil
            }
            do {
                let report = try await coreAudioTapCaptureProbe.runRepeated()
                if report.hasCapturedSignal {
                    hasVerifiedCoreAudioTapAccess = true
                    refreshPermissionStatus()
                }
                let healthy = report.allCleanupSucceeded
                    && report.allTimelinesMonotonic
                    && report.sampleDiscontinuityCount == 0
                if report.hasCapturedSignal {
                    let message = String(
                        format: "Audio-only cycle probe completed: %d/10 cycles, %d callbacks, %d gap(s), cleanup %@.",
                        report.completedCycleCount,
                        report.totalCallbackCount,
                        report.sampleDiscontinuityCount,
                        report.allCleanupSucceeded ? "passed" : "failed"
                    )
                    setupMessage = message
                    coreAudioTapProbeMessage = message
                } else {
                    let message = "Audio-only cycle probe was inconclusive: no System Audio signal was received. Play audio and retry, or review access in System Settings."
                    setupMessage = message
                    coreAudioTapProbeMessage = message
                }
                FlowLogger.audio.notice(
                    "Core Audio tap cycle probe completed: cycles=\(report.completedCycleCount, privacy: .public) callbacks=\(report.totalCallbackCount, privacy: .public) signalCallbacks=\(report.totalNonSilentCallbackCount, privacy: .public) hostRegressions=\(report.hostTimeRegressionCount, privacy: .public) sampleRegressions=\(report.sampleTimeRegressionCount, privacy: .public) discontinuities=\(report.sampleDiscontinuityCount, privacy: .public) largestGapFrames=\(report.largestPositiveSampleGapFrames, privacy: .public) cleanup=\(report.allCleanupSucceeded, privacy: .public) healthy=\(healthy, privacy: .public)"
                )
            } catch is CancellationError {
                let message = "Audio-only cycle probe cancelled."
                setupMessage = message
                coreAudioTapProbeMessage = message
            } catch {
                let message = "Audio-only cycle probe failed: \(error.localizedDescription)"
                setupMessage = message
                coreAudioTapProbeMessage = message
                FlowLogger.audio.error(
                    "Core Audio tap cycle probe failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func cancelCoreAudioTapCaptureProbe() {
        coreAudioTapProbeTask?.cancel()
    }

    private func applyRecordingAudioSource(_ source: RecordingAudioSource) {
        microphoneRecorder.previewBufferHandler = nil
        livePreviewCoordinator.cancel()
        settings.recordingAudioSource = source
        refreshPermissionStatus()
    }

    private func presentMeetingRecordingConsent(
        afterConfirmation: @escaping @MainActor () -> Void = {}
    ) {
        guard !isMeetingRecordingConsentPresented else { return }
        isMeetingRecordingConsentPresented = true
        meetingRecordingConsentPresenter.present(
            onConfirm: { [weak self] rememberConfirmation in
                guard let self else { return }
                if rememberConfirmation {
                    self.settings.acceptCurrentMeetingRecordingConsent()
                } else {
                    self.hasSessionMeetingRecordingConsent = true
                }
                self.isMeetingRecordingConsentPresented = false
                self.setupMessage = self.settings.dictationActivationMode == .pressAndHold
                    ? "Confirmation saved. Hold the dictation shortcut again to start recording."
                    : "Mixed recording confirmation saved. Start recording when you are ready."
                afterConfirmation()
            },
            onCancel: { [weak self] in
                self?.isMeetingRecordingConsentPresented = false
            }
        )
    }

    func openSystemAudioSettings() {
        SystemAudioPermissionService().openSystemSettings(
            for: systemAudioPermissionStatus.backend
        )
    }

    func refreshPermissionStatuses() {
        refreshPermissionStatus()
    }

    func testSystemAudio(duration: SystemAudioProbeDuration = .fiveSeconds) {
        guard !isSystemAudioTestRunning,
              !isCoreAudioTapProbeRunning,
              !isMixedCaptureTestRunning,
              !isCaptureActive,
              state.acceptsStart else { return }
        isSystemAudioTestRunning = true
        let runningMessage = "ScreenCaptureKit probe is running for \(duration.title.lowercased())…"
        setupMessage = runningMessage
        systemAudioTestMessage = runningMessage
        systemAudioTestTask = Task { [weak self] in
            guard let self else { return }
            let activity = processActivityManager.beginUserInitiatedActivity(
                reason: "Measuring NativeDictate ScreenCaptureKit system audio"
            )
            var temporaryURL: URL?
            var probeArtifactURL: URL?
            defer {
                processActivityManager.endActivity(activity)
            }
            do {
                let artifactURL = try captureProbeArtifactStore.makeURL()
                probeArtifactURL = artifactURL
                sessionRecorder = systemAudioRecorder
                try await systemAudioRecorder.start(at: artifactURL)
                overlay.updateSource(.systemAudio)
                overlay.show(status: .recording, reposition: true)
                try await Task.sleep(for: duration.duration)
                let result = try await systemAudioRecorder.stop()
                temporaryURL = result.url
                if let temporaryURL { try validateSystemAudioTestFile(temporaryURL) }
                let fileSize = temporaryURL.flatMap {
                    try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
                } ?? 0
                if let report = systemAudioRecorder.lastTimelineReport {
                    let message = String(
                        format: "ScreenCaptureKit probe completed: %.1f s requested, %.1f s wall, %.1f s audio, %d callbacks, %d gap(s), largest gap %lld frame(s), timestamps %@, sample-rate changes %d, %.1f MB temporary file.",
                        TimeInterval(duration.rawValue),
                        result.duration,
                        report.capturedDuration,
                        report.callbackCount,
                        report.discontinuityCount,
                        report.largestPositiveGapFrames,
                        report.hasMonotonicTimeline ? "monotonic" : "need review",
                        report.sampleRateChangeCount,
                        Double(fileSize) / 1_000_000
                    )
                    setupMessage = message
                    systemAudioTestMessage = message
                    FlowLogger.audio.notice(
                        "ScreenCaptureKit timeline probe completed: requested=\(duration.rawValue, privacy: .public)s wall=\(result.duration, privacy: .public)s audio=\(report.capturedDuration, privacy: .public)s callbacks=\(report.callbackCount, privacy: .public) missingPTS=\(report.missingPresentationTimeCount, privacy: .public) regressions=\(report.presentationTimeRegressionCount, privacy: .public) discontinuities=\(report.discontinuityCount, privacy: .public) largestGapFrames=\(report.largestPositiveGapFrames, privacy: .public) sampleRateChanges=\(report.sampleRateChangeCount, privacy: .public) temporaryFileBytes=\(fileSize, privacy: .public)"
                    )
                } else {
                    let message = "System Audio test completed successfully."
                    setupMessage = message
                    systemAudioTestMessage = message
                }
            } catch is CancellationError {
                if systemAudioRecorder.isRecording {
                    temporaryURL = try? await systemAudioRecorder.stop().url
                }
                let message = "System Audio test cancelled."
                setupMessage = message
                systemAudioTestMessage = message
            } catch {
                if systemAudioRecorder.isRecording { _ = try? await systemAudioRecorder.stop() }
                let message = error.localizedDescription
                setupMessage = message
                systemAudioTestMessage = message
            }
            for url in Set([temporaryURL, probeArtifactURL].compactMap { $0 }) {
                try? captureProbeArtifactStore.removeArtifact(at: url)
            }
            sessionRecorder = nil
            audioLevel = 0
            overlay.hide()
            isSystemAudioTestRunning = false
            systemAudioTestTask = nil
            refreshPermissionStatus()
        }
    }

    func cancelSystemAudioTest() {
        systemAudioTestTask?.cancel()
    }

    private func validateSystemAudioTestFile(_ url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.fileFormat.sampleRate > 0 else {
            throw SystemAudioRecorderError.noAudioReceived
        }
    }

    func requestMicrophonePermission() async {
        do {
            try await permissionManager.ensureMicrophoneAccess()
        } catch {
            setupMessage = error.localizedDescription
        }
        refreshPermissionStatus()
    }

    func toggleDictation() async {
        guard !isHandlingToggle,
              !isPreviewTestRunning,
              !isSystemAudioTestRunning,
              !isMixedCaptureTestRunning else { return }
        isHandlingToggle = true
        defer { isHandlingToggle = false }
        if activeMixedRecordingCoordinator != nil { await stopMixedRecordingAndProcess() }
        else if recorder.isRecording { await stopAndTranscribe() }
        else if canStartNewRecording { await startRecording() }
    }

    func refreshHistory() async {
        do { historyRecords = try await historyStore.all() }
        catch { FlowLogger.app.error("History load failed: \(error.localizedDescription, privacy: .public)") }
    }

    func refreshSmartDictationData() async {
        do {
            dictionaryEntries = try await dictionaryStore.all()
            writingStyles = try await writingStyleStore.all()
            if !writingStyles.contains(where: { $0.id == settings.writingStyleID && $0.isEnabled }) {
                settings.writingStyleID = BuiltInWritingStyles.originalID
            }
        } catch {
            FlowLogger.app.error("Smart Dictation data load failed: \(error.localizedDescription, privacy: .public)")
            setupMessage = error.localizedDescription
        }
    }

    func refreshAppProfiles() async {
        do { appProfiles = try await appProfileStore.all() }
        catch { setupMessage = error.localizedDescription }
    }

    func saveAppProfile(_ profile: AppDictationProfile) {
        let previous = appProfiles.first { $0.id == profile.id }
        let changesTranscriptionRuntime = profileTranscriptionRuntimeChanged(
            from: previous,
            to: profile
        )
        Task {
            do {
                try await appProfileStore.upsert(profile)
                await refreshAppProfiles()
                if changesTranscriptionRuntime {
                    requireRestartForTranscriptionChange()
                } else {
                    setupMessage = "App profile saved."
                }
            } catch { setupMessage = error.localizedDescription }
        }
    }

    func deleteAppProfile(_ profile: AppDictationProfile) {
        let changesTranscriptionRuntime = profile.isEnabled
            && (profile.transcriptionProviderID != nil || profile.transcriptionModel != nil)
        Task {
            do {
                try await appProfileStore.delete(id: profile.id)
                await refreshAppProfiles()
                if changesTranscriptionRuntime {
                    requireRestartForTranscriptionChange()
                }
            } catch { setupMessage = error.localizedDescription }
        }
    }

    private func profileTranscriptionRuntimeChanged(
        from previous: AppDictationProfile?,
        to updated: AppDictationProfile
    ) -> Bool {
        guard let previous else {
            return updated.isEnabled
                && (updated.transcriptionProviderID != nil || updated.transcriptionModel != nil)
        }
        return previous.transcriptionProviderID != updated.transcriptionProviderID
            || previous.transcriptionModel != updated.transcriptionModel
            || (
                previous.isEnabled != updated.isEnabled
                    && (previous.transcriptionProviderID != nil
                        || previous.transcriptionModel != nil
                        || updated.transcriptionProviderID != nil
                        || updated.transcriptionModel != nil)
            )
    }

    var recentProfileCandidates: [(bundleIdentifier: String, displayName: String)] {
        var seen = Set<String>()
        return historyRecords.compactMap { record in
            guard let bundle = record.targetBundleIdentifier,
                  let name = record.targetApplicationName,
                  !bundle.isEmpty,
                  !seen.contains(bundle),
                  !appProfiles.contains(where: { $0.bundleIdentifier == bundle }) else { return nil }
            seen.insert(bundle)
            return (bundle, name)
        }
    }

    var usageStatistics: UsageStatistics {
        usageStatistics(period: .total)
    }

    func usageStatistics(
        period: UsageStatisticsPeriod,
        now: Date = Date()
    ) -> UsageStatistics {
        let since = [period.startDate(relativeTo: now), settings.usageStatisticsResetDate]
            .compactMap { $0 }
            .max()
        return UsageStatistics.calculate(
            records: historyRecords,
            typingWordsPerMinute: settings.typingWordsPerMinute,
            since: since
        )
    }

    func checkForUpdates(manual: Bool = true) async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        if manual { updateCheckMessage = nil }
        do {
            try NetworkPolicy(
                mode: settings.privacyMode,
                cloudEnhancementEnabled: settings.cloudEnhancementEnabled
            ).requirePermission(for: .updateCheck)
        } catch {
            if manual {
                updateCheckMessage = "Update checks are disabled in Fully offline mode."
                setupMessage = updateCheckMessage
            }
            return
        }
        settings.lastUpdateCheck = Date()
        do {
            let release = try await GitHubReleaseChecker().latestStableRelease()
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "0"
            if let release, GitHubReleaseChecker.isNewer(release.version, than: current) {
                availableRelease = release
                if manual {
                    let message = "NativeDictate \(release.version) is available."
                    updateCheckMessage = message
                    setupMessage = message
                }
            } else if manual {
                availableRelease = nil
                let message = "NativeDictate is up to date."
                updateCheckMessage = message
                setupMessage = message
            }
        } catch {
            if manual {
                updateCheckMessage = error.localizedDescription
                setupMessage = error.localizedDescription
            }
        }
    }

    func openAvailableRelease() {
        guard let availableRelease else { return }
        NSWorkspace.shared.open(availableRelease.pageURL)
    }

    func saveDictionaryEntry(_ entry: DictionaryEntry) {
        Task {
            do {
                try await dictionaryStore.upsert(entry)
                await refreshSmartDictationData()
                setupMessage = "Dictionary entry saved."
            } catch { setupMessage = error.localizedDescription }
        }
    }

    func deleteDictionaryEntry(_ entry: DictionaryEntry) {
        Task {
            do {
                try await dictionaryStore.delete(id: entry.id)
                await refreshSmartDictationData()
                setupMessage = "Dictionary entry deleted."
            } catch { setupMessage = error.localizedDescription }
        }
    }

    func saveWritingStyle(_ style: WritingStyleProfile) {
        Task {
            do {
                try await writingStyleStore.upsert(style)
                await refreshSmartDictationData()
                settings.writingStyleID = style.id
                setupMessage = "Writing style saved."
            } catch { setupMessage = error.localizedDescription }
        }
    }

    func duplicateWritingStyle(_ style: WritingStyleProfile) {
        Task {
            do {
                let copy = try await writingStyleStore.duplicate(style)
                await refreshSmartDictationData()
                settings.writingStyleID = copy.id
                setupMessage = "Writing style duplicated."
            } catch { setupMessage = error.localizedDescription }
        }
    }

    func deleteWritingStyle(_ style: WritingStyleProfile) {
        Task {
            do {
                try await writingStyleStore.delete(id: style.id)
                if settings.writingStyleID == style.id {
                    settings.writingStyleID = BuiltInWritingStyles.originalID
                }
                await refreshSmartDictationData()
                setupMessage = "Writing style deleted."
            } catch { setupMessage = error.localizedDescription }
        }
    }

    func exportDictionary() { chooseSmartDictationExport(filename: "NativeDictate-Dictionary.json") { url in try await self.dictionaryStore.export(to: url) } }
    func exportWritingStyles() { chooseSmartDictationExport(filename: "NativeDictate-Writing-Styles.json") { url in try await self.writingStyleStore.export(to: url) } }
    func importDictionary() { chooseSmartDictationImport { url in try await self.dictionaryStore.importFile(from: url) } }
    func importWritingStyles() { chooseSmartDictationImport { url in try await self.writingStyleStore.importFile(from: url) } }

    func testSmartDictation(_ text: String) {
        guard !isSmartDictationTestRunning else { return }
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { smartDictationTestOutput = "Enter sample text first."; return }
        isSmartDictationTestRunning = true
        Task {
            defer { isSmartDictationTestRunning = false }
            let formatted = settings.spokenFormattingEnabled
                ? SpokenFormattingProcessor().process(original, language: settings.transcriptionLanguage.apiValue).text
                : original
            let entries = settings.personalDictionaryEnabled ? dictionaryEntries : []
            let local = PersonalDictionaryProcessor().process(
                formatted,
                entries: entries,
                language: settings.transcriptionLanguage.apiValue
            ).text
            let style = selectedWritingStyle
            guard style.usesAI else { smartDictationTestOutput = local; return }
            let enhancementPolicy = NetworkPolicy(
                mode: settings.privacyMode,
                cloudEnhancementEnabled: settings.cloudEnhancementEnabled
            )
            guard enhancementPolicy.allows(.enhancement) else {
                smartDictationTestOutput = local
                return
            }
            do {
                let result = try await activeEnhancer(policy: enhancementPolicy).enhance(
                    TranscriptEnhancementRequest(
                        text: local,
                        styleInstruction: style.instruction,
                        language: settings.transcriptionLanguage.apiValue,
                        model: settings.enhancementModel,
                        protectedTerms: entries.map(\.replacement)
                    )
                )
                smartDictationTestOutput = result.text
            } catch { smartDictationTestOutput = error.localizedDescription }
        }
    }

    func retryEnhancement(_ record: DictationRecord) {
        guard record.canRetryEnhancement, !retryingEnhancementRecordIDs.contains(record.id) else { return }
        retryingEnhancementRecordIDs.insert(record.id)
        Task {
            defer { retryingEnhancementRecordIDs.remove(record.id) }
            do {
                let style = writingStyles.first { $0.id == record.writingStyleID } ?? selectedWritingStyle
                _ = try await smartDictationPipeline.retryEnhancement(
                    record: record,
                    style: style,
                    model: record.enhancementModelID ?? settings.enhancementModel,
                    fallback: .ask,
                    dictionaryEntries: settings.personalDictionaryEnabled ? dictionaryEntries : [],
                    enhancer: try activeEnhancer()
                )
                setupMessage = "Smart Dictation completed."
            } catch { setupMessage = error.localizedDescription }
            await refreshHistory()
        }
    }

    func reprocess(_ record: DictationRecord, writingStyleID: UUID) {
        guard let style = writingStyles.first(where: { $0.id == writingStyleID }) else { return }
        Task {
            do {
                let enhancementPolicy = NetworkPolicy(
                    mode: settings.privacyMode,
                    cloudEnhancementEnabled: settings.cloudEnhancementEnabled
                )
                let enhancementAllowed = enhancementPolicy.allows(.enhancement)
                _ = try await smartDictationPipeline.processWithStyle(
                    record: record,
                    style: style,
                    model: settings.enhancementModel,
                    fallback: .ask,
                    dictionaryEntries: settings.personalDictionaryEnabled ? dictionaryEntries : [],
                    enhancer: style.usesAI && enhancementAllowed
                        ? try activeEnhancer(policy: enhancementPolicy) : nil,
                    enhancementAllowed: enhancementAllowed
                )
                setupMessage = "Dictation reprocessed. Review the result in History."
            } catch { setupMessage = error.localizedDescription }
            await refreshHistory()
        }
    }

    func reapplyLocalRules(_ record: DictationRecord) {
        guard record.originalTranscript != nil else { return }
        let style = writingStyles.first { $0.id == record.writingStyleID } ?? selectedWritingStyle
        Task {
            do {
                _ = try await smartDictationPipeline.recoverInterruptedLocalProcessing(
                    record: record,
                    spokenFormattingEnabled: settings.spokenFormattingEnabled,
                    dictionaryEntries: settings.personalDictionaryEnabled ? dictionaryEntries : [],
                    intendedStyle: style
                )
                setupMessage = style.usesAI
                    ? "Local rules reapplied. Retry the writing style from History when ready."
                    : "Local rules reapplied. Review the result in History."
            } catch { setupMessage = error.localizedDescription }
            await refreshHistory()
        }
    }

    func insertLocallyProcessedText(_ record: DictationRecord) {
        guard let text = record.dictionaryTranscript ?? record.formattedTranscript ?? record.originalTranscript,
              let target = insertionTarget(for: record) else {
            fail(TextInsertionError.targetUnavailable, retainedAudioURL: try? audioURL(for: record)); return
        }
        var resolved = record
        resolved.finalText = text
        resolved.processingStatus = .completed
        resolved.enhancementFallback = .useLocallyProcessed
        Task { await insertStoredText(text, record: resolved, target: target) }
    }

    func applyRetentionSettings() {
        Task {
            do {
                try await meetingHistorySynchronizer.syncLinkedSessions()
                try await applyRetentionPolicy()
                let result = try await historyStore.applyRetention(
                    maximumAgeDays: settings.historyRetentionDays,
                    maximumRecordCount: settings.historyMaximumRecordCount
                )
                FlowLogger.app.info(
                    "Manual retention removed \(result.removedCount, privacy: .public) and archived \(result.archivedCount, privacy: .public) records"
                )
                setupMessage = "Retention settings applied."
            } catch {
                FlowLogger.app.error("Manual retention failed: \(error.localizedDescription, privacy: .public)")
                setupMessage = error.localizedDescription
            }
            await refreshHistory()
        }
    }

    private func recoverAndRefreshHistory() async {
        do {
            let recovered = try await historyStore.recoverInterrupted()
            await transcriptionRunner.recoverInterruptedLongFormSessions()
            _ = try await meetingHistorySynchronizer.recoverLinkedSessions()
            for record in recovered
            where record.processingStatus == .notStarted
                && record.enhancementErrorCategory == .interrupted
                && record.originalTranscript != nil {
                let intendedStyle = writingStyles.first { $0.id == record.writingStyleID }
                    ?? BuiltInWritingStyles.all[0]
                _ = try await smartDictationPipeline.recoverInterruptedLocalProcessing(
                    record: record,
                    spokenFormattingEnabled: record.spokenFormattingEnabled,
                    dictionaryEntries: settings.personalDictionaryEnabled ? dictionaryEntries : [],
                    intendedStyle: intendedStyle
                )
            }
            try await recoverOrphanedAudio()
            try await applyRetentionPolicy()
            let historyResult = try await historyStore.applyRetention(
                maximumAgeDays: settings.historyRetentionDays,
                maximumRecordCount: settings.historyMaximumRecordCount
            )
            if historyResult.removedCount > 0 || historyResult.archivedCount > 0 {
                FlowLogger.app.info(
                    "History retention removed \(historyResult.removedCount, privacy: .public) and archived \(historyResult.archivedCount, privacy: .public) records"
                )
            }
        }
        catch { FlowLogger.app.error("Recovery failed: \(error.localizedDescription, privacy: .public)") }
        await refreshHistory()
    }

    func applyRetentionPolicy(now: Date = Date()) async throws {
        let days = settings.audioRetentionDays
        guard days >= 0, recordingLocationConfigured,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return }
        for var record in try await historyStore.all(includeArchived: true)
        where record.status == .completed
            && record.recordingEndedAt < cutoff
            && record.audioFileSize > 0
            && !record.isAutomaticallyProtected {
            if let meeting = record.meetingSummary {
                guard let manifest = try await meetingSessionStore.load(
                    sessionID: meeting.sessionID
                ), manifest.recordID == record.id,
                    manifest.status == .completed,
                    manifest.transcriptInsertionState == .completed else {
                    // History is a snapshot. A missing or newer manifest must
                    // never authorize deleting recoverable original tracks.
                    continue
                }
                // A meeting is one retention unit. Removing only the synthetic
                // History path would leave both originals and every derived
                // artifact orphaned outside the normal Audio directory.
                try await meetingSessionStore.delete(sessionID: meeting.sessionID)
                record.meetingSummary = meeting.withoutStoredSessionArtifacts()
            } else {
                let url = try audioURL(for: record)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
            record.audioFileSize = 0
            record.updatedAt = now
            try await historyStore.upsert(record)
        }
    }

    private func recoverOrphanedAudio() async throws {
        guard recordingLocationConfigured else { return }
        let known = try await historyStore.knownAudioRelativePaths()
        let directory = try audioStore.recordingsDirectory()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        for file in files where ["wav", "m4a", "recording"].contains(file.pathExtension.lowercased()) {
            let relative = try audioStore.relativePath(for: file)
            guard !known.contains(relative) else { continue }
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            try await historyStore.upsert(.recoveredAudio(
                relativePath: relative,
                fileSize: Int64(values.fileSize ?? 0),
                message: "Audio was found without a completed history entry."
            ))
        }
    }

    private func copyExistingRecordings(from previousRoot: URL, to selectedRoot: URL) throws -> Bool {
        let source = previousRoot.appendingPathComponent("Audio", isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else { return false }

        let previousAccess = previousRoot.startAccessingSecurityScopedResource()
        let selectedAccess = selectedRoot.startAccessingSecurityScopedResource()
        defer {
            if previousAccess { previousRoot.stopAccessingSecurityScopedResource() }
            if selectedAccess { selectedRoot.stopAccessingSecurityScopedResource() }
        }

        let destination = selectedRoot.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let enumerator = FileManager.default.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        var copiedFile = false
        for case let item as URL in enumerator {
            let relativePath = String(item.path.dropFirst(source.path.count + 1))
            let target = destination.appendingPathComponent(relativePath)
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } else if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.copyItem(at: item, to: target)
                copiedFile = true
            }
        }
        return copiedFile
    }

    private func registerInitialHotKeys() {
        do {
            try registerConfiguredHotKeys()
        } catch {
            state = .failed(message: error.localizedDescription, retainedAudioURL: nil)
        }
    }

    private func registerConfiguredHotKeys() throws {
        do {
            try registerDictationHotKey(settings.dictationHotKey)
            try registerCancelHotKey(settings.cancelHotKey)
            try registerRestoreHotKey(settings.restoreHotKey)
        } catch {
            unregisterAllHotKeys()
            throw error
        }
    }

    private func unregisterAllHotKeys() {
        dictationHotKeyRegistrar.unregister()
        cancelHotKeyRegistrar.unregister()
        restoreHotKeyRegistrar.unregister()
    }
    private func registerDictationHotKey(_ value: HotKeyConfiguration) throws {
        try dictationHotKeyRegistrar.register(
            value,
            pressed: { [weak self] in self?.dictationHotKeyPressed() },
            released: { [weak self] in self?.dictationHotKeyReleased() }
        )
    }

    private func dictationHotKeyPressed() {
        guard settings.dictationActivationMode == .pressAndHold else {
            requestToggle(); return
        }
        guard !holdHotKeyIsDown else { return }
        holdReleaseTask?.cancel()
        holdHotKeyIsDown = true
        guard !isCaptureActive else { return }
        requestToggle()
    }

    private func dictationHotKeyReleased() {
        guard settings.dictationActivationMode == .pressAndHold, holdHotKeyIsDown else { return }
        holdHotKeyIsDown = false
        holdReleaseTask?.cancel()
        holdReleaseTask = Task { [weak self] in
            guard let self else { return }
            // Starting ScreenCaptureKit can take a moment. Remember an early key-up
            // and stop as soon as the recorder has actually entered recording state.
            for _ in 0..<80 {
                guard !Task.isCancelled, !self.holdHotKeyIsDown else { return }
                if self.isCaptureActive, !self.isHandlingToggle {
                    await self.toggleDictation()
                    return
                }
                if !self.isHandlingToggle { return }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
    }
    private func registerCancelHotKey(_ value: HotKeyConfiguration) throws {
        try cancelHotKeyRegistrar.register(value) { [weak self] in self?.requestCancel() }
    }
    private func registerRestoreHotKey(_ value: HotKeyConfiguration) throws {
        try restoreHotKeyRegistrar.register(value) { [weak self] in self?.restoreLastDictation() }
    }

    private func startRecording() async {
        latestOutputNotice = nil
        latestOutputURL = nil
        let isMixedRequest = settings.recordingAudioSource == .mixed
        let startSignpost = isMixedRequest
            ? FlowLogger.meetingSignposter.beginInterval("Meeting Start Request")
            : nil
        defer {
            if let startSignpost {
                FlowLogger.meetingSignposter.endInterval(
                    "Meeting Start Request", startSignpost
                )
            }
        }
        guard !transcriptionRestartRequired else {
            setupMessage = "Transcription settings changed. Use Quit & Restart before starting another dictation."
            return
        }
        if settings.recordingAudioSource == .mixed {
            guard hasCurrentMeetingRecordingConsent else {
                FlowLogger.meetingSignposter.emitEvent("Meeting Consent Required")
                presentMeetingRecordingConsent()
                return
            }
        }
        refreshConfigurationStatus()
        guard recordingLocationConfigured else {
            showOnboarding()
            fail(RecordingLocationError.notConfigured, retainedAudioURL: nil)
            return
        }
        guard let target = focusTargetProvider() else {
            fail(TextInsertionError.targetUnavailable, retainedAudioURL: nil,
                 message: "Place the cursor in another application before starting dictation.")
            return
        }
        let configuration = effectiveConfiguration(for: target)
        let runtimeSignature = "\(configuration.providerID.rawValue)/\(configuration.transcriptionModel)"
        if let activeTranscriptionRuntimeSignature,
           activeTranscriptionRuntimeSignature != runtimeSignature {
            requireRestartForTranscriptionChange()
            setupMessage = "This app profile uses a different transcription provider or model. Quit & Restart is required before recording."
            return
        }
        activeTranscriptionRuntimeSignature = runtimeSignature
        if configuration.providerID == .openAI, !apiKeyConfigured {
            showOnboarding()
            fail(TranscriptionProviderError.missingAPIKey, retainedAudioURL: nil)
            return
        }
        let availability = providerRegistry.availability(for: configuration.providerID)
        guard availability.isAvailable else {
            fail(
                TranscriptionProviderError.providerUnavailable(
                    reason: availability.reason ?? "The selected transcription provider is unavailable."
                ),
                retainedAudioURL: nil
            )
            return
        }
        if configuration.providerID == .openAI {
            do {
                try NetworkPolicy(
                    mode: configuration.privacyMode,
                    cloudEnhancementEnabled: settings.cloudEnhancementEnabled
                ).requirePermission(for: .transcription)
            } catch {
                fail(error, retainedAudioURL: nil)
                return
            }
        }
        if configuration.providerID == .local, injectedProvider != nil {
            // Test and embedding seam: the supplied provider owns its readiness contract.
        } else if configuration.providerID == .local,
                  case .installed = localModelState {
            // Ready.
        } else if configuration.providerID == .local {
            showOnboarding()
            fail(
                TranscriptionProviderError.localModelMissing(
                    modelID: configuration.transcriptionModel
                ),
                retainedAudioURL: nil
            )
            return
        }
        beginCriticalInteractionActivityIfNeeded()
        do {
            queueSnapshot = try await processingQueue.reserveRecordingSlot()
            hasQueueReservation = true
            if isMixedRequest {
                FlowLogger.meetingSignposter.emitEvent("Meeting Queue Slot Reserved")
            }
        } catch {
            fail(error, retainedAudioURL: nil)
            return
        }
        do {
            if settings.recordingAudioSource == .microphone
                || settings.recordingAudioSource == .mixed {
                try await permissionManager.ensureMicrophoneAccess()
                if isMixedRequest {
                    FlowLogger.meetingSignposter.emitEvent("Meeting Microphone Permission Ready")
                }
            }
            try permissionManager.ensureEventPostingAccess()
            if isMixedRequest {
                FlowLogger.meetingSignposter.emitEvent("Meeting Input Permission Ready")
            }
            sessionConfiguration = configuration
            refreshPermissionStatus()
            if settings.recordingAudioSource == .microphone,
               settings.livePreviewEnabled,
               speechPermissionState == .notDetermined {
                speechPermissionState = await permissionManager.requestSpeechRecognitionAccess()
                refreshLivePreviewAvailability()
            }
            if settings.recordingAudioSource == .mixed {
                FlowLogger.meetingSignposter.emitEvent("Meeting Preflight Passed")
                try await startMixedRecording(
                    target: target,
                    configuration: configuration
                )
                FlowLogger.meetingSignposter.emitEvent("Meeting Recording Visible")
                return
            }
            sessionRecorder = settings.recordingAudioSource == .systemAudio
                ? systemAudioRecorder
                : microphoneRecorder
            if settings.recordingAudioSource == .microphone {
                recorder.selectInputDevice(try audioDeviceService.deviceID(forUID: settings.inputDeviceUID))
            }
            try await startRecorderWithPreview()
            overlayDismissTask?.cancel()
            allowsRecordingDuringCompletionPersistence = false
            focusTarget = target
            lastExternalFocusTarget = target
            state = .recording
            overlay.updateSource(settings.recordingAudioSource)
            overlay.show(status: .recording, reposition: true)
        } catch AudioDeviceServiceError.selectedDeviceUnavailable
            where settings.recordingAudioSource == .microphone {
            settings.inputDeviceUID = nil
            recorder.selectInputDevice(nil)
            do {
                sessionRecorder = microphoneRecorder
                try await startRecorderWithPreview()
                allowsRecordingDuringCompletionPersistence = false
                focusTarget = target
                lastExternalFocusTarget = target
                state = .recording
                overlay.updateSource(.microphone)
                overlay.show(status: .recording, reposition: true)
            }
            catch {
                sessionRecorder = nil
                await releaseQueueReservation()
                fail(error, retainedAudioURL: nil)
            }
        } catch {
            sessionRecorder = nil
            await releaseQueueReservation()
            refreshPermissionStatus()
            fail(error, retainedAudioURL: nil)
        }
    }

    private func startMixedRecording(
        target: FocusTarget,
        configuration: EffectiveDictationConfiguration
    ) async throws {
        let inputDeviceID: AudioDeviceID?
        do {
            inputDeviceID = try audioDeviceService.deviceID(
                forUID: settings.inputDeviceUID
            )
        } catch AudioDeviceServiceError.selectedDeviceUnavailable {
            settings.inputDeviceUID = nil
            inputDeviceID = nil
        }

        let coordinator = mixedRecordingCoordinatorFactory(inputDeviceID)
        resetMixedCaptureLevels()
        await coordinator.setLevelHandler { [weak self] role, level in
            Task { @MainActor [weak self] in
                self?.updateMixedCaptureLevel(level, for: role)
            }
        }
        await coordinator.setWarningHandler { [weak self] warning in
            Task { @MainActor [weak self] in
                self?.handleMixedCaptureWarning(warning)
            }
        }

        do {
            let session = try await coordinator.start(
                MixedRecordingSessionRequest(
                    providerID: configuration.providerID.rawValue,
                    engineID: configuration.engineID,
                    modelID: configuration.transcriptionModel,
                    language: configuration.language.apiValue,
                    privacyMode: configuration.privacyMode,
                    profileID: configuration.profileID
                )
            )
            activeMixedRecordingCoordinator = coordinator
            latestOutputURL = try meetingSessionDirectory(for: session.id)
            do {
                try await meetingHistorySynchronizer.sync(
                    session,
                    targetBundleIdentifier: target.bundleIdentifier,
                    targetApplicationName: target.localizedName
                )
            } catch {
                _ = try? await coordinator.cancel()
                activeMixedRecordingCoordinator = nil
                await coordinator.setLevelHandler(nil)
                await coordinator.setWarningHandler(nil)
                resetMixedCaptureLevels()
                throw error
            }
            overlayDismissTask?.cancel()
            allowsRecordingDuringCompletionPersistence = false
            focusTarget = target
            lastExternalFocusTarget = target
            state = .recording
            overlay.updateSource(.mixed)
            overlay.show(status: .recording, reposition: true)
            await refreshHistory()
        } catch {
            await coordinator.setLevelHandler(nil)
            await coordinator.setWarningHandler(nil)
            throw error
        }
    }

    private func stopMixedRecordingAndProcess() async {
        guard let coordinator = activeMixedRecordingCoordinator,
              let configuration = sessionConfiguration else { return }
        state = .finalizing
        audioLevel = 0
        overlay.show(status: .finalizing)
        let target = focusTarget
        let finalized: MixedRecordingSession
        do {
            finalized = try await coordinator.stop()
            activeMixedRecordingCoordinator = nil
            await coordinator.setLevelHandler(nil)
            await coordinator.setWarningHandler(nil)
            resetMixedCaptureLevels()
            latestOutputURL = try meetingSessionDirectory(for: finalized.id)
            try await meetingHistorySynchronizer.sync(
                finalized,
                targetBundleIdentifier: target?.bundleIdentifier,
                targetApplicationName: target?.localizedName
            )
            await refreshHistory()
        } catch {
            activeMixedRecordingCoordinator = nil
            await coordinator.setLevelHandler(nil)
            await coordinator.setWarningHandler(nil)
            resetMixedCaptureLevels()
            await releaseQueueReservation()
            fail(error, retainedAudioURL: latestOutputURL)
            return
        }

        await releaseQueueReservation()
        guard finalized.status == .queued else {
            fail(
                MixedRecordingError.captureNotAvailable,
                retainedAudioURL: latestOutputURL,
                message: finalized.lastErrorMessage
                    ?? "The mixed recording was preserved, but both tracks are required before automatic processing can continue."
            )
            return
        }

        state = .transcribing
        overlay.show(status: .processing)
        do {
            let completed = try await makeMeetingProcessingWorkflow().run(
                sessionID: finalized.id
            )
            try await meetingHistorySynchronizer.sync(completed)
            await refreshHistory()
            guard completed.status == .completed else {
                latestOutputNotice =
                    "Meeting processing paused. Review the preserved session in History."
                failMessage(
                    completed.lastErrorMessage
                        ?? "Meeting processing paused. Review the preserved session in History.",
                    retainedAudioURL: latestOutputURL
                )
                return
            }
            try await completeMixedTranscriptInsertion(
                session: completed,
                target: target,
                preference: configuration.insertionPreference
            )
            focusTarget = nil
            sessionConfiguration = nil
            endCriticalInteractionActivityIfNeeded()
            if state == .success { state = .idle }
        } catch is CancellationError {
            focusTarget = nil
            sessionConfiguration = nil
            endCriticalInteractionActivityIfNeeded()
            state = .idle
            overlay.hide()
            await refreshHistory()
        } catch {
            if let latest = try? await meetingSessionStore.load(sessionID: finalized.id) {
                _ = try? await meetingHistorySynchronizer.sync(latest)
            }
            await refreshHistory()
            fail(error, retainedAudioURL: latestOutputURL)
        }
    }

    private func cancelMixedRecording(
        using coordinator: any MixedRecordingSessionCoordinating
    ) async {
        state = .finalizing
        audioLevel = 0
        overlay.show(status: .finalizing)
        let target = focusTarget
        do {
            let cancelled = try await coordinator.cancel()
            activeMixedRecordingCoordinator = nil
            await coordinator.setLevelHandler(nil)
            await coordinator.setWarningHandler(nil)
            resetMixedCaptureLevels()
            latestOutputURL = try meetingSessionDirectory(for: cancelled.id)
            try await meetingHistorySynchronizer.sync(
                cancelled,
                targetBundleIdentifier: target?.bundleIdentifier,
                targetApplicationName: target?.localizedName
            )
            focusTarget = nil
            sessionConfiguration = nil
            state = .idle
            overlay.hide()
            await releaseQueueReservation()
            endCriticalInteractionActivityIfNeeded()
            await refreshHistory()
        } catch {
            activeMixedRecordingCoordinator = nil
            await coordinator.setLevelHandler(nil)
            await coordinator.setWarningHandler(nil)
            resetMixedCaptureLevels()
            await releaseQueueReservation()
            fail(error, retainedAudioURL: latestOutputURL)
        }
    }

    private func makeMeetingProcessingWorkflow() -> any MeetingProcessingRunning {
        if let injectedMeetingProcessingWorkflow {
            return injectedMeetingProcessingWorkflow
        }
        let executor = LongFormTrackTranscriptionExecutor { [weak self] request in
            guard let self,
                  let providerID = TranscriptionProviderID(rawValue: request.providerID) else {
                throw TranscriptionProviderError.providerUnavailable(
                    reason: "The frozen meeting transcription provider is unavailable."
                )
            }
            return try await self.activeProvider(
                providerID: providerID,
                model: request.modelID,
                policy: NetworkPolicy(
                    mode: request.privacyMode,
                    cloudEnhancementEnabled: false
                )
            )
        }
        let trackExecutor: any TrackTranscriptionExecuting
#if DEBUG
        if let failingRole = debugNextMeetingTrackFailureRole {
            debugNextMeetingTrackFailureRole = nil
            trackExecutor = DebugOneShotTrackTranscriptionFailureExecutor(
                base: executor,
                failing: failingRole
            )
        } else {
            trackExecutor = executor
        }
#else
        trackExecutor = executor
#endif
        return MeetingProcessingWorkflow(
            sessionStore: meetingSessionStore,
            interruptedCaptureRecovery: InterruptedMeetingCaptureRecovery(
                store: meetingSessionStore
            ),
            trackRunner: TrackTranscriptionRunner(
                store: meetingSessionStore,
                executor: trackExecutor,
                processingQueue: processingQueue
            ),
            mergeRunner: MeetingTranscriptMergeRunner(store: meetingSessionStore),
            historySynchronizer: meetingHistorySynchronizer
        )
    }

    private func completeMixedTranscriptInsertion(
        session: MixedRecordingSession,
        target: FocusTarget?,
        preference: InsertionPreference
    ) async throws {
        let targetIsAvailable = target?.isAvailable == true
        let decision = try await meetingTranscriptInsertionGate.begin(
            sessionID: session.id,
            targetIsAvailable: targetIsAvailable
        )
        try await syncLatestMeetingSessionIfAvailable(sessionID: session.id)
        switch decision {
        case let .authorized(text):
            guard let target else {
                throw TextInsertionError.targetUnavailable
            }
            state = .inserting
            overlay.show(status: .inserting)
            var insertionWasDispatched = false
            do {
                try await makeInserter(preference: preference).insert(text, into: target)
                insertionWasDispatched = true
                try await meetingTranscriptInsertionGate.markCompleted(sessionID: session.id)
                presentSuccessfulInsertion(message: "Meeting transcript inserted")
                allowsRecordingDuringCompletionPersistence = false
            } catch {
                // Once text may have reached another application, keep the
                // durable `attempting` boundary if completion persistence
                // fails. Recovery must require review instead of authorizing a
                // second automatic paste.
                if !insertionWasDispatched {
                    try? await meetingTranscriptInsertionGate.markDeferred(
                        sessionID: session.id
                    )
                }
                throw error
            }
            refreshMeetingHistoryAfterCompletedInsertion(sessionID: session.id)
        case .alreadyCompleted:
            state = .idle
            overlay.hide()
        case .deferred:
            latestOutputNotice = "Meeting transcript is ready in History. Automatic insertion was deferred because the original target is unavailable."
            state = .idle
            overlay.hide()
        case .requiresReview:
            latestOutputNotice = "Meeting transcript insertion needs review in History before it can be repeated."
            state = .idle
            overlay.hide()
        }
    }

    private func syncLatestMeetingSessionIfAvailable(sessionID: UUID) async throws {
        if let latest = try await meetingSessionStore.load(sessionID: sessionID) {
            try await meetingHistorySynchronizer.sync(latest)
        }
    }

    /// The session manifest is the exactly-once authority. History already
    /// contains the completed transcript at this point, so reflecting the
    /// insertion result must not hold the visible `Inserting` state or turn a
    /// successful external paste back into a retryable operation.
    private func refreshMeetingHistoryAfterCompletedInsertion(sessionID: UUID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let started = ContinuousClock.now
            do {
                try await syncLatestMeetingSessionIfAvailable(sessionID: sessionID)
                await refreshHistory()
                FlowLogger.app.info(
                    "Meeting insertion History refresh completed in \(String(describing: started.duration(to: .now)), privacy: .public)"
                )
            } catch {
                FlowLogger.app.error(
                    "Meeting insertion completed, but the deferred History refresh failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func stopAndTranscribe() async {
        state = .finalizing
        audioLevel = 0
        overlay.show(status: .finalizing)
        let recording: AudioRecordingResult
        let stopStarted = ContinuousClock.now
        do {
            recording = try await recorder.stop()
            FlowLogger.audio.info(
                "Recording stop/finalization completed in \(String(describing: stopStarted.duration(to: .now)), privacy: .public)"
            )
        }
        catch {
            sessionRecorder = nil
            await releaseQueueReservation()
            fail(error, retainedAudioURL: nil)
            return
        }
        recorder.previewBufferHandler = nil
        sessionRecorder = nil
        livePreviewCoordinator.finish()
        latestOutputURL = recording.url
        if recording.duration < Self.minimumTranscribableRecordingDuration {
            await rejectTooShortRecording(recording)
            return
        }
        guard let target = focusTarget else {
            await releaseQueueReservation()
            fail(TextInsertionError.targetUnavailable, retainedAudioURL: recording.url)
            return
        }

        var record = makeRecord(from: recording, target: target, status: .recorded)
        do { try await historyStore.upsert(record); await refreshHistory() }
        catch {
            await releaseQueueReservation()
            fail(error, retainedAudioURL: recording.url,
                 message: "The recording was saved, but its history entry could not be created: \(error.localizedDescription)")
            return
        }

        FlowLogger.transcription.info(
            "Post-stop History persistence completed in \(String(describing: stopStarted.duration(to: .now)), privacy: .public)"
        )

        do {
            let job = try await makeJob(record: record)
            FlowLogger.transcription.info(
                "Post-stop job creation completed in \(String(describing: stopStarted.duration(to: .now)), privacy: .public)"
            )
            queueSnapshot = try await processingQueue.commit(job)
            FlowLogger.transcription.info(
                "Post-stop queue commit completed in \(String(describing: stopStarted.duration(to: .now)), privacy: .public)"
            )
            hasQueueReservation = false
            record.jobID = job.id
            record.jobStatus = job.status
            record.queueSequence = job.queueSequence
            record.updatedAt = Date()
            do {
                // The recording and job manifest are durable now. Keep this
                // summary in memory so queue startup does not rewrite the full
                // JSON History a second time before transcription begins.
                try await historyStore.stage(record)
            } catch {
                FlowLogger.app.error(
                    "Queued job summary could not be written to History: \(error.localizedDescription, privacy: .public)"
                )
            }
            inMemoryJobTargets[job.id] = target
            focusTarget = nil
            // The recording is durable, but no text has been inserted yet. Using the
            // success state here made longer local runs look like a stuck "Inserted".
            state = .transcribing
            overlay.show(status: .processing)
            sessionConfiguration = nil
            // Keep the persistent worker sequential, but release the active
            // toggle as soon as insertion feedback has completed. Final History
            // and manifest writes continue in the worker and remain recoverable.
            await withCheckedContinuation { continuation in
                jobInteractionWaiters[job.id] = continuation
                startJobProcessingIfNeeded()
            }
            if state == .success {
                state = .idle
            }
        } catch {
            await releaseQueueReservation()
            fail(error, retainedAudioURL: recording.url)
        }
        Task { [weak self] in await self?.refreshHistory() }
    }

    private func rejectTooShortRecording(_ recording: AudioRecordingResult) async {
        let error = TranscriptionProviderError.audioTooShort(
            minimumDuration: Self.minimumTranscribableRecordingDuration
        )
        let target = focusTarget
        var record = makeRecord(from: recording, target: target, status: .transcriptionFailed)
        record.errorCategory = DictationFailureClassifier.category(for: error)
        record.errorMessage = error.localizedDescription
        record.updatedAt = Date()
        do {
            try await historyStore.upsert(record)
            await refreshHistory()
        } catch {
            FlowLogger.app.error(
                "Too-short recording history entry could not be written: \(error.localizedDescription, privacy: .public)"
            )
        }
        await releaseQueueReservation()
        fail(error, retainedAudioURL: recording.url)
    }

    private func makeJob(record: DictationRecord) async throws -> DictationJob {
        guard let configuration = sessionConfiguration else {
            throw DictationQueueError.reservationMissing
        }
        let executionLocation = configuration.providerID == .local
            ? TranscriptionExecutionLocation.local : .cloud
        let persisted = PersistedDictationConfiguration(
            providerID: configuration.providerID,
            engineID: configuration.engineID,
            modelID: configuration.transcriptionModel,
            executionLocation: executionLocation,
            language: configuration.language.apiValue,
            writingStyleID: configuration.writingStyleID,
            spokenFormattingEnabled: configuration.spokenFormattingEnabled,
            personalDictionaryEnabled: settings.personalDictionaryEnabled,
            insertionPreference: configuration.insertionPreference,
            privacyMode: configuration.privacyMode,
            cloudEnhancementEnabled: settings.cloudEnhancementEnabled,
            enhancementModel: settings.enhancementModel,
            enhancementFallback: settings.smartDictationFallback,
            profileID: configuration.profileID
        )
        let now = Date()
        return DictationJob(
            schemaVersion: DictationJob.currentSchemaVersion,
            id: UUID(),
            recordID: record.id,
            createdAt: now,
            updatedAt: now,
            queueSequence: try await jobStore.nextSequence(),
            audioRelativePath: record.audioRelativePath,
            audioSource: record.audioSource,
            providerID: configuration.providerID.rawValue,
            engineID: configuration.engineID,
            modelID: configuration.transcriptionModel,
            executionLocation: executionLocation,
            language: configuration.language.apiValue,
            targetBundleIdentifier: record.targetBundleIdentifier,
            targetApplicationName: record.targetApplicationName,
            effectiveConfiguration: persisted,
            status: .queued,
            correctionSummary: nil,
            insertionAttemptCount: 0,
            automaticInsertionCompleted: false,
            lastErrorCategory: nil,
            lastErrorMessage: nil
        )
    }

    private func recoverJobQueue() async {
        do {
            _ = try await jobStore.normalizeInterrupted()
            queueSnapshot = try await processingQueue.snapshot()
            startJobProcessingIfNeeded()
        } catch {
            FlowLogger.app.error(
                "Job queue recovery failed: \(error.localizedDescription, privacy: .public)"
            )
            setupMessage = "Some queued dictations need review in History."
        }
    }

    private func releaseQueueReservation() async {
        guard hasQueueReservation else { return }
        do {
            queueSnapshot = try await processingQueue.releaseRecordingSlot()
        } catch {
            FlowLogger.app.error(
                "Queue reservation release failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        hasQueueReservation = false
    }

    private func startJobProcessingIfNeeded() {
        guard jobProcessingTask == nil else { return }
        jobProcessingTask = Task { [weak self] in
            guard let self else { return }
            await self.drainJobQueue()
            // Clear the task before re-reading the queue. A recording can be
            // committed exactly while the previous drain loop is exiting.
            self.jobProcessingTask = nil
            do {
                self.queueSnapshot = try await self.processingQueue.snapshot()
                if self.queueSnapshot.queuedCount > 0 {
                    self.startJobProcessingIfNeeded()
                }
            } catch {
                FlowLogger.app.error(
                    "Could not refresh dictation queue after processing: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func persistCompletedHistoryAndRemoveManifest(jobID: UUID) {
        pendingCompletionPersistenceJobIDs.insert(jobID)
        guard completionPersistenceTask == nil else { return }
        completionPersistenceTask = Task { [weak self] in
            await self?.runCompletionPersistenceLoop()
        }
    }

    private func runCompletionPersistenceLoop() async {
        defer { completionPersistenceTask = nil }
        while !pendingCompletionPersistenceJobIDs.isEmpty {
            let jobIDs = pendingCompletionPersistenceJobIDs
            pendingCompletionPersistenceJobIDs.removeAll()
            let startedAt = Date()
            do {
                // One snapshot covers every completion accumulated while the
                // previous flush was running. This prevents detached full-file
                // writes from building an unbounded serial backlog.
                try await historyStore.flush()
                for jobID in jobIDs {
                    try await jobStore.delete(id: jobID)
                }
                FlowLogger.transcription.info(
                    "Background completion persistence flushed \(jobIDs.count, privacy: .public) job(s) in \(Self.elapsedSeconds(since: startedAt), privacy: .public)s"
                )
            } catch {
                // Keeping an undeleted manifest is intentional: on restart the
                // recording can be recovered conservatively.
                FlowLogger.app.error(
                    "Background completion persistence failed; recovery manifest retained: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func drainJobQueue() async {
        while !Task.isCancelled {
            let job: DictationJob
            let queueReadStarted = ContinuousClock.now
            do {
                guard let next = try await processingQueue.next() else { break }
                job = next
                queueSnapshot = try await processingQueue.snapshot()
                FlowLogger.transcription.info(
                    "Queue next/snapshot completed in \(String(describing: queueReadStarted.duration(to: .now)), privacy: .public)"
                )
            } catch {
                FlowLogger.app.error(
                    "Could not read next dictation job: \(error.localizedDescription, privacy: .public)"
                )
                break
            }

            let completed = await process(job)
            do {
                if completed.status == .completed,
                   stagedCompletionJobIDs.remove(completed.id) != nil {
                    // Release the interactive queue immediately. The manifest
                    // remains in its conservative `inserting` state until the
                    // completed History snapshot is safely on disk.
                    await processingQueue.releaseAfterInsertion(id: completed.id)
                    queueSnapshot.processingCount = 0
                    allowsRecordingDuringCompletionPersistence = false
                    persistCompletedHistoryAndRemoveManifest(jobID: completed.id)
                    FlowLogger.transcription.info(
                        "Job \(job.id, privacy: .public) handed off for background completion persistence"
                    )
                } else {
                    let queueFinishStartedAt = Date()
                    queueSnapshot = try await processingQueue.didFinish(completed)
                    if queueSnapshot.totalActiveCount == 0 {
                        allowsRecordingDuringCompletionPersistence = false
                    }
                    FlowLogger.transcription.info(
                        "Job \(job.id, privacy: .public) queue finalization completed in \(Self.elapsedSeconds(since: queueFinishStartedAt), privacy: .public)s"
                    )
                }
                if completed.status == .cancelled {
                    let manifestDeletionStartedAt = Date()
                    try await jobStore.delete(id: completed.id)
                    FlowLogger.transcription.info(
                        "Job \(job.id, privacy: .public) manifest deletion completed in \(Self.elapsedSeconds(since: manifestDeletionStartedAt), privacy: .public)s"
                    )
                }
            } catch {
                FlowLogger.app.error(
                    "Could not finish dictation job \(job.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                break
            }
            inMemoryJobTargets[job.id] = nil
            let historyRefreshStartedAt = Date()
            await refreshHistory()
            FlowLogger.transcription.info(
                "Job \(job.id, privacy: .public) History refresh completed in \(Self.elapsedSeconds(since: historyRefreshStartedAt), privacy: .public)s"
            )
        }
    }

    private func process(_ input: DictationJob) async -> DictationJob {
        var job = input
        var record: DictationRecord?
        let jobStartedAt = Date()
        FlowLogger.transcription.info(
            "Job \(job.id, privacy: .public) started after waiting \(Self.elapsedSeconds(since: job.createdAt), privacy: .public)s in the queue"
        )
        do {
            let recordLookupStartedAt = Date()
            guard var currentRecord = try await historyStore.record(id: job.recordID) else {
                throw DictationHistoryError.recordNotFound
            }
            record = currentRecord
            let audioURL = try audioURL(for: currentRecord)
            FlowLogger.transcription.info(
                "Job \(job.id, privacy: .public) record lookup and audio resolution completed in \(Self.elapsedSeconds(since: recordLookupStartedAt), privacy: .public)s"
            )

            let statePersistenceStartedAt = Date()
            job.status = .transcribing
            job.updatedAt = Date()
            let jobUpdateStartedAt = Date()
            try await jobStore.update(job)
            FlowLogger.transcription.info(
                "Job \(job.id, privacy: .public) transcribing manifest update completed in \(Self.elapsedSeconds(since: jobUpdateStartedAt), privacy: .public)s"
            )
            if !isRecording {
                let overlayStateStartedAt = Date()
                state = .transcribing
                overlay.show(status: .processing)
                FlowLogger.transcription.info(
                    "Job \(job.id, privacy: .public) transcribing overlay update completed in \(Self.elapsedSeconds(since: overlayStateStartedAt), privacy: .public)s"
                )
            }
            currentRecord.jobID = job.id
            currentRecord.jobStatus = job.status
            currentRecord.queueSequence = job.queueSequence
            currentRecord.updatedAt = Date()
            let historyStageStartedAt = Date()
            try await historyStore.stage(currentRecord)
            FlowLogger.transcription.info(
                "Job \(job.id, privacy: .public) pre-transcription History stage completed in \(Self.elapsedSeconds(since: historyStageStartedAt), privacy: .public)s"
            )
            FlowLogger.transcription.info(
                "Job \(job.id, privacy: .public) pre-transcription state persistence completed in \(Self.elapsedSeconds(since: statePersistenceStartedAt), privacy: .public)s"
            )
            if !isRecording {
                let providerStatus = job.providerID == TranscriptionProviderID.local.rawValue
                    ? "Transcribing on this Mac…" : "Waiting for OpenAI…"
                overlay.show(status: .longForm(providerStatus))
            }
            let providerResolutionStartedAt = Date()
            let provider = try await activeProvider(
                providerID: TranscriptionProviderID(rawValue: job.providerID),
                model: job.modelID,
                policy: NetworkPolicy(
                    mode: job.effectiveConfiguration.privacyMode,
                    cloudEnhancementEnabled: job.effectiveConfiguration.cloudEnhancementEnabled
                )
            )
            FlowLogger.transcription.info(
                "Job \(job.id, privacy: .public) provider resolution completed in \(Self.elapsedSeconds(since: providerResolutionStartedAt), privacy: .public)s"
            )
            let transcriptionStartedAt = Date()
            currentRecord = try await transcriptionRunner.run(
                record: currentRecord,
                audioURL: audioURL,
                language: job.language,
                maximumAttempts: settings.automaticRetryEnabled ? 3 : 1,
                provider: provider,
                deferSuccessfulPersistence: true,
                progress: { [weak self] progress in
                    guard let self, !self.isRecording else { return }
                    self.overlay.show(status: .longForm(progress.statusText))
                }
            )
            FlowLogger.transcription.info(
                "Job \(job.id, privacy: .public) transcription stage completed in \(Self.elapsedSeconds(since: transcriptionStartedAt), privacy: .public)s using \(job.providerID, privacy: .public)/\(job.modelID, privacy: .public)"
            )
            record = currentRecord

            let correctionStartedAt = Date()
            job.status = .correcting
            job.updatedAt = Date()
            try await jobStore.update(job)
            let correctionResult = InlineCorrectionProcessor().process(
                currentRecord.originalTranscript ?? "",
                language: currentRecord.language,
                protectedTerms: job.effectiveConfiguration.personalDictionaryEnabled
                    ? configurationDictionaryTerms(for: currentRecord.language) : []
            )
            currentRecord.correctedTranscript = correctionResult.text
            currentRecord.correctionSummary = correctionResult.summary
            currentRecord.jobStatus = job.status
            currentRecord.updatedAt = Date()
            job.correctionSummary = correctionResult.summary
            try await historyStore.stage(currentRecord)
            try await jobStore.update(job)
            FlowLogger.transcription.info(
                "Job \(job.id, privacy: .public) local correction stage completed in \(Self.elapsedSeconds(since: correctionStartedAt), privacy: .public)s"
            )
            record = currentRecord

            job.status = .formatting
            job.updatedAt = Date()
            try await jobStore.update(job)
            currentRecord.jobStatus = job.status
            let configuration = job.effectiveConfiguration
            let style = writingStyles.first {
                $0.id == configuration.writingStyleID && $0.isEnabled
            } ?? BuiltInWritingStyles.all[0]
            let enhancementPolicy = NetworkPolicy(
                mode: configuration.privacyMode,
                cloudEnhancementEnabled: configuration.cloudEnhancementEnabled
            )
            let enhancementAllowed = enhancementPolicy.allows(.enhancement)
            if !isRecording, style.usesAI, enhancementAllowed {
                state = .enhancing
                overlay.show(status: .longForm("Improving text…"))
            }
            let formattingStartedAt = Date()
            currentRecord = try await smartDictationPipeline.run(
                record: currentRecord,
                spokenFormattingEnabled: configuration.spokenFormattingEnabled,
                dictionaryEntries: configuration.personalDictionaryEnabled ? dictionaryEntries : [],
                style: style,
                enhancementModel: configuration.enhancementModel,
                fallback: configuration.enhancementFallback,
                enhancer: style.usesAI && enhancementAllowed
                    ? try activeEnhancer(policy: enhancementPolicy) : nil,
                enhancementAllowed: enhancementAllowed,
                deferSuccessfulPersistence: true
            )
            FlowLogger.transcription.info(
                "Job \(job.id, privacy: .public) writing-style stage completed in \(Self.elapsedSeconds(since: formattingStartedAt), privacy: .public)s; style=\(style.name, privacy: .public), AI=\(style.usesAI, privacy: .public)"
            )
            record = currentRecord

            let outputText = currentRecord.finalText ?? currentRecord.originalTranscript ?? ""
            guard !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranscriptionProviderError.emptyTranscript
            }
            job.status = .readyToInsert
            job.updatedAt = Date()
            try await jobStore.update(job)

            guard let target = inMemoryJobTargets[job.id], target.isAvailable else {
                _ = copyToClipboard(outputText)
                currentRecord.status = .insertionUnknown
                currentRecord.jobStatus = .insertionDeferred
                currentRecord.errorCategory = .interrupted
                currentRecord.errorMessage = "Automatic insertion was deferred because the original target is no longer safely available."
                currentRecord.updatedAt = Date()
                try await historyStore.upsert(currentRecord)
                job.status = .insertionDeferred
                job.lastErrorCategory = .interrupted
                job.lastErrorMessage = currentRecord.errorMessage
                job.updatedAt = Date()
                signalJobInteractionCompleted(job.id)
                return job
            }

            job.status = .inserting
            job.insertionAttemptCount += 1
            job.updatedAt = Date()
            try await jobStore.update(job)
            currentRecord.status = .inserting
            currentRecord.jobStatus = .inserting
            currentRecord.updatedAt = Date()
            try await historyStore.stage(currentRecord)
            if !isRecording {
                overlay.show(status: .inserting)
            }
            let insertionStartedAt = Date()
            try await makeInserter(
                preference: job.effectiveConfiguration.insertionPreference
            ).insert(outputText, into: target)
            FlowLogger.insertion.info(
                "Job \(job.id, privacy: .public) insertion stage completed in \(Self.elapsedSeconds(since: insertionStartedAt), privacy: .public)s"
            )

            job.automaticInsertionCompleted = true
            job.status = .completed
            job.lastErrorCategory = nil
            job.lastErrorMessage = nil
            job.updatedAt = Date()
            currentRecord.status = .completed
            currentRecord.jobStatus = .completed
            currentRecord.errorCategory = nil
            currentRecord.errorMessage = nil
            currentRecord.updatedAt = Date()

            if currentRecord.audioSource == .systemAudio {
                _ = copyToClipboard(outputText)
                latestOutputNotice = "System Audio transcript copied to the clipboard."
            }
            // The paste has already completed at this point. Complete the visible
            // UI lifecycle before starting durable persistence. In practice, a
            // slow atomic History write can delay Main Actor timers even when the
            // write itself runs on a background queue.
            if !isRecording {
                let message = currentRecord.audioSource == .systemAudio
                    ? "Text inserted · copied to clipboard" : "Text inserted"
                presentSuccessfulInsertion(message: message)
            }
            signalJobInteractionCompleted(job.id)
            // The completed state is immediately visible in the actor-backed
            // History. The disk flush is handed off after the active queue slot
            // has been released, so slow JSON or filesystem work cannot retain
            // the hotkey transition or the success overlay.
            try await historyStore.stage(currentRecord)
            stagedCompletionJobIDs.insert(job.id)
            FlowLogger.transcription.info(
                "Job \(job.id, privacy: .public) interaction completed in \(Self.elapsedSeconds(since: jobStartedAt), privacy: .public)s"
            )
            return job
        } catch let failure as TranscriptionRunFailure {
            record = failure.record
            job.lastErrorCategory = DictationFailureClassifier.category(for: failure.underlyingError)
            job.lastErrorMessage = failure.underlyingError.localizedDescription
        } catch let failure as TranscriptionPersistenceFailure {
            record = failure.record
            job.lastErrorCategory = .sessionPersistence
            job.lastErrorMessage = failure.localizedDescription
        } catch let failure as SmartDictationRunFailure {
            record = failure.record
            job.lastErrorCategory = DictationFailureClassifier.category(for: failure.underlyingError)
            job.lastErrorMessage = failure.underlyingError.localizedDescription
        } catch {
            job.lastErrorCategory = DictationFailureClassifier.category(for: error)
            job.lastErrorMessage = error.localizedDescription
        }

        job.status = .failed
        job.updatedAt = Date()
        if var failedRecord = record {
            failedRecord.jobID = job.id
            failedRecord.jobStatus = .failed
            failedRecord.queueSequence = job.queueSequence
            failedRecord.errorCategory = job.lastErrorCategory
            failedRecord.errorMessage = job.lastErrorMessage
            failedRecord.updatedAt = job.updatedAt
            try? await historyStore.upsert(failedRecord)
            record = failedRecord
        }
        if let record, let url = try? audioURL(for: record) {
            copySystemAudioTranscriptForRecovery(record, recordingURL: url)
        }
        if !isRecording {
            let message = job.lastErrorMessage ?? "Dictation processing failed"
            let retainedURL = record.flatMap { try? audioURL(for: $0) }
            latestOutputNotice = "A queued dictation needs attention in History: \(message)"
            // A transcription failure is terminal for this job. Leaving the
            // coordinator in `.transcribing` kept source/profile controls locked
            // after silent microphone or System Audio recordings.
            state = .failed(message: message, retainedAudioURL: retainedURL)
            overlay.show(status: .error(message))
            scheduleOverlayDismiss(after: .seconds(3), transitionToIdle: false)
        }
        signalJobInteractionCompleted(job.id)
        return job
    }

    nonisolated private static func elapsedSeconds(since date: Date) -> String {
        String(format: "%.3f", max(0, Date().timeIntervalSince(date)))
    }

    private func configurationDictionaryTerms(for language: String?) -> [String] {
        dictionaryEntries
            .filter { entry in
                entry.isEnabled && (entry.language == nil || language == nil || entry.language == language)
            }
            .flatMap { [$0.spokenForm, $0.replacement] }
    }

    private func insertStoredText(_ text: String, record: DictationRecord, target: FocusTarget) async {
        var updated = record
        do {
            state = .inserting
            overlay.show(status: .inserting)
            updated.status = .inserting; updated.updatedAt = Date(); try await historyStore.upsert(updated)
            try await makeInserter().insert(text, into: target)
            state = .success
            overlay.show(status: .success(message: "Text inserted"))
            scheduleOverlayDismiss(after: .milliseconds(600), transitionToIdle: true)

            updated.status = .completed; updated.errorCategory = nil; updated.errorMessage = nil; updated.updatedAt = Date()
            do {
                try await historyStore.upsert(updated)
            } catch {
                setupMessage = "Text was inserted, but the completed History status could not be saved."
                FlowLogger.app.error(
                    "Post-insertion History update failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        } catch {
            updated.status = .insertionFailed; updated.errorCategory = .insertion
            updated.errorMessage = error.localizedDescription; updated.updatedAt = Date()
            await persistBestEffort(updated, context: "insertion failure")
            fail(error, retainedAudioURL: try? audioURL(for: record))
        }
        await refreshHistory()
    }

    private func makeRecord(from recording: AudioRecordingResult, target: FocusTarget?, status: DictationRecordStatus) -> DictationRecord {
        let attributes = try? FileManager.default.attributesOfItem(atPath: recording.url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let now = Date()
        return .newRecording(
            id: recording.id,
            startedAt: recording.startedAt,
            endedAt: now,
            duration: recording.duration,
            status: status,
            audioRelativePath: (try? audioStore.relativePath(for: recording.url)) ?? recording.url.path,
            audioFileSize: size,
            providerID: sessionConfiguration?.providerID.rawValue
                ?? settings.transcriptionProviderID.rawValue,
            modelID: sessionConfiguration?.transcriptionModel ?? settings.transcriptionModel,
            language: (sessionConfiguration?.language ?? settings.transcriptionLanguage).apiValue,
            targetBundleIdentifier: target?.bundleIdentifier,
            targetApplicationName: target?.localizedName,
            sourceMetadata: recording.sourceMetadata
        )
        .withSmartConfiguration(
            writingStyleID: sessionConfiguration?.writingStyleID ?? settings.writingStyleID,
            spokenFormattingEnabled: sessionConfiguration?.spokenFormattingEnabled
                ?? settings.spokenFormattingEnabled
        )
    }

    private func persistBestEffort(_ record: DictationRecord, context: String) async {
        do {
            try await historyStore.upsert(record)
        } catch {
            FlowLogger.app.error(
                "Could not persist \(context, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func audioURL(for record: DictationRecord) throws -> URL {
        record.audioRelativePath.hasPrefix("/")
            ? URL(fileURLWithPath: record.audioRelativePath)
            : try audioStore.url(forRelativePath: record.audioRelativePath)
    }
    private func makeInserter(preference: InsertionPreference? = nil) -> TextInserting {
        if let injectedInserter { return injectedInserter }
        pasteboardInserter.updateRestoreDelay(
            .milliseconds(Int(settings.clipboardRestoreDelay * 1_000))
        )
        let resolvedPreference = preference ?? sessionConfiguration?.insertionPreference ?? .automatic
        if !resolvedPreference.attemptsDirectAccessibility {
            return pasteboardInserter
        }
        return FallbackTextInserter(
            direct: AccessibilityTextInserter(),
            clipboard: pasteboardInserter
        )
    }

    private func prepareLivePreview() {
        recorder.previewBufferHandler = nil
        livePreviewCoordinator.cancel()
        didLogLivePreviewText = false
        overlay.configure(size: settings.overlaySize, position: settings.overlayPosition)
        startLivePreviewIfAvailable(size: settings.overlaySize)
    }

    private func startLivePreviewIfAvailable(size: OverlaySize) {
        if settings.recordingAudioSource == .systemAudio {
            overlay.updatePreview(.unavailable(RecordingAudioSource.systemAudioPreviewGuidance))
            FlowLogger.audio.info("Live Preview skipped for System Audio")
            return
        }
        FlowLogger.audio.info(
            "Preparing Live Preview: enabled=\(self.settings.livePreviewEnabled, privacy: .public), speechPermission=\(self.speechPermissionState.rawValue, privacy: .public)"
        )
        guard size.showsLivePreviewText else {
            overlay.updatePreview(.disabled)
            FlowLogger.audio.info("Live Preview skipped for Compact overlay")
            return
        }
        guard settings.livePreviewEnabled else {
            overlay.updatePreview(.disabled)
            FlowLogger.audio.info("Live Preview is disabled in Settings")
            return
        }
        let availability = livePreviewAvailability
        FlowLogger.audio.info(
            "Live Preview availability: \(availability.statusText, privacy: .public)"
        )
        guard case let .available(localeIdentifier) = availability else {
            overlay.updatePreview(.unavailable(availability.statusText))
            FlowLogger.audio.notice(
                "Live Preview was not started: \(availability.statusText, privacy: .public)"
            )
            return
        }
        FlowLogger.audio.info(
            "Starting local Live Preview with locale \(localeIdentifier, privacy: .public)"
        )
        do {
            recorder.previewBufferHandler = try livePreviewCoordinator.start(
                configuration: LivePreviewConfiguration(
                    localeIdentifier: localeIdentifier,
                    characterLimit: size.clampedLivePreviewCharacterLimit(settings.livePreviewCharacterLimit)
                )
            )
        } catch {
            recorder.previewBufferHandler = nil
            FlowLogger.audio.notice(
                "Live Preview could not start: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func startRecorderWithPreview() async throws {
        do {
            try await recorder.start()
            // Attach Speech only after the audio engine is stable. Starting the
            // recognizer first can race Core Audio device initialization.
            prepareLivePreview()
        } catch {
            recorder.previewBufferHandler = nil
            livePreviewCoordinator.cancel()
            throw error
        }
    }

    private func insertionTarget(for record: DictationRecord) -> FocusTarget? {
        if let current = focusTargetProvider() {
            lastExternalFocusTarget = current
            return current
        }
        if let recordedApplication = FocusTarget.capture(
            bundleIdentifier: record.targetBundleIdentifier
        ) {
            lastExternalFocusTarget = recordedApplication
            return recordedApplication
        }
        if let lastExternalFocusTarget, lastExternalFocusTarget.isAvailable {
            return lastExternalFocusTarget
        }
        return nil
    }
    private func activeProvider(
        providerID preferredProviderID: TranscriptionProviderID? = nil,
        model preferredModel: String? = nil,
        policy preferredPolicy: NetworkPolicy? = nil
    ) async throws -> any TranscriptionProvider {
        if let injectedProvider { return injectedProvider }
        let providerID = preferredProviderID ?? settings.transcriptionProviderID
        let policy = preferredPolicy ?? NetworkPolicy(
            mode: settings.privacyMode,
            cloudEnhancementEnabled: settings.cloudEnhancementEnabled
        )
        if providerID == .local {
            let availability = providerRegistry.availability(for: .local)
            guard availability.isAvailable else {
                throw TranscriptionProviderError.providerUnavailable(
                    reason: availability.reason ?? "Local transcription is unavailable."
                )
            }
            guard case .installed = await localModelManager.refreshState() else {
                throw TranscriptionProviderError.localModelMissing(
                    modelID: preferredModel ?? settings.localTranscriptionModelID
                )
            }
            if let cachedLocalProvider { return cachedLocalProvider }
            let provider = FluidAudioTranscriptionProvider(
                modelDirectory: await localModelManager.activeDirectory,
                modelID: preferredModel ?? settings.localTranscriptionModelID
            )
            cachedLocalProvider = provider
            return provider
        }
        try policy.requirePermission(for: .transcription)
        let environmentKey = environment["OPENAI_API_KEY"]
        let keychainKey = environmentKey?.isEmpty == false ? nil : try keychainAPIKey()
        guard let key = [environmentKey, keychainKey].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw TranscriptionProviderError.missingAPIKey
        }
        let configured = (preferredModel ?? settings.transcriptionModel)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = environment["FLOWDICTATE_TRANSCRIPTION_MODEL"]?.isEmpty == false
            ? environment["FLOWDICTATE_TRANSCRIPTION_MODEL"]! : (configured.isEmpty ? "gpt-4o-mini-transcribe" : configured)
        if let cachedOpenAIProvider, cachedOpenAIProviderModel == model {
            return cachedOpenAIProvider
        }
        let provider = OpenAITranscriptionProvider(apiKey: key, model: model)
        cachedOpenAIProvider = provider
        cachedOpenAIProviderModel = model
        return provider
    }

    private func invalidateCachedOpenAIRuntime() {
        cachedOpenAIProvider = nil
        cachedOpenAIProviderModel = nil
        cachedOpenAIEnhancer = nil
    }

    private var selectedWritingStyle: WritingStyleProfile {
        writingStyles.first { $0.id == settings.writingStyleID && $0.isEnabled }
            ?? BuiltInWritingStyles.all[0]
    }

    private func effectiveConfiguration(for target: FocusTarget) -> EffectiveDictationConfiguration {
        let profile = appProfiles.first {
            $0.isEnabled && $0.bundleIdentifier == target.bundleIdentifier
        }
        return EffectiveDictationConfiguration(
            providerID: profile?.transcriptionProviderID ?? settings.transcriptionProviderID,
            engineID: (profile?.transcriptionProviderID ?? settings.transcriptionProviderID) == .local
                ? TranscriptionProviderRegistry.local.capabilities.engineID
                : TranscriptionProviderRegistry.openAI.capabilities.engineID,
            language: profile?.language ?? settings.transcriptionLanguage,
            transcriptionModel: profile?.transcriptionModel?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? ((profile?.transcriptionProviderID ?? settings.transcriptionProviderID) == .local
                    ? settings.localTranscriptionModelID : settings.transcriptionModel),
            privacyMode: settings.privacyMode,
            writingStyleID: profile?.writingStyleID ?? settings.writingStyleID,
            spokenFormattingEnabled: profile?.spokenFormattingEnabled
                ?? settings.spokenFormattingEnabled,
            insertionPreference: profile?.insertionPreference ?? .automatic,
            profileID: profile?.id
        )
    }

    private func activeEnhancer(policy: NetworkPolicy? = nil) throws -> any TranscriptEnhancing {
        if let injectedEnhancer { return injectedEnhancer }
        try (policy ?? NetworkPolicy(
            mode: settings.privacyMode,
            cloudEnhancementEnabled: settings.cloudEnhancementEnabled
        )).requirePermission(for: .enhancement)
        let environmentKey = environment["OPENAI_API_KEY"]
        let keychainKey = environmentKey?.isEmpty == false ? nil : try keychainAPIKey()
        guard let key = [environmentKey, keychainKey].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw TranscriptionProviderError.missingAPIKey
        }
        if let cachedOpenAIEnhancer { return cachedOpenAIEnhancer }
        let enhancer = transcriptEnhancerFactory(key)
        cachedOpenAIEnhancer = enhancer
        return enhancer
    }

    private func chooseSmartDictationExport(
        filename: String,
        action: @escaping @MainActor (URL) async throws -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await action(url); setupMessage = "Export completed." }
            catch { setupMessage = error.localizedDescription }
        }
    }

    private func chooseSmartDictationImport(
        action: @escaping @MainActor (URL) async throws -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await action(url)
                await refreshSmartDictationData()
                setupMessage = "Import completed."
            } catch { setupMessage = error.localizedDescription }
        }
    }

    private func keychainAPIKey() throws -> String? {
        if didLoadAPIKeyFromKeychain { return cachedAPIKey }
        let value = try credentialStore.readAPIKey()
        cachedAPIKey = value
        didLoadAPIKeyFromKeychain = true
        return value
    }

    @discardableResult
    private func copyToClipboard(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    private func copySystemAudioTranscriptForRecovery(
        _ record: DictationRecord,
        recordingURL: URL
    ) {
        guard record.audioSource == .systemAudio,
              let text = record.finalText
                ?? record.dictionaryTranscript
                ?? record.formattedTranscript
                ?? record.originalTranscript else { return }
        let copied = copyToClipboard(text)
        latestOutputURL = recordingURL
        latestOutputNotice = copied
            ? "System Audio transcript copied to the clipboard."
            : "System Audio transcript is available in History."
    }

    private func fail(_ error: Error, retainedAudioURL: URL?, message: String? = nil) {
        var resolvedMessage = message ?? error.localizedDescription
        if let retainedAudioURL, !resolvedMessage.contains(retainedAudioURL.path) {
            resolvedMessage += " Recording saved at \(retainedAudioURL.path)."
        }
        failMessage(resolvedMessage, retainedAudioURL: retainedAudioURL)
    }
    private func failMessage(_ message: String, retainedAudioURL: URL? = nil) {
        recorder.previewBufferHandler = nil
        livePreviewCoordinator.cancel()
        state = .failed(message: message, retainedAudioURL: retainedAudioURL)
        focusTarget = nil; audioLevel = 0
        sessionRecorder = nil
        sessionConfiguration = nil
        endCriticalInteractionActivityIfNeeded()
        overlay.show(status: .error(message))
        scheduleOverlayDismiss(after: .seconds(3), transitionToIdle: false)
        FlowLogger.app.error("Dictation failed: \(message, privacy: .public)")
    }
    private func scheduleOverlayDismiss(after duration: Duration, transitionToIdle: Bool) {
        overlayDismissTask?.cancel()
        overlayDismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            overlay.hide()
            if transitionToIdle, state == .success { state = .idle }
        }
    }

    /// Presents confirmation without making job completion wait for a UI timer.
    /// This keeps a delayed Main Actor wake-up from holding the next dictation.
    private func presentSuccessfulInsertion(message: String) {
        state = .success
        overlay.show(status: .success(message: message))
        // The completed job still owns its durable manifest until History has
        // finished writing. A new recording may nevertheless reserve the next
        // queue slot; it cannot begin processing until this job leaves the drain.
        allowsRecordingDuringCompletionPersistence = true
        scheduleOverlayDismiss(after: .milliseconds(350), transitionToIdle: true)
        FlowLogger.app.notice("Inserted interaction released; overlay dismissal scheduled independently")
    }

    private func signalJobInteractionCompleted(_ jobID: UUID) {
        endCriticalInteractionActivityIfNeeded()
        if let continuation = jobInteractionWaiters.removeValue(forKey: jobID) {
            continuation.resume()
        } else if state == .success {
            // Recovered jobs have no foreground stop task waiting to perform the
            // final state transition.
            state = .idle
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
