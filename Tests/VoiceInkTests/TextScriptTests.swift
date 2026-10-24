import XCTest

@testable import VoiceInk

final class TextScriptTests: XCTestCase {
    /// The Latin table must match ICU's `\p{scx=Latin}`, which LatinSpellingCorrector used before.
    func testLatinMatchesICUScriptExtensions() throws {
        let regex = try NSRegularExpression(pattern: "^\\p{scx=Latin}$")
        var mismatches: [String] = []
        for value in UInt32(0)...0x1_FFFF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let text = String(Character(scalar))
            let icu = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            if icu != TextScript.isLatin(scalar) {
                mismatches.append(String(value, radix: 16))
            }
        }
        XCTAssertEqual(mismatches, [])
    }

    func testHangulCoversSyllablesJamoCompatibilityAndExtendedBlocks() {
        for value: UInt32 in [0xAC00, 0xD7A3, 0x1100, 0x11FF, 0x3131, 0x318E, 0xA960, 0xD7B0, 0xD7FB] {
            XCTAssertTrue(TextScript.isHangul(Unicode.Scalar(value)!), String(value, radix: 16))
        }
        for scalar in "Az09.가".unicodeScalars.dropLast() {
            XCTAssertFalse(TextScript.isHangul(scalar), "\(scalar)")
        }
    }

    func testHangulIsFoundInDecomposedText() {
        let decomposed = "한국".decomposedStringWithCanonicalMapping
        XCTAssertFalse(decomposed.unicodeScalars.contains { (0xAC00...0xD7AF).contains($0.value) })
        XCTAssertTrue(TextScript.containsHangul(decomposed))
        XCTAssertFalse(TextScript.containsHangul("Claude 3.5"))
    }
}
