import Foundation

nonisolated struct TranscriptionPromptBuilder: Sendable {
    let characterLimit: Int

    init(characterLimit: Int = LongFormConfiguration.default.promptCharacterLimit) {
        self.characterLimit = max(characterLimit, 0)
    }

    func prompt(previousTranscript: String?) -> String? {
        guard characterLimit > 0,
              let value = previousTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        let suffix = value.suffix(characterLimit)
        let cleaned = suffix
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

nonisolated struct PartialTranscriptMerger: Sendable {
    static let algorithmVersion = 1

    var maximumBoundaryWords = 40
    var minimumMatchingWords = 3
    var minimumMatchingCharacters = 16

    func merge(_ segments: [TranscriptionSegment]) throws -> String {
        guard !segments.isEmpty,
              segments.enumerated().allSatisfy({ $0.offset == $0.element.index }),
              segments.allSatisfy({
                  ($0.status == .succeeded
                      && $0.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                    || ($0.status == .silent
                        && $0.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
              }) else {
            throw LongFormTranscriptionError.transcriptMergeFailed
        }
        var result = ""
        var previousWasSilent = false
        for segment in segments {
            guard segment.status == .succeeded else {
                previousWasSilent = true
                continue
            }
            let next = segment.transcript!.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isEmpty {
                result = next
            } else if previousWasSilent {
                result += " " + next
            } else {
                result = mergeBoundary(left: result, right: next)
            }
            previousWasSilent = false
        }
        return result
    }

    func mergeBoundary(left: String, right: String) -> String {
        let leftWords = words(in: left)
        let rightWords = words(in: right)
        let maximum = min(maximumBoundaryWords, leftWords.count, rightWords.count)
        var matchedCount = 0
        if maximum >= minimumMatchingWords {
            for count in stride(from: maximum, through: minimumMatchingWords, by: -1) {
                let suffix = leftWords.suffix(count).map(\.normalized)
                let prefix = rightWords.prefix(count).map(\.normalized)
                let characterCount = suffix.reduce(0) { $0 + $1.count }
                if suffix == prefix, characterCount >= minimumMatchingCharacters {
                    matchedCount = count
                    break
                }
            }
        }

        let remainder: String
        if matchedCount > 0 {
            let matched = rightWords[matchedCount - 1]
            var index = matched.range.upperBound
            while index < right.endIndex, right[index].isWhitespace {
                index = right.index(after: index)
            }
            if index < right.endIndex, left.last == right[index] {
                index = right.index(after: index)
                while index < right.endIndex, right[index].isWhitespace {
                    index = right.index(after: index)
                }
            }
            remainder = String(right[index...])
        } else {
            remainder = right
        }
        guard !remainder.isEmpty else { return left }
        let separator = left.last?.isWhitespace == true ? "" : " "
        return left + separator + remainder
    }

    private func words(in text: String) -> [(normalized: String, range: Range<String.Index>)] {
        var result: [(String, Range<String.Index>)] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords]) {
            substring, range, _, _ in
            guard let substring else { return }
            let normalized = substring
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            if !normalized.isEmpty { result.append((normalized, range)) }
        }
        return result
    }
}
