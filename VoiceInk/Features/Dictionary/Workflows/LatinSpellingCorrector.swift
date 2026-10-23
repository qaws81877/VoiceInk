import Foundation

/// Fixes close misspellings of Latin vocabulary words in a final transcript.
///
/// This is not a second word-replacement path: word replacement swaps exact
/// user-defined strings in `WordReplacementService.applyReplacements`. This
/// step is fuzzy and its only source is the vocabulary list. It runs after
/// word replacement, and spans produced by a replacement are passed in as
/// `protectedPhrases` so an exact replacement always wins.
///
/// Rules:
/// - Only vocabulary spellings made of Latin letters and digits (joined by a
///   single space, hyphen or period) are sources. Any Hangul disqualifies one.
/// - Only Latin/digit runs of the transcript are compared, so Hangul is never
///   rewritten and a Hangul particle after the spelling stays.
/// - Each span is matched independently; a span becomes a vocabulary spelling
///   only when exactly one spelling is closest and within the length-scaled
///   limit. Weak matches and ties are left unchanged.
/// - Digit runs must match exactly ("GPT-4" never becomes "GPT-4o").
enum LatinSpellingCorrector {
    static func correct(_ text: String, vocabulary: [String], protectedPhrases: [String]) -> String {
        let sources = vocabulary.compactMap(Source.init(spelling:))
        guard !sources.isEmpty, !text.isEmpty else { return text }

        let tokens = latinTokens(in: text)
        guard !tokens.isEmpty else { return text }

        let protectedRanges = ranges(of: protectedPhrases, in: text)
        let maxParts = sources.map(\.partCount).max() ?? 1
        let maxWindow = min(maxParts + 1, 4)

        var picks: [Pick] = []
        for start in tokens.indices {
            for length in 1...maxWindow {
                let end = start + length - 1
                guard end < tokens.count else { break }
                if length > 1, !isJoiner(text[tokens[end - 1].range.upperBound..<tokens[end].range.lowerBound]) {
                    break
                }
                let range = tokens[start].range.lowerBound..<tokens[end].range.upperBound
                if protectedRanges.contains(where: { $0.overlaps(range) }) { continue }

                let key = tokens[start...end].map(\.key).joined()
                guard let match = bestMatch(key: key, partCount: length, sources: sources) else { continue }
                let original = String(text[range])
                let replacement = match.isTie || match.spelling == original ? nil : match.spelling
                picks.append(
                    Pick(
                        firstToken: start,
                        lastToken: end,
                        range: range,
                        distance: match.distance,
                        replacement: replacement
                    )
                )
            }
        }

        // Closest first, then the longer span, then the earlier span. An exact
        // or tied span is kept as-is but still claims its tokens.
        let ordered = picks.sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            let leftLength = $0.lastToken - $0.firstToken
            let rightLength = $1.lastToken - $1.firstToken
            if leftLength != rightLength { return leftLength > rightLength }
            return $0.firstToken < $1.firstToken
        }
        var claimed = IndexSet()
        var edits: [(range: Range<String.Index>, replacement: String)] = []
        for pick in ordered {
            let tokenRange = pick.firstToken...pick.lastToken
            guard !tokenRange.contains(where: claimed.contains) else { continue }
            claimed.insert(integersIn: tokenRange)
            if let replacement = pick.replacement {
                edits.append((pick.range, replacement))
            }
        }

        guard !edits.isEmpty else { return text }
        var result = text
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceSubrange(edit.range, with: edit.replacement)
        }
        return result
    }

    /// True when the text contains a Hangul syllable or Jamo in any block,
    /// including decomposed (NFD) and compatibility forms.
    static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            hangulRanges.contains { $0.contains(scalar.value) }
        }
    }

    // MARK: - Matching

    private struct Source {
        let spelling: String
        let key: [Character]
        let shape: [Run]
        let partCount: Int
        let limit: Int

        init?(spelling raw: String) {
            let spelling = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
            guard !spelling.isEmpty, !LatinSpellingCorrector.containsHangul(spelling) else { return nil }

            let tokens = LatinSpellingCorrector.latinTokens(in: spelling)
            guard let first = tokens.first, let last = tokens.last,
                first.range.lowerBound == spelling.startIndex,
                last.range.upperBound == spelling.endIndex
            else { return nil }
            for (left, right) in zip(tokens, tokens.dropFirst())
            where !LatinSpellingCorrector.isJoiner(spelling[left.range.upperBound..<right.range.lowerBound]) {
                return nil
            }

            let key = tokens.map(\.key).joined()
            guard key.contains(where: \.isLetter), key.count >= 3 else { return nil }

            self.spelling = spelling
            self.key = Array(key)
            self.shape = LatinSpellingCorrector.shape(of: key)
            self.partCount = tokens.count
            self.limit = LatinSpellingCorrector.editLimit(forKeyLength: key.count)
        }
    }

    private struct Match {
        let spelling: String
        let distance: Int
        let isTie: Bool
    }

    private struct Pick {
        let firstToken: Int
        let lastToken: Int
        let range: Range<String.Index>
        let distance: Int
        let replacement: String?
    }

    private struct Token {
        let range: Range<String.Index>
        let key: String
    }

    private struct Run: Equatable {
        let isDigit: Bool
        let digits: String
    }

    private static func bestMatch(key: String, partCount: Int, sources: [Source]) -> Match? {
        let keyCharacters = Array(key)
        let keyShape = shape(of: key)
        var best: (spelling: String, distance: Int)?
        var isTie = false

        for source in sources where abs(source.partCount - partCount) <= 1 {
            guard abs(source.key.count - keyCharacters.count) <= source.limit,
                source.shape == keyShape
            else { continue }
            let distance = editDistance(keyCharacters, source.key)
            // A span with more words than the spelling may only differ by case
            // or separators, so a neighbouring word is never swallowed.
            let limit = partCount > source.partCount ? 0 : source.limit
            guard distance <= limit else { continue }

            if let current = best {
                if distance < current.distance {
                    best = (source.spelling, distance)
                    isTie = false
                } else if distance == current.distance, source.spelling != current.spelling {
                    isTie = true
                }
            } else {
                best = (source.spelling, distance)
            }
        }

        return best.map { Match(spelling: $0.spelling, distance: $0.distance, isTie: isTie) }
    }

    /// Case and separator differences cost nothing. Short spellings allow no
    /// letter edits, so ordinary short words are not pulled toward them.
    private static func editLimit(forKeyLength length: Int) -> Int {
        switch length {
        case ..<5: return 0
        case 5...8: return 1
        default: return 2
        }
    }

    /// Letter runs are compared fuzzily; digit runs must be identical.
    private static func shape(of key: String) -> [Run] {
        var runs: [Run] = []
        for character in key {
            let isDigit = character.isNumber
            if let last = runs.last, last.isDigit == isDigit {
                runs[runs.count - 1] = Run(isDigit: isDigit, digits: isDigit ? last.digits + String(character) : "")
            } else {
                runs.append(Run(isDigit: isDigit, digits: isDigit ? String(character) : ""))
            }
        }
        return runs
    }

    /// Optimal string alignment distance (adjacent transposition costs 1).
    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previousPrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, previousPrevious[j - 2] + 1)
                }
                current[j] = value
            }
            previousPrevious = previous
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Text scanning

    private static let hangulRanges: [ClosedRange<UInt32>] = [
        0x1100...0x11FF,  // Hangul Jamo
        0x302E...0x302F,  // Hangul tone marks
        0x3130...0x318F,  // Hangul Compatibility Jamo
        0x3200...0x321E,  // Parenthesized Hangul
        0x3260...0x327E,  // Circled Hangul
        0xA960...0xA97F,  // Hangul Jamo Extended-A
        0xAC00...0xD7AF,  // Hangul Syllables
        0xD7B0...0xD7FF,  // Hangul Jamo Extended-B
        0xFFA0...0xFFDC,  // Halfwidth Hangul
    ]

    /// A token is a run of Latin letters and decimal digits, with their
    /// non-Hangul combining marks.
    private static let tokenRegex: NSRegularExpression = {
        let unit = "[\\p{scx=Latin}\\p{Nd}][[\\p{M}]-[\\p{scx=Hangul}]]*"
        // The pattern is a compile-time constant.
        return try! NSRegularExpression(pattern: "(?:\(unit))+")
    }()

    private static func latinTokens(in text: String) -> [Token] {
        let fullRange = NSRange(text.startIndex..., in: text)
        return tokenRegex.matches(in: text, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let key = String(text[range])
                .precomposedStringWithCanonicalMapping
                .lowercased()
                .filter { $0.isLetter || $0.isNumber }
            return key.isEmpty ? nil : Token(range: range, key: key)
        }
    }

    private static func isJoiner(_ separator: Substring) -> Bool {
        separator == " " || separator == "-" || separator == "."
    }

    private static func ranges(of phrases: [String], in text: String) -> [Range<String.Index>] {
        phrases.flatMap { raw -> [Range<String.Index>] in
            let phrase = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { return [] }
            var found: [Range<String.Index>] = []
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                let range = text.range(of: phrase, range: searchStart..<text.endIndex)
            {
                found.append(range)
                searchStart = range.upperBound
            }
            return found
        }
    }
}
