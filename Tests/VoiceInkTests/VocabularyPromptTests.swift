import XCTest

@testable import VoiceInk

final class VocabularyPromptTests: XCTestCase {
    private let koreanLanguagePrompt = "안녕하세요, 잘 지내시나요? 만나서 반갑습니다."

    func testCleanupSystemPromptIsUnchangedWithoutVocabulary() {
        let base = KoreanCleanupPrompt.text
        XCTAssertEqual(KoreanCleanupVocabulary.systemPrompt(base: base, vocabularyText: ""), base)
        XCTAssertEqual(KoreanCleanupVocabulary.systemPrompt(base: base, vocabularyText: " \n\t"), base)
        XCTAssertEqual(
            KoreanCleanupVocabulary.systemPrompt(base: base, vocabularyText: "").utf8.count,
            base.utf8.count
        )
    }

    func testCleanupSystemPromptAppendsVocabularyAfterFrozenText() {
        let base = KoreanCleanupPrompt.text
        let vocabulary = "Important Vocabulary: Claude, Grok, Grok Bot, OpenAI"
        let prompt = KoreanCleanupVocabulary.systemPrompt(base: base, vocabularyText: vocabulary)

        XCTAssertTrue(prompt.hasPrefix(base))
        let appended = String(prompt.dropFirst(base.count))
        XCTAssertTrue(appended.hasPrefix("\n\n# Custom Vocabulary\n"))
        XCTAssertTrue(
            appended.contains(
                "Do not force a replacement when the text clearly means something else:"
            )
        )
        XCTAssertTrue(appended.contains("클로드, 그록, 드록, 그록봇, 드록볶, 오픈에이아이"))
        XCTAssertTrue(appended.contains("different ordinary Korean word"))
        XCTAssertTrue(appended.contains("<CUSTOM_VOCABULARY>\n\(vocabulary)\n</CUSTOM_VOCABULARY>"))
        XCTAssertFalse(base.contains("# Custom Vocabulary"))
        XCTAssertFalse(base.contains(vocabulary))
    }

    func testWhisperPromptIsUnchangedWithoutVocabulary() {
        let base = WhisperPrompt.resolvedPrompt(for: "ko")
        XCTAssertEqual(WhisperVocabularyPrompt.prompt(languagePrompt: base, terms: []), base)
        XCTAssertEqual(WhisperVocabularyPrompt.prompt(languagePrompt: base, terms: ["", "  ", "\n"]), base)
        XCTAssertEqual(WhisperVocabularyPrompt.prompt(languagePrompt: "", terms: []), "")
    }

    func testWhisperPromptAppendsExactSpellings() {
        XCTAssertEqual(WhisperPrompt.resolvedPrompt(for: "ko"), koreanLanguagePrompt)
        let prompt = WhisperVocabularyPrompt.prompt(
            languagePrompt: koreanLanguagePrompt,
            terms: ["Claude", "Grok", "Grok Bot", "OpenAI"]
        )
        XCTAssertEqual(
            prompt,
            koreanLanguagePrompt + "\nClaude, Grok, Grok Bot, OpenAI"
        )
        XCTAssertEqual(
            WhisperVocabularyPrompt.prompt(languagePrompt: "", terms: ["Claude", "Grok"]),
            "Claude, Grok"
        )
    }

    func testWhisperPromptDropsTermsPastEitherCap() {
        let forty = (1...40).map { "aa\($0)" }
        let overCount = forty + ["extra"]
        let counted = WhisperVocabularyPrompt.prompt(languagePrompt: "Hello", terms: overCount)
        XCTAssertTrue(counted.hasPrefix("Hello\n"))
        let countedLine = String(counted.dropFirst("Hello\n".count))
        XCTAssertEqual(countedLine.split(separator: ",").count, 40)
        XCTAssertFalse(countedLine.contains("extra"))
        XCTAssertLessThanOrEqual(countedLine.count, WhisperVocabularyPrompt.maxAppendedCharacters)

        let fat = String(repeating: "b", count: 150)
        let truncated = WhisperVocabularyPrompt.cappedLine(terms: [fat, fat, fat, "c"])
        XCTAssertEqual(truncated, "\(fat), \(fat)")
        XCTAssertFalse(truncated.contains("c"))
        XCTAssertLessThanOrEqual(truncated.count, WhisperVocabularyPrompt.maxAppendedCharacters)

        let keptOrder = WhisperVocabularyPrompt.cappedLine(terms: ["  Claude  ", "", "Grok"])
        XCTAssertEqual(keptOrder, "Claude, Grok")
    }
}
