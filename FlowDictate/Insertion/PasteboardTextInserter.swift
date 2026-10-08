import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

enum TextInsertionError: LocalizedError {
    case targetUnavailable
    case clipboardWriteFailed
    case keyboardEventCreationFailed

    var errorDescription: String? {
        switch self {
        case .targetUnavailable:
            "The target application is no longer available. Place the cursor in a running application and try again."
        case .clipboardWriteFailed:
            "The transcript could not be written to the clipboard."
        case .keyboardEventCreationFailed:
            "The paste keyboard event could not be created."
        }
    }
}

@MainActor
protocol TextInserting: AnyObject {
    func insert(_ text: String, into target: FocusTarget) async throws
}

@MainActor
final class PasteboardTextInserter: TextInserting {
    static func usesTargetedPaste(for bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.openai.codex"
    }

    private let pasteboard: NSPasteboard
    private var restoreDelay: Duration
    private var pendingRestorationTask: Task<Void, Never>?
    private var pendingOriginalSnapshot: PasteboardSnapshot?
    private var pendingInjectedChangeCount: Int?

    convenience init() {
        self.init(pasteboard: .general, restoreDelay: .milliseconds(600))
    }

    init(pasteboard: NSPasteboard, restoreDelay: Duration) {
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
    }

    func updateRestoreDelay(_ restoreDelay: Duration) {
        self.restoreDelay = restoreDelay
    }

    func insert(_ text: String, into target: FocusTarget) async throws {
        let insertionStarted = ContinuousClock.now
        await waitForModifierRelease()
        let modifierReleaseCompleted = ContinuousClock.now
        guard await target.activate() else {
            NativeDictateLogger.insertion.notice(
                "Paste target activation failed after \(String(describing: modifierReleaseCompleted.duration(to: .now)), privacy: .public)"
            )
            throw TextInsertionError.targetUnavailable
        }
        let targetActivationCompleted = ContinuousClock.now
        let isChatGPT = Self.usesTargetedPaste(for: target.bundleIdentifier)
        if isChatGPT {
            // A menu-bar Restore action can report ChatGPT frontmost before its
            // web composer has regained keyboard focus.
            try await Task.sleep(for: .milliseconds(250))
            guard await target.activate() else {
                NativeDictateLogger.insertion.notice(
                    "Paste target reactivation failed after \(String(describing: targetActivationCompleted.duration(to: .now)), privacy: .public)"
                )
                throw TextInsertionError.targetUnavailable
            }
        }
        let focusSettleCompleted = ContinuousClock.now

        pendingRestorationTask?.cancel()
        NativeDictateLogger.insertion.info("Clipboard snapshot starting")
        let snapshotStarted = ContinuousClock.now
        let snapshot: PasteboardSnapshot
        if let pendingOriginalSnapshot,
           pendingInjectedChangeCount == pasteboard.changeCount {
            snapshot = pendingOriginalSnapshot
        } else {
            snapshot = PasteboardSnapshot.capture(from: pasteboard)
        }
        pendingRestorationTask = nil
        pendingOriginalSnapshot = nil
        pendingInjectedChangeCount = nil
        let snapshotCompleted = ContinuousClock.now

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(to: pasteboard)
            throw TextInsertionError.clipboardWriteFailed
        }
        let injectedChangeCount = pasteboard.changeCount
        let clipboardWriteCompleted = ContinuousClock.now

        do {
            try await postPasteShortcut(to: target)
        } catch {
            snapshot.restore(to: pasteboard)
            throw error
        }

        pendingOriginalSnapshot = snapshot
        pendingInjectedChangeCount = injectedChangeCount
        let delay = isChatGPT ? max(restoreDelay, .seconds(2)) : restoreDelay
        pendingRestorationTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.restoreClipboardIfUnchanged(expectedChangeCount: injectedChangeCount)
        }
        NativeDictateLogger.insertion.info(
            "Paste shortcut posted for \(target.bundleIdentifier ?? "unknown", privacy: .public); modifiers=\(String(describing: insertionStarted.duration(to: modifierReleaseCompleted)), privacy: .public), activation=\(String(describing: modifierReleaseCompleted.duration(to: targetActivationCompleted)), privacy: .public), settle=\(String(describing: targetActivationCompleted.duration(to: focusSettleCompleted)), privacy: .public), snapshot=\(String(describing: snapshotStarted.duration(to: snapshotCompleted)), privacy: .public), clipboardWrite=\(String(describing: snapshotCompleted.duration(to: clipboardWriteCompleted)), privacy: .public), eventPost=\(String(describing: clipboardWriteCompleted.duration(to: .now)), privacy: .public), total=\(String(describing: insertionStarted.duration(to: .now)), privacy: .public); clipboard restoration scheduled"
        )
    }

    private func restoreClipboardIfUnchanged(expectedChangeCount: Int) {
        defer {
            pendingRestorationTask = nil
            pendingOriginalSnapshot = nil
            pendingInjectedChangeCount = nil
        }
        guard pasteboard.changeCount == expectedChangeCount else {
            NativeDictateLogger.insertion.notice(
                "Clipboard changed after paste; skipped restoration to avoid overwriting newer content"
            )
            return
        }
        guard let snapshot = pendingOriginalSnapshot,
              snapshot.restore(to: pasteboard) else {
            NativeDictateLogger.insertion.error("Clipboard restoration returned false")
            return
        }
        NativeDictateLogger.insertion.info("Clipboard restored after completed paste")
    }

    private func waitForModifierRelease(timeout: Duration = .seconds(2)) async {
        let relevantFlags: CGEventFlags = [
            .maskAlternate,
            .maskCommand,
            .maskControl,
            .maskShift,
            .maskSecondaryFn
        ]
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(relevantFlags).isEmpty {
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func postPasteShortcut(to target: FocusTarget) async throws {
        let creationStarted = ContinuousClock.now
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            )
        else {
            throw TextInsertionError.keyboardEventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        let creationCompleted = ContinuousClock.now
        if Self.usesTargetedPaste(for: target.bundleIdentifier) {
            // Route to the app selected for insertion, not whichever process
            // temporarily owns the event stream while the menu closes.
            keyDown.postToPid(target.processIdentifier)
            let keyDownCompleted = ContinuousClock.now
            try? await Task.sleep(for: .milliseconds(30))
            keyUp.postToPid(target.processIdentifier)
            NativeDictateLogger.insertion.info(
                "Targeted paste event timing: create=\(String(describing: creationStarted.duration(to: creationCompleted)), privacy: .public), keyDown=\(String(describing: creationCompleted.duration(to: keyDownCompleted)), privacy: .public), keyUp=\(String(describing: keyDownCompleted.duration(to: .now)), privacy: .public)"
            )
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            NativeDictateLogger.insertion.info(
                "Global paste event timing: \(String(describing: creationStarted.duration(to: .now)), privacy: .public)"
            )
        }
    }
}
