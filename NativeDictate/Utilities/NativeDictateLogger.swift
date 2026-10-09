import Foundation
import OSLog

enum NativeDictateLogger {
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "NativeDictate"

    nonisolated static let app = Logger(subsystem: subsystem, category: "app")
    nonisolated static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    nonisolated static let audio = Logger(subsystem: subsystem, category: "audio")
    nonisolated static let transcription = Logger(subsystem: subsystem, category: "transcription")
    nonisolated static let insertion = Logger(subsystem: subsystem, category: "insertion")
    nonisolated static let meetingSignposter = OSSignposter(
        subsystem: subsystem,
        category: "meeting-performance"
    )
    nonisolated static let transcriptionSignposter = OSSignposter(
        subsystem: subsystem,
        category: "transcription-performance"
    )
}
