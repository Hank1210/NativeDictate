import Carbon.HIToolbox
import Foundation

struct HotKeyConfiguration: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let optionSpace = HotKeyConfiguration(
        id: "option-space",
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        displayName: "Option + Space"
    )

    static let controlSpace = HotKeyConfiguration(
        id: "control-space",
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey),
        displayName: "Control + Space"
    )

    static let optionD = HotKeyConfiguration(
        id: "option-d",
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(optionKey),
        displayName: "Option + D"
    )

    static let optionShiftSpace = HotKeyConfiguration(
        id: "option-shift-space",
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey | shiftKey),
        displayName: "Option + Shift + Space"
    )

    static let controlShiftSpace = HotKeyConfiguration(
        id: "control-shift-space",
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | shiftKey),
        displayName: "Control + Shift + Space"
    )

    static let optionShiftD = HotKeyConfiguration(
        id: "option-shift-d",
        keyCode: UInt32(kVK_ANSI_D),
        modifiers: UInt32(optionKey | shiftKey),
        displayName: "Option + Shift + D"
    )

    static let optionShiftZ = HotKeyConfiguration(
        id: "option-shift-z",
        keyCode: keyCode(for: "z", fallback: UInt32(kVK_ANSI_Z)),
        modifiers: UInt32(optionKey | shiftKey),
        displayName: "Option + Shift + Z"
    )

    static let controlShiftZ = HotKeyConfiguration(
        id: "control-shift-z",
        keyCode: keyCode(for: "z", fallback: UInt32(kVK_ANSI_Z)),
        modifiers: UInt32(controlKey | shiftKey),
        displayName: "Control + Shift + Z"
    )

    static let dictationPresets = [optionSpace, controlSpace, optionD]
    static let cancelPresets = [optionShiftSpace, controlShiftSpace, optionShiftD]
    static let restorePresets = [optionShiftZ, controlShiftZ]

    static func normalizedRestorePreset(_ saved: Self?) -> Self {
        switch saved?.id {
        case optionShiftZ.id: optionShiftZ
        case controlShiftZ.id: controlShiftZ
        default: saved ?? optionShiftZ
        }
    }

    private static func keyCode(for character: String, fallback: UInt32) -> UInt32 {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return fallback
        }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return fallback }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        for keyCode in UInt16(0)..<UInt16(128) {
            var deadKeyState: UInt32 = 0
            var length = 0
            var output = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, output.count, &length, &output
            )
            if status == noErr,
               String(utf16CodeUnits: output, count: length).lowercased() == character {
                return UInt32(keyCode)
            }
        }
        return fallback
    }

    static func custom(keyCode: UInt32, modifiers: UInt32, keyName: String) -> Self {
        let modifierName = [
            (UInt32(controlKey), "Control"),
            (UInt32(optionKey), "Option"),
            (UInt32(shiftKey), "Shift"),
            (UInt32(cmdKey), "Command")
        ]
        .compactMap { mask, name in modifiers & mask != 0 ? name : nil }
        .joined(separator: " + ")
        let displayName = modifierName.isEmpty ? keyName : "\(modifierName) + \(keyName)"
        return HotKeyConfiguration(
            id: "custom-\(keyCode)-\(modifiers)",
            keyCode: keyCode,
            modifiers: modifiers,
            displayName: displayName
        )
    }
}
