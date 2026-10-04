import AppKit
import SwiftUI

struct FlowDictateMenu: View {
    @ObservedObject var coordinator: DictationCoordinator

    var body: some View {
        Text(coordinator.state.title)

        if coordinator.queueSnapshot.processingCount > 0 || coordinator.queueSnapshot.queuedCount > 0 {
            Text("\(coordinator.queueSnapshot.processingCount) processing · \(coordinator.queueSnapshot.queuedCount) queued")
                .foregroundStyle(.secondary)
        }

        Button(coordinator.primaryActionTitle) {
            coordinator.requestToggle()
        }
        .disabled(
            !coordinator.canPerformPrimaryAction
        )

        Button("Cancel Dictation") {
            coordinator.requestCancel()
        }
        .disabled(!coordinator.canCancel)

        Button("Restore Last Dictation") {
            coordinator.restoreLastDictation()
        }

        Button("History…") {
            coordinator.showHistory()
        }

        if let notice = coordinator.latestOutputNotice {
            Text(notice)
            if let outputURL = coordinator.latestOutputURL {
                Text("Saved at: \(outputURL.path)")
                Button("Show Saved Recording in Finder") {
                    coordinator.revealLatestOutput()
                }
            }
        }

        if let failedRecord = coordinator.latestEnhancementFailure {
            Menu("Smart Dictation Needs Attention") {
                Button("Retry Enhancement") {
                    coordinator.retryEnhancement(failedRecord)
                }
                .disabled(coordinator.retryingEnhancementRecordIDs.contains(failedRecord.id))

                Button("Insert Locally Processed Text") {
                    coordinator.insertLocallyProcessedText(failedRecord)
                }

                Button("Insert Original Transcript") {
                    coordinator.insertOriginalText(failedRecord)
                }

                Divider()
                Button("Review in History…") {
                    coordinator.showHistory()
                }
            }
        }

        Divider()

        Menu("Recording Source") {
            ForEach(RecordingAudioSource.allCases) { source in
                Button {
                    coordinator.selectRecordingAudioSource(source)
                } label: {
                    selectionLabel(
                        source.title,
                        selected: coordinator.settings.recordingAudioSource == source
                    )
                }
            }
        }
        .disabled(
            coordinator.isRecording
                || coordinator.isProcessing
                || coordinator.isSystemAudioTestRunning
                || coordinator.isCoreAudioTapProbeRunning
                || coordinator.isMixedCaptureTestRunning
        )

        Menu("Microphone") {
            Button {
                coordinator.selectInputDevice(uid: nil)
            } label: {
                selectionLabel("System Default", selected: coordinator.settings.inputDeviceUID == nil)
            }

            ForEach(coordinator.inputDevices) { device in
                Button {
                    coordinator.selectInputDevice(uid: device.uid)
                } label: {
                    selectionLabel(
                        device.name + (device.isDefault ? " (Default)" : ""),
                        selected: coordinator.settings.inputDeviceUID == device.uid
                    )
                }
            }

            Divider()
            Button("Refresh Devices") {
                coordinator.refreshInputDevices()
            }
        }
        .disabled(
            coordinator.isRecording
                || coordinator.isMixedCaptureTestRunning
        )

        if case .failed(_, let retainedAudioURL?) = coordinator.state {
            Button("Show Saved Recording in Finder") {
                coordinator.revealRetainedAudio()
            }
            .help(retainedAudioURL.path)
        }

        SettingsLink {
            Text("Settings…")
        }

        if coordinator.needsOnboarding {
            Button("Continue Setup…") {
                coordinator.showOnboarding()
            }
        }

        Divider()

        Button("Quit NativeDictate") {
            NSApplication.shared.terminate(nil)
        }

        Button("Quit & Restart NativeDictate") {
            coordinator.quitAndRestart()
        }
        .disabled(coordinator.isRecording || coordinator.isProcessing)
    }

    @ViewBuilder
    private func selectionLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

struct FlowDictateSettingsView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @ObservedObject private var settings: AppSettings
    @ObservedObject private var launchAtLogin: LaunchAtLoginManager
    @State private var apiKey = ""
    @State private var systemAudioProbeDuration = SystemAudioProbeDuration.fiveMinutes

    init(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        _settings = ObservedObject(wrappedValue: coordinator.settings)
        _launchAtLogin = ObservedObject(wrappedValue: coordinator.launchAtLogin)
    }

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gear") }
            dictationSettings
                .tabItem { Label("Dictation", systemImage: "keyboard") }
            audioSettings
                .tabItem { Label("Audio", systemImage: "mic") }
            transcriptionSettings
                .tabItem { Label("Transcription", systemImage: "text.bubble") }
            SmartDictationSettingsView(coordinator: coordinator)
                .tabItem { Label("Smart Dictation", systemImage: "sparkles") }
            AppProfilesSettingsView(coordinator: coordinator)
                .tabItem { Label("App Profiles", systemImage: "square.stack.3d.up") }
            ProductivitySettingsView(coordinator: coordinator)
                .tabItem { Label("Productivity", systemImage: "chart.bar") }
            storageSettings
                .tabItem { Label("Storage", systemImage: "externaldrive") }
            advancedSettings
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 720, height: 560)
        .onAppear {
            if coordinator.isRecording {
                coordinator.restoreRecordingOverlayAfterSettingsActivation()
                return
            }
            coordinator.refreshInputDevices()
            coordinator.refreshConfigurationStatus()
            coordinator.refreshPermissionStatus()
            launchAtLogin.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            if coordinator.isRecording {
                coordinator.restoreRecordingOverlayAfterSettingsActivation()
                return
            }
            coordinator.refreshPermissionStatus()
            coordinator.refreshInputDevices()
            launchAtLogin.refresh()
        }
    }

    private var generalSettings: some View {
        settingsForm {
            Section("Startup") {
                Toggle(
                    "Launch NativeDictate at login",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                if let message = launchAtLogin.errorMessage {
                    Text(message).foregroundStyle(.red).font(.caption)
                }
                if let message = launchAtLogin.statusMessage {
                    Text(message).foregroundStyle(.secondary).font(.caption)
                    Button("Open Login Items Settings") {
                        launchAtLogin.openLoginItemsSettings()
                    }
                }
            }

            Section("Permissions") {
                permissionRow(
                    "Microphone",
                    granted: coordinator.microphonePermissionGranted,
                    action: coordinator.openMicrophoneSettings
                )
                permissionRow(
                    "Accessibility",
                    granted: coordinator.accessibilityPermissionGranted,
                    action: coordinator.openAccessibilitySettings
                )
                speechRecognitionPermissionRow
            }

            Section("Setup") {
                Button("Open Setup Assistant…") {
                    coordinator.showOnboarding()
                }
                Button("Open Dictation History…") {
                    coordinator.showHistory()
                }
            }

            Section("Restart") {
                restartControls(
                    "Changing the transcription provider, privacy mode or recognition model requires a restart. Settings, History and recordings are retained."
                )
            }
        }
    }

    private var dictationSettings: some View {
        settingsForm {
            Section("Keyboard Shortcuts") {
                Picker("Activation mode", selection: $settings.dictationActivationMode) {
                    ForEach(DictationActivationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                ShortcutRecorderView(
                    title: "Start / Stop",
                    configuration: settings.dictationHotKey,
                    onChange: coordinator.setDictationHotKey
                )
                ShortcutRecorderView(
                    title: "Cancel",
                    configuration: settings.cancelHotKey,
                    onChange: coordinator.setCancelHotKey
                )
                ShortcutRecorderView(
                    title: "Restore Last",
                    configuration: settings.restoreHotKey,
                    onChange: coordinator.setRestoreHotKey
                )
                Text("Click a shortcut, then press a key combination. Escape cancels recording the shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Live Preview") {
                Toggle("Show Live Preview", isOn: $settings.livePreviewEnabled)
                Text(coordinator.livePreviewAvailability.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.livePreviewEnabled
                    && coordinator.speechPermissionState == .notDetermined {
                    Button("Allow Speech Recognition…") {
                        coordinator.requestSpeechRecognitionPermission()
                    }
                } else if settings.livePreviewEnabled
                    && coordinator.speechPermissionState != .authorized {
                    Button("Open Speech Recognition Settings") {
                        coordinator.openSpeechRecognitionSettings()
                    }
                }
                if settings.livePreviewEnabled,
                   coordinator.speechPermissionState == .authorized,
                   case .unavailable = coordinator.livePreviewAvailability {
                    Button("Open Keyboard & Dictation Settings") {
                        coordinator.openKeyboardSettings()
                    }
                }

                Picker("Overlay size", selection: $settings.overlaySize) {
                    ForEach(OverlaySize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                Picker("Overlay position", selection: $settings.overlayPosition) {
                    ForEach(OverlayPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                if let previewCharacterRange = settings.overlaySize.livePreviewCharacterRange {
                    HStack {
                        Text("Max preview characters")
                        Slider(
                            value: Binding(
                                get: {
                                    Double(settings.overlaySize.clampedLivePreviewCharacterLimit(settings.livePreviewCharacterLimit))
                                },
                                set: { settings.livePreviewCharacterLimit = Int($0.rounded()) }
                            ),
                            in: Double(previewCharacterRange.lowerBound)...Double(previewCharacterRange.upperBound),
                            step: 25
                        )
                        Text("\(settings.overlaySize.clampedLivePreviewCharacterLimit(settings.livePreviewCharacterLimit))")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                    Text("Limits the live transcript shown in the overlay. Standard allows up to 200 and Expanded up to 800 characters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Compact overlay does not show Live Preview text, so no Preview character limit is needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Test Preview for 5 Seconds…") {
                    coordinator.testLivePreview()
                }
                .disabled(
                    !settings.livePreviewEnabled
                        || coordinator.isPreviewTestRunning
                        || coordinator.isProcessing
                )
            }
        }
    }

    private var audioSettings: some View {
        settingsForm {
            Section("Recording Source") {
                Picker(
                    "Source",
                    selection: Binding(
                        get: { settings.recordingAudioSource },
                        set: { coordinator.selectRecordingAudioSource($0) }
                    )
                ) {
                    Text(RecordingAudioSource.microphone.title).tag(RecordingAudioSource.microphone)
                    Text(RecordingAudioSource.systemAudio.title).tag(RecordingAudioSource.systemAudio)
                    Text(RecordingAudioSource.mixed.title).tag(RecordingAudioSource.mixed)
                }
                .disabled(
                    coordinator.isRecording
                        || coordinator.isProcessing
                        || coordinator.isSystemAudioTestRunning
                        || coordinator.isCoreAudioTapProbeRunning
                        || coordinator.isMixedCaptureTestRunning
                )

                Text(settings.recordingAudioSource.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.recordingAudioSource != .microphone {
                    HStack {
                        Label(
                            coordinator.systemAudioPermissionStatus.readiness.title,
                            systemImage: coordinator.systemAudioPermissionStatus.readiness.symbolName
                        )
                        .foregroundStyle(
                            coordinator.systemAudioPermissionStatus.readiness == .authorized
                                ? Color.green
                                : coordinator.systemAudioPermissionStatus.readiness == .requestRequired
                                    ? Color.orange
                                    : Color.secondary
                        )
                        Spacer()
                        if coordinator.systemAudioPermissionStatus.backend == .screenCaptureKit {
                            Button("Check Again") { coordinator.refreshPermissionStatuses() }
                        }
                        Button("Open System Settings") { coordinator.openSystemAudioSettings() }
                    }
                    Text(coordinator.systemAudioPermissionStatus.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if coordinator.systemAudioPermissionStatus.backend == .coreAudioTap {
                        Text("In System Settings, use the NativeDictate switch under \u{201c}System Audio Recording Only.\u{201d} macOS may show it on the same page as screen recording access.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if settings.recordingAudioSource == .systemAudio {
                        systemAudioProbeDurationPicker
                        Button("Run ScreenCaptureKit Probe for \(systemAudioProbeDuration.title)…") {
                            coordinator.testSystemAudio(duration: systemAudioProbeDuration)
                        }
                        .disabled(
                            coordinator.isSystemAudioTestRunning
                                || coordinator.isRecording
                                || coordinator.isProcessing
                        )
                        if coordinator.isSystemAudioTestRunning {
                            Button("Cancel ScreenCaptureKit Probe") {
                                coordinator.cancelSystemAudioTest()
                            }
                        }
                        Text("The test stays on this Mac, creates no History entry and sends nothing to OpenAI.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let message = coordinator.systemAudioTestMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if settings.recordingAudioSource == .mixed {
                Section("Meeting Recording") {
                    Label(
                        coordinator.hasCurrentMeetingRecordingConsent
                            ? "Responsibility confirmed"
                            : "Confirmation required",
                        systemImage: coordinator.hasCurrentMeetingRecordingConsent
                            ? "checkmark.shield.fill"
                            : "person.crop.circle.badge.exclamationmark"
                    )
                    .foregroundStyle(
                        coordinator.hasCurrentMeetingRecordingConsent ? .green : .orange
                    )

                    Text("Before recording, inform everyone involved and obtain any consent required for your location, organization, and meeting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Storage: at 48 kHz, the two uncompressed original tracks use about 1.4 GB per hour. Aligned working copies can roughly double that; higher microphone sample rates need more. NativeDictate warns below 500 MB free and blocks a new mixed recording only below 50 MB.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if coordinator.hasCurrentMeetingRecordingConsent {
                        Button("Reset Meeting Recording Confirmation") {
                            coordinator.resetMeetingRecordingConsent()
                        }
                        .disabled(coordinator.isMixedCaptureTestRunning)
                    } else {
                        Button("Review and Confirm…") {
                            coordinator.requestMeetingRecordingConsent()
                        }
                    }

                    Divider()
                    Button("Run Mixed Capture Test for 5 Seconds…") {
                        coordinator.runMixedCaptureTest()
                    }
                    .disabled(
                        !coordinator.hasCurrentMeetingRecordingConsent
                            || coordinator.isMixedCaptureTestRunning
                            || coordinator.isSystemAudioTestRunning
                            || coordinator.isCoreAudioTapProbeRunning
                            || coordinator.isRecording
                            || coordinator.isProcessing
                    )
                    if coordinator.isMixedCaptureTestRunning {
                        Button("Cancel Mixed Capture Test") {
                            coordinator.cancelMixedCaptureTest()
                        }
                    }
                    Text("Development test: records separate microphone and System Audio originals plus a session manifest. It creates no History entry, starts no transcription and sends nothing over the network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let message = coordinator.mixedCaptureTestMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

#if DEBUG
                    Divider()
                    Group {
                        if coordinator.debugNextMeetingTrackFailureRole == .systemAudio {
                            Button("Cancel Simulated Track Failure") {
                                coordinator.clearNextMeetingTrackTranscriptionFailure()
                            }
                        } else {
                            Button("Fail System Audio Transcription Once") {
                                coordinator.armNextSystemAudioTranscriptionFailure()
                            }
                        }
                    }
                    .disabled(coordinator.isRecording || coordinator.isProcessing)
                    Text("Development test: the next full mixed session keeps both originals, transcribes the microphone, fails System Audio once, and exposes the History retry flow. Release builds omit this control.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                    HStack {
                        Button("Show Mic Clipping Warning") {
                            coordinator.showDebugMicrophoneClippingWarning()
                        }
                        Button("Show System Audio Lost Warning") {
                            coordinator.showDebugSystemAudioLostWarning()
                        }
                    }
                    .disabled(!coordinator.isRecording)
                    Text("Development display test: while a full mixed recording is active, the clipping warning clears after about five seconds; track-loss warnings remain visible. These controls do not alter or discard either original track.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
#endif

                    if #available(macOS 14.2, *) {
                        Divider()
                        systemAudioProbeDurationPicker
                        Button("Run Audio-Only Capture Probe for \(systemAudioProbeDuration.title)…") {
                            coordinator.runCoreAudioTapCaptureProbe(
                                duration: systemAudioProbeDuration
                            )
                        }
                        .disabled(
                            coordinator.isCoreAudioTapProbeRunning
                                || coordinator.isMixedCaptureTestRunning
                                || coordinator.isRecording
                                || coordinator.isProcessing
                        )
                        if coordinator.isCoreAudioTapProbeRunning {
                            Button("Cancel Audio-Only Capture Probe") {
                                coordinator.cancelCoreAudioTapCaptureProbe()
                            }
                        }
                        Button("Run 10 Start/Stop Probe Cycles…") {
                            coordinator.runCoreAudioTapRepeatedCaptureProbe()
                        }
                        .disabled(
                            coordinator.isCoreAudioTapProbeRunning
                                || coordinator.isMixedCaptureTestRunning
                                || coordinator.isRecording
                                || coordinator.isProcessing
                        )
                        Text("Development diagnostic: measures Core Audio tap callbacks and timing without saving audio or creating a History entry.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let message = coordinator.coreAudioTapProbeMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("The audio-only Core Audio tap requires macOS 14.2 or later. ScreenCaptureKit remains the compatibility candidate on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Input") {
                Picker(
                    "Microphone",
                    selection: Binding(
                        get: { settings.inputDeviceUID },
                        set: { coordinator.selectInputDevice(uid: $0) }
                    )
                ) {
                    Text("System Default").tag(nil as String?)
                    ForEach(coordinator.inputDevices) { device in
                        Text(device.name + (device.isDefault ? " (Default)" : ""))
                            .tag(Optional(device.uid))
                    }
                }
                .disabled(
                    coordinator.isRecording
                        || coordinator.isMixedCaptureTestRunning
                        || settings.recordingAudioSource == .systemAudio
                )

                HStack {
                    Text("Input level")
                    ProgressView(value: coordinator.audioLevel)
                    Text("\(Int(coordinator.audioLevel * 100))%")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }

                Button("Refresh Devices") {
                    coordinator.refreshInputDevices()
                }
                .disabled(
                    coordinator.isRecording
                        || coordinator.isMixedCaptureTestRunning
                        || settings.recordingAudioSource == .systemAudio
                )

                if coordinator.isRecording {
                    Text("Microphone controls are paused while a recording is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var systemAudioProbeDurationPicker: some View {
        Picker("Probe duration", selection: $systemAudioProbeDuration) {
            ForEach(SystemAudioProbeDuration.allCases) { duration in
                Text(duration.compactTitle).tag(duration)
            }
        }
        .pickerStyle(.segmented)
        .disabled(
            coordinator.isSystemAudioTestRunning
                || coordinator.isCoreAudioTapProbeRunning
                || coordinator.isMixedCaptureTestRunning
                || coordinator.isRecording
                || coordinator.isProcessing
        )
    }

    private var transcriptionSettings: some View {
        settingsForm {
            if coordinator.transcriptionRestartRequired {
                Section("Restart Required") {
                    Label(
                        "Transcription settings changed",
                        systemImage: "arrow.clockwise.circle.fill"
                    )
                    .foregroundStyle(.orange)
                    Text("NativeDictate will not start another dictation until it has restarted. This prevents local and OpenAI transcription resources from being mixed in one app session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Quit & Restart Now") {
                        coordinator.quitAndRestart()
                    }
                    .disabled(coordinator.isRecording || coordinator.isProcessing)
                }
            }

            Section("Privacy & Provider") {
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { settings.privacyMode },
                        set: { settings.selectPrivacyMode($0) }
                    )
                ) {
                    ForEach(PrivacyMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .disabled(coordinator.isRecording || coordinator.isProcessing)
                Text(settings.privacyMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    "Transcription",
                    selection: Binding(
                        get: { settings.transcriptionProviderID },
                        set: { settings.selectTranscriptionProvider($0) }
                    )
                ) {
                    ForEach(compatibleTranscriptionProviders) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .disabled(
                    compatibleTranscriptionProviders.count == 1
                        || coordinator.isRecording
                        || coordinator.isProcessing
                )
                if settings.transcriptionProviderID == .local {
                    Text("Runs on this Mac. Recording audio is not uploaded for transcription.")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Sends recording audio directly to OpenAI.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                LabeledContent("Audio transcription", value: coordinator.transcriptionLocationSummary)
                LabeledContent("AI improvements", value: coordinator.improvementLocationSummary)
                if settings.transcriptionProviderID == .local {
                    Text("Local transcription never uploads recording audio. OpenAI receives locally transcribed text only when an AI writing style is selected and cloud improvements are allowed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.transcriptionProviderID == .openAI {
                Section("OpenAI") {
                HStack {
                    Text("API key")
                    Spacer()
                    Label(
                        coordinator.apiKeyConfigured ? "Configured" : "Missing",
                        systemImage: coordinator.apiKeyConfigured
                            ? "checkmark.circle.fill"
                            : "xmark.circle"
                    )
                    .foregroundStyle(coordinator.apiKeyConfigured ? .green : .secondary)
                }

                SecureField("New API key", text: $apiKey)
                    .textContentType(.password)

                HStack {
                    Button("Save in Keychain") {
                        coordinator.saveAPIKey(apiKey)
                        apiKey = ""
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Remove from Keychain", role: .destructive) {
                        coordinator.deleteAPIKey()
                    }
                }
            }
            }

            Section("Recognition") {
                if settings.transcriptionProviderID == .openAI {
                    TextField("Model", text: $settings.transcriptionModel)
                } else {
                    LabeledContent("Model", value: LocalModelCatalog.parakeetV3.displayName)
                    localModelControls
                }
                Picker("Language", selection: $settings.transcriptionLanguage) {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
            }

            if settings.transcriptionProviderID == .local,
               settings.privacyMode == .localWithOptionalCloudEnhancement {
                Section("Optional Cloud Enhancement") {
                    Toggle(
                        "Allow enabled AI writing styles to send text to OpenAI",
                        isOn: $settings.cloudEnhancementEnabled
                    )
                    Text("Recording audio remains local. Only the locally transcribed text is sent when an AI writing style is selected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Provider Troubleshooting") {
                restartControls(
                    "A provider, privacy-mode or recognition-model change is saved immediately but becomes active only after Quit & Restart. This deliberately resets every loaded transcription resource."
                )
            }
        }
    }

    @ViewBuilder
    private func restartControls(_ explanation: String) -> some View {
        Button("Quit & Restart") {
            coordinator.quitAndRestart()
        }
        .disabled(coordinator.isRecording || coordinator.isProcessing)
        Text(explanation)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var localModelControls: some View {
        Text("Parakeet is an open-weight speech-recognition model. The download is approximately \(ByteCountFormatter.string(fromByteCount: LocalModelCatalog.parakeetV3.downloadBytes, countStyle: .file)); installation requires about \(ByteCountFormatter.string(fromByteCount: LocalModelCatalog.parakeetV3.installedBytes * 2, countStyle: .file)) of free storage and uses about \(ByteCountFormatter.string(fromByteCount: LocalModelCatalog.parakeetV3.installedBytes, countStyle: .file)) after installation.")
            .font(.caption)
            .foregroundStyle(.secondary)

        switch coordinator.localModelState {
        case let .unavailable(reason):
            Label(reason, systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        case .notInstalled:
            LabeledContent("Status", value: "Not installed")
            Button("Download Local Model…") { coordinator.installLocalModel() }
                .disabled(settings.privacyMode == .offline)
            Text("Downloaded from Hugging Face. Model license: \(LocalModelCatalog.parakeetV3.licenseIdentifier).")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .downloading(progress):
            ProgressView(value: progress) {
                Text("Downloading and preparing local model…")
            }
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button(
                coordinator.isLocalTranscriptionTestRunning
                    ? "Testing Local Transcription…" : "Choose Audio File and Test Locally…"
            ) {
                coordinator.testLocalTranscription()
            }
            .disabled(coordinator.isLocalTranscriptionTestRunning)
            Text("Select an existing WAV, M4A, MP3 or other audio file. It is transcribed only on this Mac; the result is not inserted and no History entry is created.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = coordinator.localTranscriptionTestMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Remove Local Model", role: .destructive) {
                coordinator.removeLocalModel()
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Button("Try Download Again…") { coordinator.installLocalModel() }
                .disabled(settings.privacyMode == .offline)
        }
    }

    private var compatibleTranscriptionProviders: [TranscriptionProviderID] {
        settings.privacyMode == .cloudTranscription ? [.openAI] : [.local]
    }

    private var advancedSettings: some View {
        settingsForm {
            Section("Text Insertion") {
                HStack {
                    Text("Clipboard restore delay")
                    Slider(value: $settings.clipboardRestoreDelay, in: 0.3...2.0, step: 0.1)
                    Text(settings.clipboardRestoreDelay, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                    Text("s")
                }
            }

            Section("Local Audio") {
                Text("Recordings are retained locally and remain recoverable after transcription errors.")
                    .foregroundStyle(.secondary)
                Button("Show Recordings Folder") {
                    coordinator.revealRecordingsFolder()
                }
            }

            Section("Reliability") {
                Toggle("Automatically retry temporary transcription failures", isOn: $settings.automaticRetryEnabled)
            }

            Section("Diagnostics") {
                Button("Export Diagnostics…") {
                    coordinator.exportDiagnostics()
                }
                Text("The export excludes API keys, transcripts, audio, clipboard contents and folder bookmarks.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var storageSettings: some View {
        settingsForm {
            Section("Recordings Folder") {
                LabeledContent("Location") {
                    Text(coordinator.recordingLocationPath ?? "Not configured")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Use Documents/Recordings…") {
                        coordinator.chooseRecordingDirectory(recommended: true)
                    }
                    Button("Choose Another Folder…") {
                        coordinator.chooseRecordingDirectory(recommended: false)
                    }
                    Button("Show in Finder") {
                        coordinator.revealRecordingsFolder()
                    }
                    .disabled(!coordinator.recordingLocationConfigured)
                }
            }

            Section("Retention") {
                Picker("Keep successful audio", selection: $settings.audioRetentionDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(-1)
                }
                Text("Failed and recovered recordings are never deleted automatically.")
                    .font(.caption).foregroundStyle(.secondary)

                Picker("Keep history", selection: $settings.historyRetentionDays) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                    Text("Forever").tag(-1)
                }
                Picker("Maximum history entries", selection: $settings.historyMaximumRecordCount) {
                    Text("250").tag(250)
                    Text("500").tag(500)
                    Text("1,000").tag(1_000)
                    Text("Unlimited").tag(-1)
                }
                Text("History and audio retention are separate. Failed and recovery-required entries are protected.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Apply Retention Now") {
                    coordinator.applyRetentionSettings()
                }
            }

            Section("Migration") {
                Button("Import Phase 1 Recordings") {
                    coordinator.migrateLegacyRecordings()
                }
            }
        }
    }

    private func settingsForm<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Form(content: content)
            .formStyle(.grouped)
            .padding()
    }

    private func permissionRow(
        _ title: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Label(
                granted ? "Allowed" : "Required",
                systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle"
            )
            .foregroundStyle(granted ? .green : .orange)
            Button("Open System Settings", action: action)
        }
    }

    private var speechRecognitionPermissionRow: some View {
        HStack {
            Text("Speech Recognition")
            Spacer()
            Label(
                coordinator.speechPermissionState.title,
                systemImage: coordinator.speechPermissionState == .authorized
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle"
            )
            .foregroundStyle(
                coordinator.speechPermissionState == .authorized ? .green : .orange
            )

            switch coordinator.speechPermissionState {
            case .notDetermined:
                Button("Allow…") {
                    coordinator.requestSpeechRecognitionPermission()
                }
            case .denied, .restricted:
                Button("Open System Settings") {
                    coordinator.openSpeechRecognitionSettings()
                }
            case .authorized:
                EmptyView()
            }
        }
    }
}
