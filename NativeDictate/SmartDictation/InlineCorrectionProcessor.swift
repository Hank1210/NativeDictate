import Foundation

nonisolated struct InlineCorrectionResult: Equatable, Sendable {
    var text: String
    var summary: CorrectionSummary
}

nonisolated struct InlineCorrectionProcessor: Sendable {
    private enum CommandKind {
        case replace(sourceGroup: Int, targetGroup: Int, all: Bool)
        case deleteLastWord
        case deleteLastSentence
        case undo
    }

    private struct CommandPattern {
        let expression: NSRegularExpression
        let kind: CommandKind
    }

    func process(
        _ input: String,
        language: String?,
        protectedTerms: [String] = []
    ) -> InlineCorrectionResult {
        let patterns = commandPatterns(language: language)
        var remaining = input
        var output = ""
        var undoStack: [String] = []
        var applied = 0
        var ignored = 0
        var undone = 0

        while let match = earliestMatch(in: remaining, patterns: patterns) {
            let prefixRange = NSRange(location: 0, length: match.result.range.location)
            let prefix = substring(remaining, range: prefixRange)
            let commandText = substring(remaining, range: match.result.range)

            if let escapedPrefix = stripLiteralEscape(from: prefix) {
                output += escapedPrefix + commandText
            } else {
                output += prefix
                let before = output
                let changed: Bool
                switch match.pattern.kind {
                case let .replace(sourceGroup, targetGroup, all):
                    let source = capture(remaining, match: match.result, group: sourceGroup)
                    let target = capture(remaining, match: match.result, group: targetGroup)
                    if let source, let target,
                       !source.isEmpty, !target.isEmpty,
                       let replaced = replace(
                           source,
                           with: target,
                           in: output,
                           replaceAll: all,
                           protectedTerms: protectedTerms
                       ) {
                        output = replaced
                        changed = true
                    } else {
                        output += commandText
                        ignored += 1
                        changed = false
                    }
                case .deleteLastWord:
                    let modified = deletingLastWord(in: output)
                    changed = modified != output
                    output = modified
                case .deleteLastSentence:
                    let modified = deletingLastSentence(in: output)
                    changed = modified != output
                    output = modified
                case .undo:
                    if let previous = undoStack.popLast() {
                        output = previous
                        undone += 1
                        changed = false
                    } else {
                        output += commandText
                        ignored += 1
                        changed = false
                    }
                }
                if changed {
                    undoStack.append(before)
                    applied += 1
                }
            }

            let consumed = match.result.range.location + match.result.range.length
            remaining = substring(
                remaining,
                range: NSRange(
                    location: consumed,
                    length: (remaining as NSString).length - consumed
                )
            )
        }
        output += remaining
        return InlineCorrectionResult(
            text: normalizeWhitespace(output),
            summary: CorrectionSummary(
                appliedCount: applied,
                ignoredAmbiguousCount: ignored,
                undoneCount: undone
            )
        )
    }

    private func commandPatterns(language: String?) -> [CommandPattern] {
        let german = language == nil || language == "de"
        let english = language == nil || language == "en"
        var values: [(String, CommandKind)] = []
        if german {
            values += [
                (#"\bersetze\s+alle\s+(.+?)\s+durch\s+(.+?)(?=[.!?](?:\s|$)|$)[.!?]?"#, .replace(sourceGroup: 1, targetGroup: 2, all: true)),
                (#"\bersetze\s+(.+?)\s+durch\s+(.+?)(?=[.!?](?:\s|$)|$)[.!?]?"#, .replace(sourceGroup: 1, targetGroup: 2, all: false)),
                (#"\blösche\s+das\s+letzte\s+wort\b"#, .deleteLastWord),
                (#"\blösche\s+den\s+letzten\s+satz\b"#, .deleteLastSentence),
                (#"\bwiderrufe\s+die\s+letzte\s+korrektur\b"#, .undo)
            ]
        }
        if english {
            values += [
                (#"\breplace\s+all\s+(.+?)\s+with\s+(.+?)(?=[.!?](?:\s|$)|$)[.!?]?"#, .replace(sourceGroup: 1, targetGroup: 2, all: true)),
                (#"\breplace\s+(.+?)\s+with\s+(.+?)(?=[.!?](?:\s|$)|$)[.!?]?"#, .replace(sourceGroup: 1, targetGroup: 2, all: false)),
                (#"\bdelete\s+the\s+last\s+word\b"#, .deleteLastWord),
                (#"\bdelete\s+the\s+last\s+sentence\b"#, .deleteLastSentence),
                (#"\bundo\s+the\s+last\s+correction\b"#, .undo)
            ]
        }
        return values.compactMap { pattern, kind in
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { return nil }
            return CommandPattern(expression: expression, kind: kind)
        }
    }

    private func earliestMatch(
        in text: String,
        patterns: [CommandPattern]
    ) -> (pattern: CommandPattern, result: NSTextCheckingResult)? {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return patterns.compactMap { pattern in
            pattern.expression.firstMatch(in: text, range: range).map { (pattern, $0) }
        }.min { lhs, rhs in lhs.1.range.location < rhs.1.range.location }
    }

    private func stripLiteralEscape(from prefix: String) -> String? {
        let expression = try! NSRegularExpression(
            pattern: #"(?i)(?:wörtlich|literal)\s+$"#
        )
        let full = NSRange(location: 0, length: (prefix as NSString).length)
        guard let match = expression.firstMatch(in: prefix, range: full),
              match.range.location + match.range.length == full.length else { return nil }
        return (prefix as NSString).replacingCharacters(in: match.range, with: "")
    }

    private func replace(
        _ source: String,
        with target: String,
        in text: String,
        replaceAll: Bool,
        protectedTerms: [String]
    ) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: source.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !escaped.isEmpty,
              let expression = try? NSRegularExpression(
                pattern: "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])",
                options: [.caseInsensitive]
              ) else { return nil }
        let protected = protectedRanges(in: text, terms: protectedTerms)
        let full = NSRange(location: 0, length: (text as NSString).length)
        let candidates = expression.matches(in: text, range: full).filter { candidate in
            !protected.contains { NSIntersectionRange($0, candidate.range).length > 0 }
        }
        guard !candidates.isEmpty else { return nil }
        let selected = replaceAll ? candidates : [candidates.last!]
        let mutable = NSMutableString(string: text)
        for match in selected.reversed() {
            mutable.replaceCharacters(in: match.range, with: target.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return mutable as String
    }

    private func protectedRanges(in text: String, terms: [String]) -> [NSRange] {
        let pattern = #"(?i)\b(?:https?://|www\.)\S+|\b[\w.%+-]+@[\w.-]+\.[A-Z]{2,}\b"#
        let expression = try! NSRegularExpression(pattern: pattern)
        var ranges = expression.matches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        ).map(\.range)
        let full = NSRange(location: 0, length: (text as NSString).length)
        for term in terms {
            let escaped = NSRegularExpression.escapedPattern(
                for: term.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard !escaped.isEmpty,
                  let termExpression = try? NSRegularExpression(
                    pattern: "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])",
                    options: [.caseInsensitive]
                  ) else { continue }
            ranges += termExpression.matches(in: text, range: full).map(\.range)
        }
        return ranges
    }

    private func deletingLastWord(in text: String) -> String {
        text.replacingOccurrences(
            of: #"\s*\S+\s*$"#,
            with: "",
            options: .regularExpression
        )
    }

    private func deletingLastSentence(in text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        let body = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        let ns = body as NSString
        let expression = try! NSRegularExpression(pattern: #"[.!?]\s+"#)
        let matches = expression.matches(
            in: body,
            range: NSRange(location: 0, length: ns.length)
        )
        guard let boundary = matches.last else { return "" }
        return ns.substring(to: boundary.range.location + 1)
    }

    private func capture(
        _ text: String,
        match: NSTextCheckingResult,
        group: Int
    ) -> String? {
        guard group < match.numberOfRanges, match.range(at: group).location != NSNotFound else {
            return nil
        }
        return substring(text, range: match.range(at: group))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func substring(_ text: String, range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([.!?,;:])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
