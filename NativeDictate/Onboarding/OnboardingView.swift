import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(coordinator: DictationCoordinator) {
        let rootView = OnboardingView(coordinator: coordinator)
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = "Welcome to NativeDictate"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 680, height: 540))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

struct OnboardingView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @State private var step = 0
    @State private var apiKey = ""
    @State private var validating = false

    private let steps = ["Welcome", "Storage", "Transcription", "Permissions", "Shortcuts", "Ready"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 5)
                }
            }
            .padding()

            Group {
                switch step {
                case 0: welcome
                case 1: storage
                case 2: credentials
                case 3: permissions
                case 4: shortcuts
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)

            Divider()
            HStack {
                Button("Back") { step -= 1 }.disabled(step == 0)
                Spacer()
                Text(coordinator.setupMessage ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                if step < steps.count - 1 {
                    Button("Continue") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinue)
                } else {
                    Button("Start NativeDictate") { coordinator.completeOnboarding() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!coordinator.transcriptionSetupReady || !coordinator.recordingLocationConfigured)
                }
            }
            .padding()
        }
        .onAppear {
            coordinator.refreshConfigurationStatus()
            coordinator.refreshPermissionStatus()
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 72)).foregroundStyle(.tint)
            Text("Welcome to NativeDictate").font(.largeTitle.bold())
            Text("Dictate into any app from the menu bar. Choose local transcription to keep audio on this Mac, or explicitly use OpenAI with your own API key.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 520)
        }
    }

    private var storage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Choose where recordings are stored", systemImage: "folder")
                .font(.title2.bold())
            Text("The recommended location is a Recordings folder inside Documents. macOS asks you to confirm the folder once so NativeDictate can keep secure write access.")
                .foregroundStyle(.secondary)
            statusRow("Recordings folder", value: coordinator.recordingLocationPath ?? "Not configured",
                      ready: coordinator.recordingLocationConfigured)
            HStack {
                Button("Use Documents/Recordings…") { coordinator.chooseRecordingDirectory(recommended: true) }
                Button("Choose Another Folder…") { coordinator.chooseRecordingDirectory(recommended: false) }
            }
            if coordinator.recordingLocationConfigured {
                Button("Import Phase 1 Recordings") { coordinator.migrateLegacyRecordings() }
            }
        }
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Choose transcription", systemImage: "waveform.badge.magnifyingglass")
                .font(.title2.bold())
            Picker(
                "Provider",
                selection: Binding(
                    get: { coordinator.settings.transcriptionProviderID },
                    set: { coordinator.settings.selectTranscriptionProvider($0) }
                )
            ) {
                Text("On this Mac").tag(TranscriptionProviderID.local)
                Text("OpenAI").tag(TranscriptionProviderID.openAI)
            }
            .pickerStyle(.segmented)

            if coordinator.transcriptionRestartRequired {
                Label(
                    "Restart NativeDictate to activate this transcription provider.",
                    systemImage: "arrow.clockwise.circle.fill"
                )
                .foregroundStyle(.orange)
                Button("Quit & Restart Now") { coordinator.quitAndRestart() }
            }

            if coordinator.settings.transcriptionProviderID == .local {
                Text("Audio stays on this Mac. Local transcription requires Apple Silicon and an approximately \(ByteCountFormatter.string(fromByteCount: LocalModelCatalog.parakeetV3.downloadBytes, countStyle: .file)) model download.")
                    .foregroundStyle(.secondary)
                localModelSetup
            } else {
                Text("Your API key is stored only in macOS Keychain. Recording audio is sent directly to OpenAI for transcription.")
                    .foregroundStyle(.secondary)
                statusRow("API key", value: coordinator.apiKeyConfigured ? "Configured" : "Missing",
                          ready: coordinator.apiKeyConfigured)
                SecureField("OpenAI API key", text: $apiKey)
                    .textContentType(.password)
                Button(validating ? "Checking…" : "Verify and Save Securely") {
                    validating = true
                    Task {
                        if await coordinator.validateAndSaveAPIKey(apiKey) { apiKey = "" }
                        validating = false
                    }
                }
                .disabled(validating || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var localModelSetup: some View {
        switch coordinator.localModelState {
        case let .unavailable(reason):
            Label(reason, systemImage: "xmark.circle").foregroundStyle(.orange)
        case .notInstalled:
            statusRow("Local model", value: "Not installed", ready: false)
            Button("Download Local Model") { coordinator.installLocalModel() }
        case let .downloading(progress):
            ProgressView(value: progress) { Text("Downloading local model…") }
        case .installed:
            statusRow("Local model", value: "Installed", ready: true)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            Button("Try Download Again") { coordinator.installLocalModel() }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Allow system access", systemImage: "checkmark.shield.fill").font(.title2.bold())
            Text("Microphone records your voice. Speech Recognition can show an optional local live preview. Accessibility lets NativeDictate paste the final transcript.")
                .foregroundStyle(.secondary)
            statusRow("Microphone", value: coordinator.microphonePermissionGranted ? "Allowed" : "Required",
                      ready: coordinator.microphonePermissionGranted)
            statusRow("Accessibility", value: coordinator.accessibilityPermissionGranted ? "Allowed" : "Required",
                      ready: coordinator.accessibilityPermissionGranted)
            statusRow(
                "Speech Recognition (optional)",
                value: coordinator.speechPermissionState.title,
                ready: coordinator.speechPermissionState == .authorized
                    || !coordinator.settings.livePreviewEnabled
            )
            Toggle(
                "Show local Live Preview while recording",
                isOn: Binding(
                    get: { coordinator.settings.livePreviewEnabled },
                    set: { coordinator.settings.livePreviewEnabled = $0 }
                )
            )
            if coordinator.settings.livePreviewEnabled {
                Text("Live Preview also needs macOS Dictation enabled in System Settings → Keyboard → Dictation. Speech Recognition permission alone may not be enough. Final transcription still works without Live Preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Microphone Permissions") {
                    Task { await coordinator.requestMicrophonePermission() }
                }
                if coordinator.settings.livePreviewEnabled
                    && coordinator.speechPermissionState == .notDetermined {
                    Button("Allow Live Preview") {
                        coordinator.requestSpeechRecognitionPermission()
                    }
                } else if coordinator.settings.livePreviewEnabled
                    && coordinator.speechPermissionState != .authorized {
                    Button("Speech Recognition Settings") {
                        coordinator.openSpeechRecognitionSettings()
                    }
                }
                Button("Microphone Settings") { coordinator.openMicrophoneSettings() }
                Button("Accessibility Settings") { coordinator.openAccessibilitySettings() }
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Keyboard shortcuts", systemImage: "keyboard").font(.title2.bold())
            ShortcutRecorderView(title: "Start / Stop", configuration: coordinator.settings.dictationHotKey,
                                 onChange: coordinator.setDictationHotKey)
            ShortcutRecorderView(title: "Cancel", configuration: coordinator.settings.cancelHotKey,
                                 onChange: coordinator.setCancelHotKey)
            ShortcutRecorderView(title: "Restore Last", configuration: coordinator.settings.restoreHotKey,
                                 onChange: coordinator.setRestoreHotKey)
            Text("You can change these later in Settings → Dictation.").foregroundStyle(.secondary)
        }
    }

    private var ready: some View {
        VStack(spacing: 18) {
            let prerequisitesReady = Self.isReady(
                recordingLocationConfigured: coordinator.recordingLocationConfigured,
                transcriptionSetupReady: coordinator.transcriptionSetupReady
            )
            Image(systemName: prerequisitesReady ? "checkmark.circle.fill" : "exclamationmark.triangle")
                .font(.system(size: 72)).foregroundStyle(prerequisitesReady ? .green : .orange)
            Text(prerequisitesReady ? "NativeDictate is ready" : "Setup needs attention")
                .font(.largeTitle.bold())
            Text("Place the cursor in another app and press \(coordinator.settings.dictationHotKey.displayName) to begin.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Toggle("Launch NativeDictate at login", isOn: Binding(
                get: { coordinator.launchAtLogin.isEnabled },
                set: { coordinator.launchAtLogin.setEnabled($0) }
            ))
            .frame(width: 280)
        }
    }

    private var canContinue: Bool {
        Self.canContinue(
            step: step,
            recordingLocationConfigured: coordinator.recordingLocationConfigured,
            transcriptionSetupReady: coordinator.transcriptionSetupReady
        )
    }

    static func canContinue(
        step: Int,
        recordingLocationConfigured: Bool,
        transcriptionSetupReady: Bool
    ) -> Bool {
        switch step {
        case 1: recordingLocationConfigured
        case 2: transcriptionSetupReady
        default: true
        }
    }

    static func isReady(
        recordingLocationConfigured: Bool,
        transcriptionSetupReady: Bool
    ) -> Bool {
        recordingLocationConfigured && transcriptionSetupReady
    }

    private func statusRow(_ title: String, value: String, ready: Bool) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ready ? .green : .orange)
            Text(title).fontWeight(.medium)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
