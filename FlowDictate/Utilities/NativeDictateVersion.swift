import Foundation

enum NativeDictateVersion {
    nonisolated static let onboardingSchema = 2
    nonisolated static let historySchema = 7
    nonisolated static let dictationRecordSchema = 7

    static var displayString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version) (\(build))"
    }
}
