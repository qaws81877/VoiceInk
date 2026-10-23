import SwiftData
import XCTest

@testable import VoiceInk

final class LatinSpellingCorrectionTests: XCTestCase {
    private func correct(
        _ text: String,
        vocabulary: [String],
        protectedPhrases: [String] = []
    ) -> String {
        LatinSpellingCorrector.correct(text, vocabulary: vocabulary, protectedPhrases: protectedPhrases)
    }

    // MARK: - Close misses

    func testSingleCloseMissBecomesVocabularySpelling() {
        XCTAssertEqual(
            correct("I asked Cluade about it", vocabulary: ["Claude"]),
            "I asked Claude about it"
        )
    }

    func testWrongCapitalsBecomeVocabularySpelling() {
        XCTAssertEqual(correct("openai released it", vocabulary: ["OpenAI"]), "OpenAI released it")
    }

    func testSeparatorDifferenceBecomesVocabularySpelling() {
        XCTAssertEqual(correct("grok bot is here", vocabulary: ["Grok", "Grok Bot"]), "Grok Bot is here")
    }

    func testEverySeparateMissIsCorrected() {
        XCTAssertEqual(
            correct("Cluade and Cluade", vocabulary: ["Claude"]),
            "Claude and Claude"
        )
    }

    func testExactSpellingIsLeftAlone() {
        XCTAssertEqual(correct("Groq is fast", vocabulary: ["Groq", "Grok"]), "Groq is fast")
    }

    // MARK: - Hangul

    func testTrailingHangulParticleStays() {
        XCTAssertEqual(correct("Cluade가 답했다", vocabulary: ["Claude"]), "Claude가 답했다")
        XCTAssertEqual(correct("오늘 openai에서", vocabulary: ["OpenAI"]), "오늘 OpenAI에서")
    }

    func testHangulInTranscriptIsNeverChanged() {
        let text = "클로드 클라우드 그록에게 물어봤다"
        XCTAssertEqual(correct(text, vocabulary: ["Claude", "클로드", "Grok"]), text)
    }

    func testDecomposedHangulInTranscriptIsNeverChanged() {
        let decomposed = "클로드가 Cluade".decomposedStringWithCanonicalMapping
        let corrected = correct(decomposed, vocabulary: ["Claude"])
        XCTAssertEqual(corrected, "클로드가 ".decomposedStringWithCanonicalMapping + "Claude")
        XCTAssertEqual(Array(corrected.unicodeScalars.prefix(8)), Array(decomposed.unicodeScalars.prefix(8)))
    }

    func testVocabularyWordContainingHangulIsNotASource() {
        XCTAssertEqual(correct("Cluade bot", vocabulary: ["Claude봇"]), "Cluade bot")
        XCTAssertEqual(correct("openai", vocabulary: ["OpenAI 오픈"]), "openai")
    }

    func testVocabularyWordContainingJamoIsNotASource() {
        let decomposed = "Claude가".decomposedStringWithCanonicalMapping
        XCTAssertEqual(correct("cluade", vocabulary: [decomposed]), "cluade")
        XCTAssertEqual(correct("cluade", vocabulary: ["Claudeㅋ"]), "cluade")
        XCTAssertEqual(correct("cluade", vocabulary: ["Claude\u{1100}"]), "cluade")
        XCTAssertTrue(LatinSpellingCorrector.containsHangul("\u{3131}"))
        XCTAssertTrue(LatinSpellingCorrector.containsHangul("\u{A960}"))
        XCTAssertTrue(LatinSpellingCorrector.containsHangul("\u{D7B0}"))
        XCTAssertFalse(LatinSpellingCorrector.containsHangul("Claude 3.5"))
    }

    // MARK: - Digits and hyphens

    func testSpellingWithDigitsAndHyphenIsASource() {
        XCTAssertEqual(correct("try gpt 4o now", vocabulary: ["GPT-4o"]), "try GPT-4o now")
        XCTAssertEqual(correct("try gpt-4O now", vocabulary: ["GPT-4o"]), "try GPT-4o now")
        XCTAssertEqual(correct("Qwen3 대신 Quen3을", vocabulary: ["Qwen3"]), "Qwen3 대신 Qwen3을")
    }

    func testDifferentDigitsAreNotAMiss() {
        XCTAssertEqual(correct("GPT-4 and gpt-5o", vocabulary: ["GPT-4o"]), "GPT-4 and gpt-5o")
    }

    // MARK: - Weak and tied matches

    func testWeakMatchIsLeftUnchanged() {
        XCTAssertEqual(correct("the cloud is grey", vocabulary: ["Claude"]), "the cloud is grey")
        XCTAssertEqual(correct("grow fast", vocabulary: ["Groq"]), "grow fast")
    }

    func testNeighbouringWordIsNotSwallowed() {
        XCTAssertEqual(correct("I asked Claud a question", vocabulary: ["Claude"]), "I asked Claude a question")
        XCTAssertEqual(correct("I prefer GPT-4 a bit", vocabulary: ["GPT-4o"]), "I prefer GPT-4 a bit")
    }

    func testTieBetweenTwoVocabularyWordsIsLeftUnchanged() {
        XCTAssertEqual(correct("ask Clauda now", vocabulary: ["Claude", "Claudi"]), "ask Clauda now")
    }

    // MARK: - Exact word replacement wins

    func testProtectedReplacementSpanIsNotCorrected() {
        XCTAssertEqual(correct("Claud said", vocabulary: ["Claude"], protectedPhrases: ["Claud"]), "Claud said")
        XCTAssertEqual(correct("Claud and Cluade", vocabulary: ["Claude"], protectedPhrases: ["Claud"]), "Claud and Claude")
    }

    func testNoVocabularyLeavesTextUnchanged() {
        XCTAssertEqual(correct("Cluade", vocabulary: []), "Cluade")
    }

    // MARK: - Transcript step (word replacement then correction)

    @MainActor
    func testTranscriptStepAppliesReplacementThenCorrection() throws {
        let context = try makeDictionaryContext()
        context.insert(VocabularyWord(word: "Claude"))
        context.insert(VocabularyWord(word: "OpenAI"))
        context.insert(VocabularyWord(word: "클로드"))
        context.insert(WordReplacement(originalText: "open ai", replacementText: "openai"))
        try context.save()

        XCTAssertEqual(
            TranscriptDictionaryStep.apply(to: "Cluade는 open ai 제품이 아니다", using: context),
            "Claude는 openai 제품이 아니다"
        )
    }

    @MainActor
    func testTranscriptStepLetsExactReplacementWin() throws {
        let context = try makeDictionaryContext()
        context.insert(VocabularyWord(word: "Claude"))
        context.insert(WordReplacement(originalText: "claud", replacementText: "Claud"))
        try context.save()

        XCTAssertEqual(TranscriptDictionaryStep.apply(to: "claud and Cluade", using: context), "Claud and Claude")
    }

    @MainActor
    func testTranscriptStepWithoutDictionaryLeavesTextUnchanged() throws {
        let context = try makeDictionaryContext()
        XCTAssertEqual(TranscriptDictionaryStep.apply(to: "Cluade 테스트", using: context), "Cluade 테스트")
    }

    @MainActor
    private func makeDictionaryContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: VocabularyWord.self, WordReplacement.self,
            configurations: configuration
        )
        containers.append(container)
        return container.mainContext
    }

    private var containers: [ModelContainer] = []
}
