//
//  NativeDictateApp.swift
//  NativeDictate
//
//  Created by Frank Euler on 16.08.26.
//

import AppKit
import SwiftUI

@main
struct NativeDictateApp: App {
    @StateObject private var coordinator: DictationCoordinator
    #if DEBUG
    @State private var didRunCoreAudioTapLaunchProbe = false
    #endif

    init() {
        let coordinator = DictationCoordinator()
        _coordinator = StateObject(wrappedValue: coordinator)
        #if DEBUG
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                DebugSettingsWindowPresenter.shared.present(coordinator: coordinator)
            }
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            NativeDictateMenu(coordinator: coordinator)
        } label: {
            Image(systemName: coordinator.state.symbolName)
                #if DEBUG
                .onAppear {
                    guard !didRunCoreAudioTapLaunchProbe else { return }
                    let arguments = CommandLine.arguments
                    guard arguments.contains("--run-core-audio-tap-probe")
                            || arguments.contains("--run-core-audio-tap-cycle-probe") else { return }
                    didRunCoreAudioTapLaunchProbe = true
                    if arguments.contains("--run-core-audio-tap-cycle-probe") {
                        coordinator.runCoreAudioTapRepeatedCaptureProbe()
                    } else {
                        coordinator.runCoreAudioTapCaptureProbe()
                    }
                }
                #endif
        }
        .menuBarExtraStyle(.menu)

        Settings {
            NativeDictateSettingsView(coordinator: coordinator)
        }
    }
}

#if DEBUG
@MainActor
private final class DebugSettingsWindowPresenter {
    static let shared = DebugSettingsWindowPresenter()

    private var windowController: NSWindowController?

    func present(coordinator: DictationCoordinator) {
        if let window = windowController?.window {
            positionOnActiveScreen(window)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let content = NativeDictateSettingsView(coordinator: coordinator)
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = "NativeDictate Settings — Test Build"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 720))
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.level = .floating
        window.isReleasedWhenClosed = false
        positionOnActiveScreen(window)
        windowController = NSWindowController(window: window)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func positionOnActiveScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = targetScreen?.visibleFrame else { return }

        let size = window.frame.size
        window.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            )
        )
    }
}
#endif
