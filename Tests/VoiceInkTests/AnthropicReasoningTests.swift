import XCTest

@testable import VoiceInk

final class AnthropicReasoningTests: XCTestCase {
    private let sonnet55 = "claude-sonnet-5-5"

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func thinkingType(_ object: [String: Any]) -> String? {
        (object["thinking"] as? [String: Any])?["type"] as? String
    }

    private func effort(_ object: [String: Any]) -> String? {
        (object["output_config"] as? [String: Any])?["effort"] as? String
    }

    private func decodeMode(extraFields: String = "") throws -> ModeConfig {
        let json = """
            {
              "id": "20000000-0000-0000-0000-000000000003",
              "name": "Chat",
              "isAIEnhancementEnabled": true,
              "useClipboardContext": false,
              "useSelectedTextContext": true,
              "useScreenCapture": false,
              "outputMode": "paste"\(extraFields)
            }
            """
        return try JSONDecoder().decode(ModeConfig.self, from: Data(json.utf8))
    }

    func testSonnet55IsInTheAnthropicModelList() {
        XCTAssertTrue(AIProvider.anthropic.availableModels.contains(sonnet55))
    }

    func testSonnet55ThinksAdaptivelyAtLowEffortByDefault() throws {
        let object = try jsonObject(
            KoreanCleanupRequestBuilder.anthropicJSON(systemPrompt: "S", transcript: "T", model: sonnet55)
        )

        XCTAssertEqual(object["model"] as? String, sonnet55)
        XCTAssertEqual(thinkingType(object), "adaptive")
        XCTAssertEqual(effort(object), "low")
        XCTAssertNil(object["temperature"])
    }

    func testSonnet55KeepsRoomForThinkingInMaxTokens() throws {
        let object = try jsonObject(
            KoreanCleanupRequestBuilder.anthropicJSON(
                systemPrompt: "S",
                transcript: "T",
                maxTokens: KoreanCleanupModels.maxTokens,
                model: sonnet55
            )
        )

        XCTAssertEqual(
            object["max_tokens"] as? Int,
            KoreanCleanupModels.maxTokens + AnthropicEffort.low.thinkingHeadroomTokens
        )
    }

    func testChosenEffortReachesTheRequestAndRaisesTheHeadroom() throws {
        for level in AnthropicEffort.allCases {
            let object = try jsonObject(
                KoreanCleanupRequestBuilder.anthropicJSON(
                    systemPrompt: "S",
                    transcript: "T",
                    model: sonnet55,
                    effort: level
                )
            )
            XCTAssertEqual(effort(object), level.rawValue)
            XCTAssertEqual(thinkingType(object), "adaptive")
            XCTAssertEqual(
                object["max_tokens"] as? Int,
                KoreanCleanupModels.maxTokens + level.thinkingHeadroomTokens
            )
        }
        XCTAssertLessThan(
            AnthropicEffort.low.thinkingHeadroomTokens,
            AnthropicEffort.max.thinkingHeadroomTokens
        )
    }

    func testOtherModelsKeepThinkingOffAtLowEffortAndIgnoreTheChosenLevel() throws {
        for model in [KoreanCleanupModels.anthropic, "claude-sonnet-5", "claude-haiku-4-5"] {
            let object = try jsonObject(
                KoreanCleanupRequestBuilder.anthropicJSON(
                    systemPrompt: "S",
                    transcript: "T",
                    model: model,
                    effort: .max
                )
            )
            XCTAssertEqual(thinkingType(object), "disabled", model)
            XCTAssertEqual(effort(object), "low", model)
            XCTAssertEqual(object["max_tokens"] as? Int, KoreanCleanupModels.maxTokens, model)
        }
    }

    func testGenericBodyForSonnet55OmitsTemperatureAndThinksAdaptively() throws {
        let data = try JSONEncoder().encode(
            KoreanCleanupRequestBuilder.anthropicMessagesBody(
                model: sonnet55,
                systemPrompt: "Rewrite this",
                messages: [.init(role: "user", content: "hello")],
                maxTokens: 8192,
                stream: false,
                effort: .medium
            )
        )
        let object = try jsonObject(data)

        XCTAssertEqual(thinkingType(object), "adaptive")
        XCTAssertEqual(effort(object), "medium")
        XCTAssertEqual(object["max_tokens"] as? Int, 8192 + AnthropicEffort.medium.thinkingHeadroomTokens)
        XCTAssertEqual(object["stream"] as? Bool, false)
        XCTAssertNil(object["temperature"])
    }

    func testOnlySonnet55AndHaikuUseTheDirectRequest() {
        XCTAssertTrue(AnthropicReasoningPolicy.usesDirectRequest(sonnet55))
        XCTAssertTrue(AnthropicReasoningPolicy.usesDirectRequest(KoreanCleanupModels.anthropic))
        XCTAssertFalse(AnthropicReasoningPolicy.usesDirectRequest("claude-sonnet-5"))
        XCTAssertTrue(AnthropicReasoningPolicy.supportsEffortSelection(sonnet55))
        XCTAssertFalse(AnthropicReasoningPolicy.supportsEffortSelection(KoreanCleanupModels.anthropic))
        XCTAssertFalse(AnthropicReasoningPolicy.supportsEffortSelection(nil))
    }

    func testModeEffortReachesTheCleanupModelChoice() {
        XCTAssertEqual(
            KoreanCleanupPolicy.models(
                selectedProvider: "Anthropic",
                selectedModel: sonnet55,
                anthropicEffort: .high
            ),
            KoreanCleanupModelChoice(openAI: KoreanCleanupModels.openAI, anthropic: sonnet55, anthropicEffort: .high)
        )
        XCTAssertNil(
            KoreanCleanupPolicy.models(
                selectedProvider: "OpenAI",
                selectedModel: "gpt-6-sol",
                anthropicEffort: .high
            ).anthropicEffort
        )
    }

    func testModeSavedBeforeTheReasoningLevelExistedDecodesAsUnset() throws {
        XCTAssertNil(try decodeMode().anthropicEffort)
    }

    func testUnknownStoredReasoningLevelDecodesAsUnsetInsteadOfDroppingTheMode() throws {
        XCTAssertNil(try decodeMode(extraFields: #", "anthropicEffort": "ultra""#).anthropicEffort)
        XCTAssertNil(try decodeMode(extraFields: #", "anthropicEffort": 3"#).anthropicEffort)
    }

    func testChosenReasoningLevelSurvivesSaveAndLoad() throws {
        var mode = try decodeMode()
        mode.anthropicEffort = .xhigh
        let reloaded = try JSONDecoder().decode(ModeConfig.self, from: JSONEncoder().encode(mode))
        XCTAssertEqual(reloaded.anthropicEffort, .xhigh)
    }

    func testNewModeLeavesTheReasoningLevelUnsetAndLowIsTheDefault() {
        XCTAssertNil(ModeConfig(name: "New", isAIEnhancementEnabled: false).anthropicEffort)
        XCTAssertEqual(AnthropicEffort.default, .low)
    }
}
