import XCTest

@testable import VoiceInk

final class KoreanCleanupStabilityTests: XCTestCase {
    func testCleanThrowsInsteadOfReturningTheTranscriptWhenNoProviderCanRun() async {
        do {
            _ = try await KoreanCleanupClient.clean(
                transcript: "음 그러니까 내일 회의는 세 시예요",
                systemPrompt: KoreanCleanupPrompt.text,
                credentials: KoreanCleanupCredentials(openAI: nil, anthropic: "  ")
            )
            XCTFail("clean must not report the raw transcript as a cleanup result")
        } catch let reason as KoreanCleanupFallbackReason {
            XCTAssertEqual(reason, .requestFailed)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testFailedCleanupMapsToNonRetriedEnhancementErrors() {
        guard case .enhancementFailed = KoreanCleanupPolicy.enhancementError(for: .requestFailed) else {
            return XCTFail("requestFailed should map to enhancementFailed")
        }
        guard case .outputTruncated = KoreanCleanupPolicy.enhancementError(for: .outputTruncated) else {
            return XCTFail("outputTruncated should map to outputTruncated")
        }
        for reason in [KoreanCleanupFallbackReason.firstTokenTimeout, .overallTimeout] {
            guard case .customError(let message) = KoreanCleanupPolicy.enhancementError(for: reason) else {
                return XCTFail("\(reason) must not map to .timeout, which makeRequestWithRetry retries")
            }
            XCTAssertEqual(message, EnhancementError.timeout.errorDescription)
        }
    }

    func testStreamParsersReportOutputTruncation() {
        XCTAssertEqual(
            KoreanCleanupStreamParser.openAIEvent(
                fromLine: #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#
            ),
            .truncated
        )
        XCTAssertEqual(
            KoreanCleanupStreamParser.openAIEvent(
                fromLine: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#
            ),
            .ignore
        )
        XCTAssertEqual(
            KoreanCleanupStreamParser.anthropicEvent(
                fromLine: #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#
            ),
            .truncated
        )
        XCTAssertEqual(
            KoreanCleanupStreamParser.anthropicEvent(
                fromLine: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#
            ),
            .ignore
        )
        XCTAssertTrue(KoreanCleanupPolicy.shouldFallBackToAnthropic(.outputTruncated, hasAnthropicKey: true))
        XCTAssertFalse(KoreanCleanupPolicy.shouldFallBackToAnthropic(.outputTruncated, hasAnthropicKey: false))
    }

    func testAnthropicFallbackSharesTheOverallDeadline() {
        let budget = KoreanCleanupBudget.base
        XCTAssertEqual(
            budget.anthropicFallbackLimit(afterOpenAIElapsed: budget.openAIOverall),
            budget.anthropicOverall - budget.openAIOverall
        )
        XCTAssertNil(budget.anthropicFallbackLimit(afterOpenAIElapsed: budget.anthropicOverall))
        XCTAssertEqual(budget.withAnthropicOverall(4).anthropicOverall, 4)
        XCTAssertEqual(budget.withAnthropicOverall(4).maxTokens, budget.maxTokens)

        // 3,000 characters: OpenAI 60 s, shared deadline 90 s, so a timed-out OpenAI leaves 30 s.
        let long = KoreanCleanupBudget.forTranscript(String(repeating: "가", count: 3_000))
        XCTAssertEqual(long.anthropicFallbackLimit(afterOpenAIElapsed: long.openAIOverall) ?? 0, 30, accuracy: 0.001)

        // At the 300 s cap both limits are equal, so a timed-out OpenAI leaves nothing to wait for.
        let capped = KoreanCleanupBudget.forTranscript(String(repeating: "가", count: 20_000))
        XCTAssertNil(capped.anthropicFallbackLimit(afterOpenAIElapsed: capped.openAIOverall))
        XCTAssertNotNil(capped.anthropicFallbackLimit(afterOpenAIElapsed: 1))
    }

    func testAdoptionUsesAnExistingCleanupPrompt() {
        XCTAssertEqual(
            KoreanCleanupAdoption.cleanupPromptId(
                availablePromptIds: [PromptTemplates.defaultPromptId, PromptTemplates.organizePromptId]
            ),
            PromptTemplates.organizePromptId
        )
        XCTAssertEqual(
            KoreanCleanupAdoption.cleanupPromptId(availablePromptIds: [PromptTemplates.defaultPromptId]),
            PromptTemplates.defaultPromptId
        )
        XCTAssertNil(KoreanCleanupAdoption.cleanupPromptId(availablePromptIds: [PromptTemplates.chatPromptId]))
        XCTAssertNil(KoreanCleanupAdoption.cleanupPromptId(availablePromptIds: []))
    }
}
