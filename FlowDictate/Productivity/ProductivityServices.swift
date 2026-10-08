import Foundation

nonisolated enum UsageStatisticsPeriod: String, CaseIterable, Identifiable, Sendable {
    case total
    case thirtyDays
    case fourteenDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .total: "Total"
        case .thirtyDays: "30 Days"
        case .fourteenDays: "14 Days"
        }
    }

    func startDate(relativeTo now: Date) -> Date? {
        switch self {
        case .total: nil
        case .thirtyDays: now.addingTimeInterval(-30 * 86_400)
        case .fourteenDays: now.addingTimeInterval(-14 * 86_400)
        }
    }
}

nonisolated struct UsageStatistics: Equatable, Sendable {
    var successfulDictations: Int = 0
    var totalDuration: TimeInterval = 0
    var wordCount: Int = 0
    var characterCount: Int = 0
    var retryCount: Int = 0
    var estimatedSecondsSaved: TimeInterval = 0

    var averageWordsPerDictation: Double {
        guard successfulDictations > 0 else { return 0 }
        return Double(wordCount) / Double(successfulDictations)
    }

    var averageDuration: TimeInterval {
        guard successfulDictations > 0 else { return 0 }
        return totalDuration / Double(successfulDictations)
    }

    static func calculate(
        records: [DictationRecord],
        typingWordsPerMinute: Double,
        since: Date? = nil
    ) -> Self {
        let completed = records.filter {
            $0.status == .completed && (since == nil || $0.createdAt >= since!)
        }
        let words = completed.reduce(0) { result, record in
            result + (record.finalText ?? record.originalTranscript ?? "")
                .split(whereSeparator: \.isWhitespace).count
        }
        let duration = completed.reduce(0) { $0 + $1.duration }
        let typingSeconds = Double(words) / max(typingWordsPerMinute, 1) * 60
        return Self(
            successfulDictations: completed.count,
            totalDuration: duration,
            wordCount: words,
            characterCount: completed.reduce(0) {
                $0 + ($1.finalText ?? $1.originalTranscript ?? "").count
            },
            retryCount: completed.reduce(0) { $0 + max($1.attemptCount - 1, 0) },
            estimatedSecondsSaved: max(typingSeconds - duration, 0)
        )
    }
}

nonisolated struct GitHubReleaseInfo: Equatable, Sendable {
    var version: String
    var name: String
    var summary: String
    var pageURL: URL
}

nonisolated enum ReleaseCheckError: LocalizedError {
    case invalidResponse

    var errorDescription: String? { "The NativeDictate release information is unavailable." }
}

nonisolated struct GitHubReleaseChecker: Sendable {
    private struct Payload: Decodable {
        var tag_name: String
        var name: String?
        var body: String?
        var html_url: URL
        var prerelease: Bool
        var draft: Bool
    }

    func latestStableRelease(session: URLSession = .shared) async throws -> GitHubReleaseInfo? {
        let url = URL(string: "https://api.github.com/repos/Hank1210/NativeDictate/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ReleaseCheckError.invalidResponse
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard !payload.prerelease, !payload.draft else { return nil }
        return GitHubReleaseInfo(
            version: payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            name: payload.name ?? payload.tag_name,
            summary: String((payload.body ?? "").prefix(300)),
            pageURL: payload.html_url
        )
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}
