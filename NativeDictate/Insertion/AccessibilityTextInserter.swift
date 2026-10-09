import AppKit
import ApplicationServices
import Foundation
import OSLog

enum DirectInsertionError: LocalizedError {
    case unsupported
    case protectedField
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unsupported: "The focused control does not support direct text insertion."
        case .protectedField: "NativeDictate will not insert text into a protected field."
        case .writeFailed: "Direct text insertion failed."
        }
    }
}

@MainActor
final class AccessibilityTextInserter: TextInserting {
    private let maximumCharacterCount: Int
    private let messagingTimeout: Float

    init(maximumCharacterCount: Int = 100_000, messagingTimeout: Float = 0.5) {
        self.maximumCharacterCount = maximumCharacterCount
        self.messagingTimeout = messagingTimeout
    }

    func insert(_ text: String, into target: FocusTarget) async throws {
        guard text.count <= maximumCharacterCount else { throw DirectInsertionError.unsupported }
        guard await target.activate() else { throw TextInsertionError.targetUnavailable }

        let processIdentifier = target.processIdentifier
        let messagingTimeout = messagingTimeout
        try await Task.detached(priority: .userInitiated) {
            try Self.insertSynchronously(
                text,
                processIdentifier: processIdentifier,
                messagingTimeout: messagingTimeout
            )
        }.value
    }

    private nonisolated static func insertSynchronously(
        _ text: String,
        processIdentifier: pid_t,
        messagingTimeout: Float
    ) throws {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else { throw DirectInsertionError.unsupported }

        let element = unsafeBitCast(focusedValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &subroleValue
        )
        let subrole = subroleValue as? String
        if subrole == kAXSecureTextFieldSubrole as String {
            throw DirectInsertionError.protectedField
        }

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success,
        settable.boolValue else { throw DirectInsertionError.unsupported }

        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success else { throw DirectInsertionError.writeFailed }

        NativeDictateLogger.insertion.info("Transcript inserted through Accessibility")
    }
}

@MainActor
final class FallbackTextInserter: TextInserting {
    /// Word's Accessibility tree can block selected-text inspection. ChatGPT's
    /// composer can report a successful AX selected-text write without showing
    /// the text. Both need the clipboard path; other apps keep the AX-first path.
    private static let clipboardPreferredBundleIdentifiers: Set<String> = [
        "com.microsoft.Word",
        "com.openai.codex"
    ]

    private let direct: TextInserting
    private let clipboard: TextInserting

    init(direct: TextInserting, clipboard: TextInserting) {
        self.direct = direct
        self.clipboard = clipboard
    }

    func insert(_ text: String, into target: FocusTarget) async throws {
        if let bundleIdentifier = target.bundleIdentifier,
           Self.clipboardPreferredBundleIdentifiers.contains(bundleIdentifier) {
            NativeDictateLogger.insertion.info(
                "Using clipboard insertion for \(bundleIdentifier, privacy: .public)"
            )
            try await clipboard.insert(text, into: target)
            return
        }

        let directStarted = ContinuousClock.now
        do {
            try await direct.insert(text, into: target)
        } catch DirectInsertionError.protectedField {
            throw DirectInsertionError.protectedField
        } catch {
            NativeDictateLogger.insertion.notice(
                "Direct insertion unavailable after \(String(describing: directStarted.duration(to: .now)), privacy: .public); using clipboard fallback"
            )
            try await clipboard.insert(text, into: target)
        }
    }
}
