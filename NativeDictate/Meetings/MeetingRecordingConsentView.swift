import AppKit
import SwiftUI

@MainActor
protocol MeetingRecordingConsentPresenting: AnyObject {
    func present(
        onConfirm: @escaping @MainActor (_ rememberConfirmation: Bool) -> Void,
        onCancel: @escaping @MainActor () -> Void
    )
}

@MainActor
final class MeetingRecordingConsentWindowController: NSWindowController, NSWindowDelegate,
    MeetingRecordingConsentPresenting {
    private var onConfirm: (@MainActor (Bool) -> Void)?
    private var onCancel: (@MainActor () -> Void)?

    func present(
        onConfirm: @escaping @MainActor (Bool) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        self.onConfirm = onConfirm
        self.onCancel = onCancel
        let rootView = MeetingRecordingConsentView(
            onConfirm: { [weak self] remember in self?.confirm(remember: remember) },
            onCancel: { [weak self] in self?.cancel() }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = "Mixed Recording Consent"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 430))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard onCancel != nil else { return }
        let action = onCancel
        clearActions()
        action?()
    }

    private func confirm(remember: Bool) {
        let action = onConfirm
        clearActions()
        close()
        action?(remember)
    }

    private func cancel() {
        let action = onCancel
        clearActions()
        close()
        action?()
    }

    private func clearActions() {
        onConfirm = nil
        onCancel = nil
    }
}

private struct MeetingRecordingConsentView: View {
    @State private var rememberConfirmation = true
    let onConfirm: (Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Before recording a conversation")
                        .font(.title2.weight(.semibold))
                    Text("Microphone + System Audio")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                sourceRow(
                    title: "Your microphone",
                    detail: "Records your voice",
                    symbol: "mic.fill"
                )
                Divider().padding(.leading, 42)
                sourceRow(
                    title: "System Audio",
                    detail: "Records voices and sound played by other apps",
                    symbol: "speaker.wave.2.fill"
                )
            }
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))

            Text(
                "Before you record, inform everyone involved and obtain any consent required for your location, organization, and meeting. You are responsible for deciding whether recording is permitted. NativeDictate cannot provide legal advice."
            )
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)

            Toggle("Remember this confirmation on this Mac", isOn: $rememberConfirmation)

            Divider()

            HStack {
                Text("Confirming does not start a recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Confirm and Continue") {
                    onConfirm(rememberConfirmation)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func sourceRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
