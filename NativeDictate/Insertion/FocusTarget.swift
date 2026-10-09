import AppKit
import Foundation

@MainActor
struct FocusTarget {
    let application: NSRunningApplication
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String

    static func capture() -> FocusTarget? {
        guard
            let application = NSWorkspace.shared.frontmostApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return nil
        }

        return FocusTarget(
            application: application,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName ?? "Unknown application"
        )
    }

    static func capture(bundleIdentifier: String?) -> FocusTarget? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        guard let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { !$0.isTerminated }) else { return nil }

        return FocusTarget(
            application: application,
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName ?? "Unknown application"
        )
    }

    var isAvailable: Bool { !application.isTerminated }

    func activate(timeout: Duration = .seconds(2)) async -> Bool {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier {
            return true
        }

        guard !application.isTerminated else { return false }
        application.activate(options: [])

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}
