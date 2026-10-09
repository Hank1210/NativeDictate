import Foundation

nonisolated struct PersonalDictionaryProcessor: Sendable {
    func process(
        _ text: String,
        entries: [DictionaryEntry],
        language: String?
    ) -> TextTransformationResult {
        let applicable = entries
            .filter { entry in
                entry.isEnabled && (entry.language == nil || language == nil || entry.language == language)
            }
            .sorted {
                if $0.spokenForm.count == $1.spokenForm.count {
                    return $0.createdAt < $1.createdAt
                }
                return $0.spokenForm.count > $1.spokenForm.count
            }

        var working = text
        var protected: [String: String] = [:]
        var replacementCount = 0

        for entry in applicable {
            let escaped = NSRegularExpression.escapedPattern(for: entry.spokenForm)
            let pattern = entry.matchWholeWordsOnly
                ? "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
                : escaped
            let options: NSRegularExpression.Options = entry.caseSensitive ? [] : [.caseInsensitive]
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { continue }
            let range = NSRange(working.startIndex..., in: working)
            let matches = expression.matches(in: working, range: range).reversed()
            for match in matches {
                guard let swiftRange = Range(match.range, in: working) else { continue }
                let placeholder = "\u{E100}\(protected.count)\u{E101}"
                protected[placeholder] = entry.replacement
                working.replaceSubrange(swiftRange, with: placeholder)
                replacementCount += 1
            }
        }

        for (placeholder, replacement) in protected {
            working = working.replacingOccurrences(of: placeholder, with: replacement)
        }
        return TextTransformationResult(text: working, replacementCount: replacementCount)
    }
}
