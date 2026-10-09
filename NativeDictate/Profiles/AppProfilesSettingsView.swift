import SwiftUI

struct AppProfilesSettingsView: View {
    @ObservedObject var coordinator: DictationCoordinator

    var body: some View {
        Form {
            if coordinator.transcriptionRestartRequired {
                Section("Restart Required") {
                    Label(
                        "A profile changed the transcription provider or model.",
                        systemImage: "arrow.clockwise.circle.fill"
                    )
                    .foregroundStyle(.orange)
                    Button("Quit & Restart Now") { coordinator.quitAndRestart() }
                        .disabled(coordinator.isRecording || coordinator.isProcessing)
                }
            }

            Section {
                Text("Profiles are selected by app bundle identifier when recording starts. Empty values inherit the global setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Switching to an app profile with a different transcription provider or model requires a restart before recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Menu("Add Recent App") {
                    if coordinator.recentProfileCandidates.isEmpty {
                        Text("No unconfigured recent apps")
                    } else {
                        ForEach(coordinator.recentProfileCandidates, id: \.bundleIdentifier) { candidate in
                            Button(candidate.displayName) {
                                coordinator.saveAppProfile(.new(
                                    bundleIdentifier: candidate.bundleIdentifier,
                                    displayName: candidate.displayName
                                ))
                            }
                        }
                    }
                }
            }

            ForEach(coordinator.appProfiles) { profile in
                Section(profile.displayName) {
                    Toggle("Enabled", isOn: binding(profile, \.isEnabled))
                    LabeledContent("Bundle ID", value: profile.bundleIdentifier)
                    Picker("Transcription provider", selection: optionalProviderBinding(profile)) {
                        Text("Inherit global").tag(nil as TranscriptionProviderID?)
                        ForEach(TranscriptionProviderID.allCases) { provider in
                            Text(provider.title).tag(Optional(provider))
                        }
                    }
                    Picker("Language", selection: optionalLanguageBinding(profile)) {
                        Text("Inherit global").tag(nil as TranscriptionLanguage?)
                        ForEach(TranscriptionLanguage.allCases) { language in
                            Text(language.title).tag(Optional(language))
                        }
                    }
                    TextField("Transcription model (inherit global)", text: optionalModelBinding(profile))
                    Picker("Writing style", selection: optionalStyleBinding(profile)) {
                        Text("Inherit global").tag(nil as UUID?)
                        ForEach(coordinator.writingStyles.filter(\.isEnabled)) { style in
                            Text(style.name).tag(Optional(style.id))
                        }
                    }
                    Picker("Spoken formatting", selection: optionalBoolBinding(profile)) {
                        Text("Inherit global").tag(nil as Bool?)
                        Text("On").tag(Optional(true))
                        Text("Off").tag(Optional(false))
                    }
                    Picker("Insertion", selection: binding(profile, \.insertionPreference)) {
                        ForEach(InsertionPreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    Text(profile.insertionPreference == .clipboard
                         ? "Always pastes through the clipboard. macOS may show a privacy notice when NativeDictate reads or restores clipboard contents from another app."
                         : "Inserts directly through Accessibility first. If the target app does not support direct insertion, NativeDictate uses the clipboard as a bounded fallback.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Delete Profile", role: .destructive) {
                        coordinator.deleteAppProfile(profile)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await coordinator.refreshAppProfiles() }
    }

    private func binding<Value>(
        _ profile: AppDictationProfile,
        _ keyPath: WritableKeyPath<AppDictationProfile, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                coordinator.appProfiles.first { $0.id == profile.id }?[keyPath: keyPath]
                    ?? profile[keyPath: keyPath]
            },
            set: { value in
                var updated = coordinator.appProfiles.first { $0.id == profile.id } ?? profile
                updated[keyPath: keyPath] = value
                coordinator.saveAppProfile(updated)
            }
        )
    }

    private func optionalLanguageBinding(_ profile: AppDictationProfile) -> Binding<TranscriptionLanguage?> {
        binding(profile, \.language)
    }

    private func optionalProviderBinding(_ profile: AppDictationProfile) -> Binding<TranscriptionProviderID?> {
        binding(profile, \.transcriptionProviderID)
    }

    private func optionalStyleBinding(_ profile: AppDictationProfile) -> Binding<UUID?> {
        binding(profile, \.writingStyleID)
    }

    private func optionalModelBinding(_ profile: AppDictationProfile) -> Binding<String> {
        Binding(
            get: {
                coordinator.appProfiles.first { $0.id == profile.id }?.transcriptionModel ?? ""
            },
            set: { value in
                var updated = coordinator.appProfiles.first { $0.id == profile.id } ?? profile
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                updated.transcriptionModel = trimmed.isEmpty ? nil : value
                coordinator.saveAppProfile(updated)
            }
        )
    }

    private func optionalBoolBinding(_ profile: AppDictationProfile) -> Binding<Bool?> {
        binding(profile, \.spokenFormattingEnabled)
    }
}
