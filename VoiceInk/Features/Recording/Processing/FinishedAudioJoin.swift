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
        return TextScript.isLatin(letter)
    }

    private static func endsWithLatinLetter(_ text: String) -> Bool {
        guard let letter = text.unicodeScalars.last(where: isLetter) else { return false }
        return TextScript.isLatin(letter)
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic
    }
}
