import AppKit
import SwiftUI

struct SmartDictationSettingsView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @ObservedObject private var settings: AppSettings
    @State private var showingDictionary = false
    @State private var showingStyles = false
    @State private var sampleText = "Das ist äh ein kurzer Test Punkt neuer Absatz Flow Diktat"

    init(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        _settings = ObservedObject(wrappedValue: coordinator.settings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                pipelineStrip
                explanationCard
                Form {
                    Section("Local processing") {
                        Toggle("Recognize spoken formatting commands", isOn: $settings.spokenFormattingEnabled)
                        Text("Supports punctuation, new lines, paragraphs and bullet points in German and English.")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Apply personal dictionary", isOn: $settings.personalDictionaryEnabled)
                        HStack {
                            Button("Manage Dictionary…") { showingDictionary = true }
                            Text("\(coordinator.dictionaryEntries.count) entries")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Section("Writing style") {
                        Picker("Default style", selection: $settings.writingStyleID) {
                            ForEach(coordinator.writingStyles.filter(\.isEnabled)) { style in
                                Text(style.name).tag(style.id)
                            }
                        }
                        Button("Manage Writing Styles…") { showingStyles = true }

                        if selectedStyle.usesAI {
                            if enhancementAllowed {
                                Label(
                                    "This style sends text—not audio—to OpenAI and creates one additional API request per dictation.",
                                    systemImage: "sparkles"
                                )
                                .font(.caption)
                                .foregroundStyle(.indigo)
                                Text("The additional cloud request can noticeably extend Processing. Choose Original for the fastest insertion.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Enhancement model", text: $settings.enhancementModel)
                                Picker("If enhancement fails", selection: $settings.smartDictationFallback) {
                                    ForEach(SmartDictationFallback.allCases) { option in
                                        Text(option.title).tag(option)
                                    }
                                }
                            } else {
                                Label(
                                    "\(selectedStyle.name) is inactive because OpenAI improvement is not permitted. NativeDictate will insert the locally processed text.",
                                    systemImage: "cloud.slash"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            }
                        } else {
                            Label("Original uses no additional AI request.", systemImage: "lock.shield")
                                .font(.caption).foregroundStyle(.green)
                        }
                    }

                    Section("Try it") {
                        Text("Compare the local rules and selected style without recording audio.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $sampleText)
                            .font(.body)
                            .frame(minHeight: 66)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(.secondary.opacity(0.2))
                            }
                        Button(coordinator.isSmartDictationTestRunning ? "Processing…" : "Process Sample") {
                            coordinator.testSmartDictation(sampleText)
                        }
                        .disabled(coordinator.isSmartDictationTestRunning || sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let output = coordinator.smartDictationTestOutput {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("FINAL")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundStyle(.secondary)
                                Text(output).textSelection(.enabled)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .padding(20)
        }
        .sheet(isPresented: $showingDictionary) {
            DictionaryManagerView(coordinator: coordinator)
        }
        .sheet(isPresented: $showingStyles) {
            WritingStyleManagerView(coordinator: coordinator)
        }
        .task { await coordinator.refreshSmartDictationData() }
    }

    private var selectedStyle: WritingStyleProfile {
        coordinator.writingStyles.first { $0.id == settings.writingStyleID }
            ?? BuiltInWritingStyles.all[0]
    }

    private var enhancementAllowed: Bool {
        NetworkPolicy(
            mode: settings.privacyMode,
            cloudEnhancementEnabled: settings.cloudEnhancementEnabled
        ).allows(.enhancement)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 42, height: 42)
                .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text("Smart Dictation").font(.title2.bold())
                Text("Keep the original. Improve only what you choose.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("How it works", systemImage: "info.circle")
                .font(.headline)
            Text("After transcription, NativeDictate first applies spoken commands and your personal dictionary locally. The selected default writing style then creates the final text.")
            Text("The style is applied automatically to every new dictation—you do not need to say its name. Original makes no additional AI request; all other styles send text, but not audio, to OpenAI.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.indigo.opacity(0.14))
        }
    }

    private var pipelineStrip: some View {
        HStack(spacing: 7) {
            pipelineStep("Original", active: true)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            pipelineStep("Commands", active: settings.spokenFormattingEnabled)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            pipelineStep("Dictionary", active: settings.personalDictionaryEnabled)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            pipelineStep(selectedStyle.name, active: selectedStyle.usesAI)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
    }

    private func pipelineStep(_ title: String, active: Bool) -> some View {
        Text(title)
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(active ? Color.indigo.opacity(0.11) : Color.secondary.opacity(0.07), in: Capsule())
            .foregroundStyle(active ? Color.indigo : Color.secondary)
    }
}

private struct DictionaryManagerView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var spokenForm = ""
    @State private var replacement = ""
    @State private var language = ""
    @State private var caseSensitive = false
    @State private var wholeWords = true
    @State private var enabled = true
    @State private var createdAt = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Personal Dictionary").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding()
            Divider()
            HSplitView {
                VStack(spacing: 8) {
                    List(coordinator.dictionaryEntries, selection: $selection) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.spokenForm)
                            Text(entry.replacement).font(.caption).foregroundStyle(.secondary)
                        }.tag(entry.id)
                    }
                    HStack {
                        Button { newEntry() } label: { Image(systemName: "plus") }
                        Button(role: .destructive) { deleteSelected() } label: { Image(systemName: "minus") }
                            .disabled(selectedEntry == nil)
                        Spacer()
                    }.padding(.horizontal).padding(.bottom, 10)
                }.frame(minWidth: 220)

                Form {
                    Section("Replacement") {
                        if selection == nil {
                            Label(
                                "New entry: fill in both highlighted fields, then save the entry.",
                                systemImage: "square.and.pencil"
                            )
                            .font(.caption)
                            .foregroundStyle(.indigo)
                        }
                        dictionaryTextField("Spoken form", text: $spokenForm)
                        dictionaryTextField("Replacement", text: $replacement)
                        Picker("Language", selection: $language) {
                            Text("Any language").tag("")
                            Text("German").tag("de")
                            Text("English").tag("en")
                        }
                        Toggle("Match whole words only", isOn: $wholeWords)
                        Toggle("Case sensitive", isOn: $caseSensitive)
                        Toggle("Enabled", isOn: $enabled)
                    }
                    Section("Preview") {
                        Text(previewText).textSelection(.enabled)
                    }
                    Button("Save Entry") { save() }
                        .disabled(spokenForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .formStyle(.grouped)
                .frame(minWidth: 390)
            }
            Divider()
            HStack {
                Button("Import…") { coordinator.importDictionary() }
                Button("Export…") { coordinator.exportDictionary() }
                Spacer()
                if let message = coordinator.setupMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            }.padding()
        }
        .frame(width: 680, height: 470)
        .onChange(of: selection) { loadSelected() }
        .task { await coordinator.refreshSmartDictationData() }
    }

    private var selectedEntry: DictionaryEntry? { coordinator.dictionaryEntries.first { $0.id == selection } }

    private func dictionaryTextField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Write here", text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
        }
    }

    private var previewText: String {
        guard !spokenForm.isEmpty else { return "Enter a spoken form to preview the rule." }
        let entry = DictionaryEntry(
            id: selection ?? UUID(), spokenForm: spokenForm, replacement: replacement,
            language: language.isEmpty ? nil : language, caseSensitive: caseSensitive,
            matchWholeWordsOnly: wholeWords, isEnabled: true, createdAt: createdAt, updatedAt: Date()
        )
        return PersonalDictionaryProcessor().process(
            "Example: \(spokenForm) appears here.", entries: [entry], language: entry.language
        ).text
    }

    private func newEntry() { selection = nil; spokenForm = ""; replacement = ""; language = ""; caseSensitive = false; wholeWords = true; enabled = true; createdAt = Date() }
    private func loadSelected() {
        guard let entry = selectedEntry else { return }
        spokenForm = entry.spokenForm; replacement = entry.replacement; language = entry.language ?? ""
        caseSensitive = entry.caseSensitive; wholeWords = entry.matchWholeWordsOnly; enabled = entry.isEnabled; createdAt = entry.createdAt
    }
    private func save() {
        let id = selection ?? UUID()
        coordinator.saveDictionaryEntry(DictionaryEntry(
            id: id,
            spokenForm: spokenForm.trimmingCharacters(in: .whitespacesAndNewlines),
            replacement: replacement.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language.isEmpty ? nil : language,
            caseSensitive: caseSensitive, matchWholeWordsOnly: wholeWords, isEnabled: enabled,
            createdAt: createdAt, updatedAt: Date()
        ))
        selection = id
    }
    private func deleteSelected() { if let entry = selectedEntry { coordinator.deleteDictionaryEntry(entry); newEntry() } }
}

private struct WritingStyleManagerView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var name = ""
    @State private var instruction = ""
    @State private var enabled = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Writing Styles").font(.title2.bold())
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding()
            Divider()
            HSplitView {
                List(coordinator.writingStyles, selection: $selection) { style in
                    HStack {
                        Image(systemName: style.usesAI ? "sparkles" : "doc.plaintext")
                            .foregroundStyle(style.usesAI ? .indigo : .secondary)
                        Text(style.name)
                        if style.isBuiltIn { Spacer(); Text("BUILT-IN").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
                    }.tag(style.id)
                }.frame(minWidth: 230)

                Form {
                    Section("Style") {
                        TextField("Name", text: $name).disabled(selectedStyle?.isBuiltIn == true)
                        TextEditor(text: $instruction)
                            .frame(minHeight: 130)
                            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.2)) }
                            .disabled(selectedStyle?.isBuiltIn == true)
                        Toggle("Enabled", isOn: $enabled).disabled(selectedStyle?.isBuiltIn == true)
                    }
                    HStack {
                        if let style = selectedStyle {
                            Button("Duplicate") { coordinator.duplicateWritingStyle(style) }
                            if !style.isBuiltIn {
                                Button("Delete", role: .destructive) { coordinator.deleteWritingStyle(style); selection = nil }
                            }
                        } else {
                            Button("Create Style") { createStyle() }
                        }
                        Spacer()
                        Button("Save Changes") { save() }
                            .disabled(selectedStyle?.isBuiltIn != false)
                    }
                }.formStyle(.grouped).frame(minWidth: 410)
            }
            Divider()
            HStack {
                Button("New Style") { selection = nil; name = ""; instruction = ""; enabled = true }
                Button("Import…") { coordinator.importWritingStyles() }
                Button("Export…") { coordinator.exportWritingStyles() }
                Spacer()
                if let message = coordinator.setupMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            }.padding()
        }
        .frame(width: 720, height: 500)
        .onChange(of: selection) { loadSelected() }
        .task { await coordinator.refreshSmartDictationData() }
    }

    private var selectedStyle: WritingStyleProfile? { coordinator.writingStyles.first { $0.id == selection } }
    private func loadSelected() { guard let style = selectedStyle else { return }; name = style.name; instruction = style.instruction; enabled = style.isEnabled }
    private func createStyle() {
        let style = WritingStyleProfile(id: UUID(), name: name, instruction: instruction, isBuiltIn: false, isEnabled: enabled, schemaVersion: 1)
        coordinator.saveWritingStyle(style); selection = style.id
    }
    private func save() {
        guard let style = selectedStyle, !style.isBuiltIn else { return }
        coordinator.saveWritingStyle(WritingStyleProfile(
            id: style.id, name: name, instruction: instruction,
            isBuiltIn: false, isEnabled: enabled, schemaVersion: 1
        ))
    }
}
