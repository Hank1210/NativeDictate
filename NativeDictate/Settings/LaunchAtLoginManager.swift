import AppKit
import Combine
import Foundation
import OSLog
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isEnabled: Bool { self == .enabled }

    var message: String? {
        switch self {
        case .disabled, .enabled:
            nil
        case .requiresApproval:
            "Allow NativeDictate under System Settings → General → Login Items."
        case .unavailable:
            "Launch at login is unavailable for this build. Install and sign the app consistently."
        }
    }

    init(serviceStatus: SMAppService.Status) {
        switch serviceStatus {
        case .notRegistered: self = .disabled
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .unavailable
        @unknown default: self = .unavailable
        }
    }
}

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    private static let configuredDefaultsKey = "hasConfiguredLaunchAtLogin"

    @Published private(set) var state: LaunchAtLoginState = .disabled
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults

    var isEnabled: Bool { state.isEnabled }
    var statusMessage: String? { state.message }

    init(
        defaults: UserDefaults = .standard,
        automaticallyEnableOnFirstLaunch: Bool = true
    ) {
        self.defaults = defaults
        refresh()
        let hasConfiguredPreference = defaults.object(forKey: Self.configuredDefaultsKey) != nil
        if automaticallyEnableOnFirstLaunch,
           (!hasConfiguredPreference || state == .unavailable),
           state != .enabled,
           state != .requiresApproval {
            defaults.set(true, forKey: Self.configuredDefaultsKey)
            setEnabled(true)
        }
    }

    func refresh() {
        state = LaunchAtLoginState(serviceStatus: SMAppService.mainApp.status)
        NativeDictateLogger.app.info("Launch at login status: \(String(describing: self.state), privacy: .public)")
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: Self.configuredDefaultsKey)
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
            refresh()
            NativeDictateLogger.app.info("Launch at login preference updated")
        } catch {
            errorMessage = error.localizedDescription
            refresh()
            NativeDictateLogger.app.error(
                "Launch at login update failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func openLoginItemsSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
