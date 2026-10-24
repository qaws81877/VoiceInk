import Foundation

/// Joins the recognized pieces of one finished recording.
///
/// Pieces stay in order and are trimmed; empty pieces are dropped. One space goes between two pieces
/// only when both sides are Latin, judged by the nearest letter at the boundary (whitespace,
/// punctuation and digits are skipped). Nothing else is inserted.
enum FinishedAudioJoin {
    static func join(_ pieces: [String]) -> String {
        let texts = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result = ""
        var previous: String?
        for text in texts {
            if let previous, endsWithLatinLetter(previous), startsWithLatinLetter(text) {
                result.append(" ")
            }
            result.append(text)
            previous = text
        }
        return result
    }

    private static func startsWithLatinLetter(_ text: String) -> Bool {
        guard let letter = text.unicodeScalars.first(where: isLetter) else { return false }
        return LatinScript.contains(letter)
    }

    private static func endsWithLatinLetter(_ text: String) -> Bool {
        guard let letter = text.unicodeScalars.last(where: isLetter) else { return false }
        return LatinScript.contains(letter)
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic
    }
}

/// Unicode blocks that hold Latin-script letters.
enum LatinScript {
    private static let ranges: [ClosedRange<UInt32>] = [
        0x0041...0x005A,  // A-Z
        0x0061...0x007A,  // a-z
        0x00AA...0x00AA, 0x00BA...0x00BA,  // ordinal indicators
        0x00C0...0x00D6, 0x00D8...0x00F6, 0x00F8...0x024F,  // Latin-1 letters, Extended-A/B
        0x0250...0x02AF,  // IPA extensions
        0x1D00...0x1D7F,  // phonetic extensions
        0x1E00...0x1EFF,  // Latin Extended Additional
        0x2C60...0x2C7F,  // Latin Extended-C
        0xA720...0xA7FF,  // Latin Extended-D
        0xAB30...0xAB6F,  // Latin Extended-E
        0xFF21...0xFF3A, 0xFF41...0xFF5A,  // fullwidth A-Z, a-z
    ]

    static func contains(_ scalar: Unicode.Scalar) -> Bool {
        ranges.contains { $0.contains(scalar.value) }
    }
}
