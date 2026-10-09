import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: View {
    let title: String
    let configuration: HotKeyConfiguration
    let onChange: (HotKeyConfiguration) -> Void

    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(isRecording ? "Press shortcut…" : configuration.displayName) {
                isRecording.toggle()
            }
            .frame(minWidth: 190)
            .background {
                ShortcutEventMonitor(isRecording: $isRecording) { event in
                    if event.keyCode == UInt16(kVK_Escape) {
                        isRecording = false
                        return
                    }
                    guard let configuration = Self.configuration(from: event) else { return }
                    onChange(configuration)
                    isRecording = false
                }
                .frame(width: 0, height: 0)
            }
        }
    }

    private static func configuration(from event: NSEvent) -> HotKeyConfiguration? {
        var modifiers: UInt32 = 0
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0 else { return nil }

        let keyName: String
        switch Int(event.keyCode) {
        case kVK_Space: keyName = "Space"
        case kVK_Return: keyName = "Return"
        case kVK_Tab: keyName = "Tab"
        default:
            keyName = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
        return .custom(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyName: keyName)
    }
}

private struct ShortcutEventMonitor: NSViewRepresentable {
    @Binding var isRecording: Bool
    let handler: (NSEvent) -> Void

    func makeNSView(context: Context) -> MonitorView {
        MonitorView()
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.handler = handler
        view.setRecording(isRecording)
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: Void) {
        view.setRecording(false)
    }

    final class MonitorView: NSView {
        var handler: ((NSEvent) -> Void)?
        private var monitor: Any?

        func setRecording(_ recording: Bool) {
            if recording, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handler?(event)
                    return nil
                }
            } else if !recording, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
