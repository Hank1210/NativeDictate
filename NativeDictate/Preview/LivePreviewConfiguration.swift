import Foundation

nonisolated enum LivePreviewState: Equatable, Sendable {
    case disabled
    case waiting
    case active(String)
    case unavailable(String)
    case failed(String)
}

nonisolated enum LivePreviewEvent: Equatable, Sendable {
    case partial(String)
    case finalSegment(String)
    case unavailable(String)
    case failed(String)
    case finished
}

nonisolated enum OverlaySize: String, CaseIterable, Codable, Identifiable, Sendable {
    case compact
    case standard
    case expanded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .expanded: "Expanded"
        }
    }

    var showsLivePreviewText: Bool {
        self != .compact
    }

    var livePreviewCharacterRange: ClosedRange<Int>? {
        switch self {
        case .compact: nil
        case .standard: 50...200
        case .expanded: 50...800
        }
    }

    func clampedLivePreviewCharacterLimit(_ limit: Int) -> Int {
        guard let livePreviewCharacterRange else { return limit }
        return min(max(limit, livePreviewCharacterRange.lowerBound), livePreviewCharacterRange.upperBound)
    }
}

nonisolated enum OverlayPosition: String, CaseIterable, Codable, Identifiable, Sendable {
    case bottomTrailing
    case bottomCenter
    case menuBarTrailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottomTrailing: "Bottom Right"
        case .bottomCenter: "Bottom Center"
        case .menuBarTrailing: "Top Right"
        }
    }
}

nonisolated struct LivePreviewConfiguration: Equatable, Sendable {
    let localeIdentifier: String
    let characterLimit: Int
}
