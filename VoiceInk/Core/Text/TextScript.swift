import Foundation

/// The one Latin/Hangul classifier shared by dictionary correction, word replacement and the
/// finished-audio join, so the features cannot disagree about which script a character belongs to.
/// Works per Unicode scalar, so decomposed (NFD) text is classified like composed text.
enum TextScript {
    /// Scalars whose Script_Extensions include Latin (ICU `\p{scx=Latin}`): letters, plus the marks,
    /// modifiers and punctuation Unicode assigns to Latin. Pinned against ICU by `TextScriptTests`.
    static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        latinRanges.contains { $0.contains(scalar.value) }
    }

    /// Hangul syllables and Jamo in every block (conjoining, compatibility, extended A/B, halfwidth),
    /// plus tone marks and parenthesized/circled Hangul.
    static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        hangulRanges.contains { $0.contains(scalar.value) }
    }

    static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isHangul)
    }

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

    // Generated from ICU `\p{scx=Latin}` (macOS 27); ascending, non-overlapping.
    private static let latinRanges: [ClosedRange<UInt32>] = [
        0x0041...0x005A, 0x0061...0x007A, 0x00AA...0x00AA, 0x00B7...0x00B7, 0x00BA...0x00BA,
        0x00C0...0x00D6, 0x00D8...0x00F6, 0x00F8...0x02B8, 0x02BC...0x02BC, 0x02C7...0x02C7,
        0x02C9...0x02CB, 0x02CD...0x02CD, 0x02D7...0x02D7, 0x02D9...0x02D9, 0x02E0...0x02E4,
        0x0300...0x030E, 0x0310...0x0311, 0x0313...0x0313, 0x0323...0x0325, 0x032D...0x032E,
        0x0330...0x0331, 0x0358...0x0358, 0x035E...0x035E, 0x0363...0x036F, 0x0485...0x0486,
        0x0951...0x0952, 0x10FB...0x10FB, 0x1D00...0x1D25, 0x1D2C...0x1D5C, 0x1D62...0x1D65,
        0x1D6B...0x1D77, 0x1D79...0x1DBE, 0x1DF8...0x1DF8, 0x1E00...0x1EFF, 0x202F...0x202F,
        0x2071...0x2071, 0x207F...0x207F, 0x2090...0x209C, 0x20F0...0x20F0, 0x212A...0x212B,
        0x2132...0x2132, 0x214E...0x214E, 0x2160...0x2188, 0x2C60...0x2C7F, 0x2E17...0x2E17,
        0xA700...0xA707, 0xA722...0xA787, 0xA78B...0xA7DC, 0xA7F1...0xA7FF, 0xA92E...0xA92E,
        0xAB30...0xAB5A, 0xAB5C...0xAB64, 0xAB66...0xAB69, 0xFB00...0xFB06, 0xFF21...0xFF3A,
        0xFF41...0xFF5A, 0x10780...0x10785, 0x10787...0x107B0, 0x107B2...0x107BA, 0x1DF00...0x1DF1E,
        0x1DF25...0x1DF2A,
    ]
}
