import XCTest

@testable import VoiceInk

final class KoreanCleanupTests: XCTestCase {
    private let systemPrompt = "SYSTEM"
    private let transcript = "음 오늘 저녁에 어 시간 돼"

    func testUserMessageWrapperIsExact() {
        XCTAssertEqual(
            KoreanCleanupRequestBuilder.userMessage(transcript: transcript),
            "<TRANSCRIPT>\n음 오늘 저녁에 어 시간 돼\n</TRANSCRIPT>"
        )
        XCTAssertFalse(
            KoreanCleanupRequestBuilder.userMessage(transcript: transcript).hasPrefix("\n")
        )
    }

    func testOpenAIBodyOmitsTemperatureAndUsesLunaParameters() throws {
        let object = try jsonObject(
            KoreanCleanupRequestBuilder.openAIJSON(systemPrompt: systemPrompt, transcript: transcript)
        )

        XCTAssertEqual(object["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(object["reasoning_effort"] as? String, "none")
        XCTAssertEqual(object["max_completion_tokens"] as? Int, 600)
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertNil(object["temperature"])
        XCTAssertNil(object["max_tokens"])
        XCTAssertFalse(containsKey(object, named: "temperature"))

        let messages = object["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?[0]["role"] as? String, "system")
        XCTAssertEqual(messages?[0]["content"] as? String, systemPrompt)
        XCTAssertEqual(messages?[1]["role"] as? String, "user")
        XCTAssertEqual(
            messages?[1]["content"] as? String,
            "<TRANSCRIPT>\n\(transcript)\n</TRANSCRIPT>"
        )
    }

    func testAnthropicBodyOmitsTemperatureAndDisablesThinking() throws {
        let object = try jsonObject(
            KoreanCleanupRequestBuilder.anthropicJSON(systemPrompt: systemPrompt, transcript: transcript)
        )

        XCTAssertEqual(object["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(object["max_tokens"] as? Int, 600)
        XCTAssertEqual(object["system"] as? String, systemPrompt)
        XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertEqual((object["thinking"] as? [String: Any])?["type"] as? String, "disabled")
        XCTAssertEqual((object["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertNil(object["temperature"])
        XCTAssertFalse(containsKey(object, named: "temperature"))

        let messages = object["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 1)
        XCTAssertEqual(messages?[0]["role"] as? String, "user")
        XCTAssertEqual(
            messages?[0]["content"] as? String,
            "<TRANSCRIPT>\n\(transcript)\n</TRANSCRIPT>"
        )
    }

    func testFallbackRouteUsesHaikuOnlyWhenOpenAIKeyIsMissing() {
        XCTAssertEqual(
            KoreanCleanupPolicy.route(keys: KoreanCleanupKeys(openAI: true, anthropic: true)),
            .openAIThenAnthropic
        )
        XCTAssertEqual(
            KoreanCleanupPolicy.route(keys: KoreanCleanupKeys(openAI: true, anthropic: false)),
            .openAIThenAnthropic
        )
        XCTAssertEqual(
            KoreanCleanupPolicy.route(keys: KoreanCleanupKeys(openAI: false, anthropic: true)),
            .anthropicOnly
        )
        XCTAssertEqual(
            KoreanCleanupPolicy.route(keys: KoreanCleanupKeys(openAI: false, anthropic: false)),
            .pasteTranscript
        )
        XCTAssertEqual(
            KoreanCleanupPolicy.route(
                keys: KoreanCleanupKeys(openAI: true, anthropic: true),
                selectedProvider: "Anthropic"
            ),
            .anthropicOnly
        )

        for reason in [
            KoreanCleanupFallbackReason.requestFailed,
            .firstTokenTimeout,
            .overallTimeout,
        ] {
            XCTAssertTrue(KoreanCleanupPolicy.shouldFallBackToAnthropic(reason, hasAnthropicKey: true))
            XCTAssertFalse(KoreanCleanupPolicy.shouldFallBackToAnthropic(reason, hasAnthropicKey: false))
        }
    }

    func testOpenAITimingDeadlines() {
        XCTAssertEqual(
            KoreanCleanupOpenAITiming.decision(
                failed: true,
                sawToken: false,
                firstTokenElapsed: nil,
                completionElapsed: nil
            ),
            .fallBack(.requestFailed)
        )
        XCTAssertEqual(
            KoreanCleanupOpenAITiming.decision(
                failed: false,
                sawToken: true,
                firstTokenElapsed: 2.5,
                completionElapsed: 6
            ),
            .accept
        )
        XCTAssertEqual(
            KoreanCleanupOpenAITiming.decision(
                failed: false,
                sawToken: true,
                firstTokenElapsed: 2.51,
                completionElapsed: nil
            ),
            .fallBack(.firstTokenTimeout)
        )
        XCTAssertEqual(
            KoreanCleanupOpenAITiming.decision(
                failed: false,
                sawToken: true,
                firstTokenElapsed: 1,
                completionElapsed: 6.01
            ),
            .fallBack(.overallTimeout)
        )
        XCTAssertEqual(
            KoreanCleanupOpenAITiming.decision(
                failed: false,
                sawToken: false,
                firstTokenElapsed: nil,
                completionElapsed: nil
            ),
            .keepWaiting
        )
        XCTAssertEqual(
            KoreanCleanupOpenAITiming.stalledReason(sawToken: false, elapsed: 2.51),
            .firstTokenTimeout
        )
        XCTAssertEqual(
            KoreanCleanupOpenAITiming.stalledReason(sawToken: true, elapsed: 6.01),
            .overallTimeout
        )
        XCTAssertEqual(KoreanCleanupTimeouts.openAIFirstToken, 2.5)
        XCTAssertEqual(KoreanCleanupTimeouts.openAIOverall, 6)
        XCTAssertEqual(KoreanCleanupTimeouts.anthropicOverall, 30)
    }

    func testDefaultCleanupSelectionLeavesOtherProvidersAlone() {
        XCTAssertTrue(
            KoreanCleanupPolicy.isDefaultCleanupSelection(
                providerName: "OpenAI",
                modelName: "gpt-6-luna"
            )
        )
        XCTAssertTrue(
            KoreanCleanupPolicy.isDefaultCleanupSelection(
                providerName: "Anthropic",
                modelName: "claude-haiku-5-5"
            )
        )
        XCTAssertFalse(
            KoreanCleanupPolicy.isDefaultCleanupSelection(
                providerName: "OpenAI",
                modelName: "gpt-4.1-mini"
            )
        )
        XCTAssertFalse(
            KoreanCleanupPolicy.isDefaultCleanupSelection(
                providerName: "Groq",
                modelName: nil
            )
        )
    }

    func testPromptMigrationReplacesOnlyTheUnmodifiedSeed() {
        let legacy = CustomPrompt(
            id: PromptTemplates.defaultPromptId,
            title: "Default",
            promptText: KoreanCleanupPromptMigration.legacyUnmodifiedDefaultPromptText,
            useSystemInstructions: true
        )
        let edited = CustomPrompt(
            id: PromptTemplates.defaultPromptId,
            title: "Default",
            promptText: "user edited",
            useSystemInstructions: true
        )
        let migrated = KoreanCleanupPromptMigration.migrate([legacy, edited])
        XCTAssertEqual(migrated[0].promptText, KoreanCleanupPrompt.text)
        XCTAssertFalse(migrated[0].useSystemInstructions)
        XCTAssertEqual(migrated[1].promptText, "user edited")
        XCTAssertTrue(migrated[1].useSystemInstructions)
    }

    func testDefaultSeedIsTheFrozenPrompt() throws {
        let seed = try XCTUnwrap(
            PromptTemplates.seedPrompts.first { $0.id == PromptTemplates.defaultPromptId }
        )
        XCTAssertEqual(seed.promptText, KoreanCleanupPrompt.text)
        XCTAssertFalse(seed.useSystemInstructions)

        let fixture = try String(
            contentsOf: fixtureURL("prompt_ko_v3", fileExtension: "txt"),
            encoding: .utf8
        )
        XCTAssertEqual(KoreanCleanupPrompt.text, fixture)
        XCTAssertTrue(KoreanCleanupPrompt.text.hasPrefix("너는 한국어 받아쓰기"))
        XCTAssertTrue(KoreanCleanupPrompt.text.hasSuffix("받아쓴 문장으로만 다듬어라.\n"))
    }

    func testCleanupFixturesParseWithoutCallingProviders() throws {
        let lines = try String(
            contentsOf: fixtureURL("ko_cleanup_cases", fileExtension: "jsonl"),
            encoding: .utf8
        )
        .split(whereSeparator: \.isNewline)
        XCTAssertEqual(lines.count, 20)
        for line in lines {
            let object = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            )
            XCTAssertNotNil(object["id"] as? String)
            XCTAssertNotNil(object["input"] as? String)
            XCTAssertNotNil(object["expected"] as? String)
        }
    }

    func testAdoptionDoesNotOverwriteACustomizedDictationMode() {
        XCTAssertEqual(
            KoreanCleanupAdoption.decision(
                alreadyApplied: false,
                hasDictationMode: true,
                isStockDictation: true,
                hasCleanupKey: false
            ),
            .waitForKey
        )
        XCTAssertEqual(
            KoreanCleanupAdoption.decision(
                alreadyApplied: false,
                hasDictationMode: true,
                isStockDictation: true,
                hasCleanupKey: true
            ),
            .enableDefaultCleanup
        )
        XCTAssertEqual(
            KoreanCleanupAdoption.decision(
                alreadyApplied: false,
                hasDictationMode: true,
                isStockDictation: false,
                hasCleanupKey: true
            ),
            .leaveCustomized
        )
        XCTAssertEqual(
            KoreanCleanupAdoption.decision(
                alreadyApplied: true,
                hasDictationMode: true,
                isStockDictation: true,
                hasCleanupKey: true
            ),
            .alreadyApplied
        )
    }

    func testOpenAIAndAnthropicStreamParsers() {
        XCTAssertEqual(
            KoreanCleanupStreamParser.openAIEvent(
                fromLine: #"data: {"choices":[{"delta":{"content":"안녕"}}]}"#
            ),
            .content("안녕")
        )
        XCTAssertEqual(KoreanCleanupStreamParser.openAIEvent(fromLine: "data: [DONE]"), .done)
        XCTAssertEqual(KoreanCleanupStreamParser.openAIEvent(fromLine: "data: {"), .malformed)
        XCTAssertEqual(
            KoreanCleanupStreamParser.anthropicEvent(
                fromLine: #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"네."}}"#
            ),
            .content("네.")
        )
        XCTAssertEqual(
            KoreanCleanupStreamParser.anthropicEvent(
                fromLine: #"data: {"type":"error","error":{"type":"api_error"}}"#
            ),
            .malformed
        )
    }

    private func fixtureURL(_ name: String, fileExtension: String) throws -> URL {
        try XCTUnwrap(
            Bundle(for: KoreanCleanupTests.self).url(forResource: name, withExtension: fileExtension)
        )
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func containsKey(_ value: Any, named key: String) -> Bool {
        if let dictionary = value as? [String: Any] {
            if dictionary.keys.contains(key) {
                return true
            }
            return dictionary.values.contains { containsKey($0, named: key) }
        }
        if let array = value as? [Any] {
            return array.contains { containsKey($0, named: key) }
        }
        return false
    }
}
