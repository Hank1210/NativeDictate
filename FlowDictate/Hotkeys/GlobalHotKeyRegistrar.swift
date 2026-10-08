import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog

enum HotKeyRegistrationError: LocalizedError {
    case installationFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .installationFailed(status):
            "Could not install the global hotkey handler (\(status))."
        case let .registrationFailed(status):
            "The selected global hotkey could not be registered (\(status)). It may already be in use."
        }
    }
}

@MainActor
protocol HotKeyRegistering: AnyObject {
    func register(
        _ configuration: HotKeyConfiguration,
        pressed: @escaping @MainActor () -> Void,
        released: @escaping @MainActor () -> Void
    ) throws
    func unregister()
}

extension HotKeyRegistering {
    func register(
        _ configuration: HotKeyConfiguration,
        handler: @escaping @MainActor () -> Void
    ) throws {
        try register(configuration, pressed: handler, released: {})
    }
}

@MainActor
final class DisabledHotKeyRegistrar: HotKeyRegistering {
    func register(
        _ configuration: HotKeyConfiguration,
        pressed: @escaping @MainActor () -> Void,
        released: @escaping @MainActor () -> Void
    ) throws {}

    func unregister() {}
}

@MainActor
final class GlobalHotKeyRegistrar: HotKeyRegistering {
    nonisolated private static let signature: OSType = 0x464C4F57 // "FLOW"

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var globalFallbackMonitor: Any?
    private var localFallbackMonitor: Any?
    private var handler: (@MainActor () -> Void)?
    private var releaseHandler: (@MainActor () -> Void)?
    private var monitoredConfiguration: HotKeyConfiguration?
    private var lastPressDelivery = Date.distantPast
    private var lastReleaseDelivery = Date.distantPast
    private let registrationID: UInt32

    init(registrationID: UInt32 = 1) {
        self.registrationID = registrationID
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let globalFallbackMonitor {
            NSEvent.removeMonitor(globalFallbackMonitor)
        }
        if let localFallbackMonitor {
            NSEvent.removeMonitor(localFallbackMonitor)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(
        _ configuration: HotKeyConfiguration,
        handler: @escaping @MainActor () -> Void
    ) throws {
        try register(configuration, pressed: handler, released: {})
    }

    func register(
        _ configuration: HotKeyConfiguration,
        pressed: @escaping @MainActor () -> Void,
        released: @escaping @MainActor () -> Void
    ) throws {
        unregister()
        self.handler = pressed
        releaseHandler = released
        monitoredConfiguration = configuration

        if eventHandlerRef == nil {
            var eventTypes = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            ]
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                Self.eventCallback,
                eventTypes.count,
                &eventTypes,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
            guard status == noErr else {
                throw HotKeyRegistrationError.installationFailed(status)
            }
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: registrationID)
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKeyRef
        )
        guard status == noErr else {
            throw HotKeyRegistrationError.registrationFailed(status)
        }

        installFallbackMonitors()
        NativeDictateLogger.hotkey.info("Registered hotkey: \(configuration.displayName, privacy: .public)")
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let globalFallbackMonitor {
            NSEvent.removeMonitor(globalFallbackMonitor)
            self.globalFallbackMonitor = nil
        }
        if let localFallbackMonitor {
            NSEvent.removeMonitor(localFallbackMonitor)
            self.localFallbackMonitor = nil
        }
        monitoredConfiguration = nil
    }

    private func invokeHandler(released: Bool, source: String = "Carbon") {
        let now = Date()
        let lastDelivery = released ? lastReleaseDelivery : lastPressDelivery
        guard now.timeIntervalSince(lastDelivery) >= 0.08 else {
            NativeDictateLogger.hotkey.debug(
                "Deduplicated \(released ? "release" : "press", privacy: .public) from \(source, privacy: .public)"
            )
            return
        }
        if released { lastReleaseDelivery = now } else { lastPressDelivery = now }
        NativeDictateLogger.hotkey.debug(
            "Delivered \(released ? "release" : "press", privacy: .public) from \(source, privacy: .public)"
        )
        if released { releaseHandler?() } else { handler?() }
    }

    private func installFallbackMonitors() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp]
        globalFallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            guard !event.isARepeat else { return }
            let keyCode = UInt32(event.keyCode)
            let modifiers = event.modifierFlags
            let released = event.type == .keyUp
            Task { @MainActor [weak self] in
                self?.handleFallbackEvent(keyCode: keyCode, modifiers: modifiers, released: released)
            }
        }
        localFallbackMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard !event.isARepeat else { return event }
            let keyCode = UInt32(event.keyCode)
            let modifiers = event.modifierFlags
            let released = event.type == .keyUp
            Task { @MainActor [weak self] in
                self?.handleFallbackEvent(keyCode: keyCode, modifiers: modifiers, released: released)
            }
            return event
        }
    }

    private func handleFallbackEvent(
        keyCode: UInt32,
        modifiers: NSEvent.ModifierFlags,
        released: Bool
    ) {
        guard let configuration = monitoredConfiguration,
              keyCode == configuration.keyCode,
              normalizedModifiers(modifiers) == expectedModifiers(configuration.modifiers) else {
            return
        }
        invokeHandler(released: released, source: "NSEvent fallback")
    }

    private func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .control, .option, .shift])
    }

    private func expectedModifiers(_ carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { result.insert(.command) }
        if carbonModifiers & UInt32(controlKey) != 0 { result.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { result.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { result.insert(.shift) }
        return result
    }

    private nonisolated static let eventCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        let registrar = Unmanaged<GlobalHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
        guard
            status == noErr,
            hotKeyID.signature == signature,
            hotKeyID.id == registrar.registrationID
        else {
            return OSStatus(eventNotHandledErr)
        }

        MainActor.assumeIsolated {
            registrar.invokeHandler(released: GetEventKind(event) == UInt32(kEventHotKeyReleased))
        }
        return noErr
    }
}
