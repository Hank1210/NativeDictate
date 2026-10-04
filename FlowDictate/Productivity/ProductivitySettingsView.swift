import SwiftUI

struct ProductivitySettingsView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @ObservedObject private var settings: AppSettings
    @State private var statisticsPeriod: UsageStatisticsPeriod = .total
    @State private var isResetConfirmationPresented = false

    init(coordinator: DictationCoordinator) {
        self.coordinator = coordinator
        _settings = ObservedObject(wrappedValue: coordinator.settings)
    }

    var body: some View {
        Form {
            Section("Local Usage Statistics") {
                Toggle("Show usage statistics", isOn: $settings.showUsageStatistics)
                if settings.showUsageStatistics {
                    Picker("Period", selection: $statisticsPeriod) {
                        ForEach(UsageStatisticsPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)

                    let statistics = coordinator.usageStatistics(period: statisticsPeriod)
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        metric("Successful dictations", statistics.successfulDictations.formatted(), "checkmark.circle")
                        metric("Dictated words", statistics.wordCount.formatted(), "text.word.spacing")
                        metric("Characters", statistics.characterCount.formatted(), "character.cursor.ibeam")
                        metric("Recording time", duration(statistics.totalDuration), "waveform")
                        metric("Average words", statistics.averageWordsPerDictation.formatted(.number.precision(.fractionLength(0))), "sum")
                        metric("Average duration", duration(statistics.averageDuration, includeSeconds: true), "timer")
                        metric("Estimated time saved", duration(statistics.estimatedSecondsSaved), "clock.arrow.circlepath")
                        metric("Retries", statistics.retryCount.formatted(), "arrow.clockwise")
                    }

                    HStack {
                        Text("Typing speed")
                        Slider(value: $settings.typingWordsPerMinute, in: 10...120, step: 5)
                        Text("\(Int(settings.typingWordsPerMinute)) wpm")
                            .monospacedDigit().frame(width: 70)
                    }
                    Text("Statistics are calculated only from your local History and are never uploaded.")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack {
                        if let resetDate = settings.usageStatisticsResetDate {
                            Text("Statistics reset \(resetDate.formatted(date: .abbreviated, time: .shortened)).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset Statistics…", role: .destructive) {
                            isResetConfirmationPresented = true
                        }
                    }
                    .confirmationDialog(
                        "Reset usage statistics?",
                        isPresented: $isResetConfirmationPresented
                    ) {
                        Button("Reset Statistics", role: .destructive) {
                            settings.usageStatisticsResetDate = Date()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Existing History entries and recordings will not be deleted.")
                    }
                }
            }

            Section("Community Updates") {
                LabeledContent("Installed", value: "NativeDictate \(FlowDictateVersion.displayString)")
                LabeledContent("Edition", value: "Community")
                Toggle("Check for new stable releases once per day", isOn: $settings.updateCheckEnabled)
                Button {
                    Task { await coordinator.checkForUpdates() }
                } label: {
                    HStack(spacing: 8) {
                        if coordinator.isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(coordinator.isCheckingForUpdates ? "Checking…" : "Check Now")
                    }
                }
                .disabled(coordinator.isCheckingForUpdates)
                if let message = coordinator.updateCheckMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let release = coordinator.availableRelease {
                    LabeledContent("Available", value: release.name)
                    if !release.summary.isEmpty {
                        Text(release.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Open GitHub Release Page") { coordinator.openAvailableRelease() }
                }
                Text("NativeDictate never downloads or installs an update automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func metric(_ label: String, _ value: String, _ systemImage: String) -> some View {
        GroupBox {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .monospacedDigit()
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func duration(_ seconds: TimeInterval, includeSeconds: Bool = false) -> String {
        if includeSeconds {
            return Duration.seconds(seconds).formatted(
                .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)
            )
        }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated)
        )
    }
}
