import Foundation

/// Named deadlines for the default Korean cleanup pipeline.
/// OpenAI falls back to Anthropic when the first token is later than
/// `openAIFirstToken` or the full response is later than `openAIOverall`.
/// `anthropicOverall` is a safety cap so a stalled Anthropic stream cannot hang dictation.
enum KoreanCleanupTimeouts {
    static let openAIFirstToken: TimeInterval = 2.5
    static let openAIOverall: TimeInterval = 6
    static let anthropicOverall: TimeInterval = 30
}

enum KoreanCleanupModels {
    static let openAI = "gpt-6-luna"
    static let anthropic = "claude-haiku-5-5"
    static let maxTokens = 600
    static let openAIReasoningEffort = "none"
    static let anthropicThinkingType = "disabled"
    static let anthropicOutputEffort = "low"
    static let anthropicVersion = "2023-06-01"
}

enum KoreanCleanupRoute: Equatable {
    case openAIThenAnthropic
    case anthropicOnly
    case pasteTranscript
}

enum KoreanCleanupFallbackReason: Error, Equatable {
    case requestFailed
    case firstTokenTimeout
    case overallTimeout
}

struct KoreanCleanupKeys: Equatable {
    var openAI: Bool
    var anthropic: Bool
}

struct KoreanCleanupCredentials: Equatable {
    var openAI: String?
    var anthropic: String?

    var keys: KoreanCleanupKeys {
        KoreanCleanupKeys(
            openAI: Self.isPresent(openAI),
            anthropic: Self.isPresent(anthropic)
        )
    }

    var openAIToken: String? {
        Self.trimmed(openAI)
    }

    var anthropicToken: String? {
        Self.trimmed(anthropic)
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isPresent(_ value: String?) -> Bool {
        trimmed(value) != nil
    }
}

enum KoreanCleanupPolicy {
    static func route(keys: KoreanCleanupKeys) -> KoreanCleanupRoute {
        route(keys: keys, selectedProvider: nil)
    }

    /// OpenAI is primary for the default pair. An explicit Anthropic selection uses Haiku directly.
    static func route(keys: KoreanCleanupKeys, selectedProvider: String?) -> KoreanCleanupRoute {
        if selectedProvider == AIProvider.anthropic.rawValue {
            return keys.anthropic ? .anthropicOnly : .pasteTranscript
        }
        if keys.openAI {
            return .openAIThenAnthropic
        }
        if keys.anthropic {
            return .anthropicOnly
        }
        return .pasteTranscript
    }

    static func shouldFallBackToAnthropic(
        _ reason: KoreanCleanupFallbackReason,
        hasAnthropicKey: Bool
    ) -> Bool {
        switch reason {
        case .requestFailed, .firstTokenTimeout, .overallTimeout:
            return hasAnthropicKey
        }
    }

    /// The default Korean cleanup pair, not a manually chosen provider or model.
    static func usesDefaultPipeline(_ configuration: EnhancementRuntimeConfiguration) -> Bool {
        guard configuration.prompt?.id == PromptTemplates.defaultPromptId else {
            return false
        }

        let providerName = configuration.mode?.selectedAIProvider ?? configuration.provider?.rawValue
        let modelName = configuration.mode?.selectedAIModel ?? configuration.modelName
        return isDefaultCleanupSelection(providerName: providerName, modelName: modelName)
    }

    static func isDefaultCleanupSelection(providerName: String?, modelName: String?) -> Bool {
        if let providerName, !providerName.isEmpty,
            providerName != AIProvider.openAI.rawValue,
            providerName != AIProvider.anthropic.rawValue
        {
            return false
        }

        if providerName == AIProvider.openAI.rawValue {
            if let modelName, !modelName.isEmpty, modelName != KoreanCleanupModels.openAI {
                return false
            }
        }

        if providerName == AIProvider.anthropic.rawValue {
            if let modelName, !modelName.isEmpty, modelName != KoreanCleanupModels.anthropic {
                return false
            }
        }

        return true
    }

    static func systemPrompt(from prompt: CustomPrompt) -> String {
        let trimmed = prompt.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? KoreanCleanupPrompt.text : prompt.promptText
    }
}

enum KoreanCleanupOpenAIDecision: Equatable {
    case accept
    case keepWaiting
    case fallBack(KoreanCleanupFallbackReason)
}

enum KoreanCleanupOpenAITiming {
    /// `firstTokenElapsed` and `completionElapsed` are measured from the start of the OpenAI call.
    /// A missing first token while the call is still running stays `.keepWaiting`; the caller
    /// applies `openAIFirstToken` when that deadline passes with no token.
    static func decision(
        failed: Bool,
        sawToken: Bool,
        firstTokenElapsed: TimeInterval?,
        completionElapsed: TimeInterval?,
        firstTokenLimit: TimeInterval = KoreanCleanupTimeouts.openAIFirstToken,
        overallLimit: TimeInterval = KoreanCleanupTimeouts.openAIOverall
    ) -> KoreanCleanupOpenAIDecision {
        if failed {
            return .fallBack(.requestFailed)
        }

        if let completionElapsed, completionElapsed > overallLimit {
            return .fallBack(.overallTimeout)
        }

        if sawToken {
            let elapsed = firstTokenElapsed ?? 0
            if elapsed > firstTokenLimit {
                return .fallBack(.firstTokenTimeout)
            }
        } else if completionElapsed != nil {
            return .fallBack(.requestFailed)
        } else {
            return .keepWaiting
        }

        if completionElapsed != nil {
            return .accept
        }

        return .keepWaiting
    }

    static func stalledReason(
        sawToken: Bool,
        elapsed: TimeInterval,
        firstTokenLimit: TimeInterval = KoreanCleanupTimeouts.openAIFirstToken,
        overallLimit: TimeInterval = KoreanCleanupTimeouts.openAIOverall
    ) -> KoreanCleanupFallbackReason {
        if elapsed > overallLimit {
            return .overallTimeout
        }
        if !sawToken, elapsed > firstTokenLimit {
            return .firstTokenTimeout
        }
        return .requestFailed
    }
}

enum KoreanCleanupRequestBuilder {
    struct ChatMessage: Encodable, Equatable {
        let role: String
        let content: String
    }

    struct OpenAIBody: Encodable, Equatable {
        let model: String
        let messages: [ChatMessage]
        let reasoningEffort: String
        let maxCompletionTokens: Int
        let stream: Bool

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case reasoningEffort = "reasoning_effort"
            case maxCompletionTokens = "max_completion_tokens"
            case stream
        }
    }

    struct AnthropicBody: Encodable, Equatable {
        struct Thinking: Encodable, Equatable {
            let type: String
        }

        struct OutputConfig: Encodable, Equatable {
            let effort: String
        }

        let model: String
        let maxTokens: Int
        let system: String
        let stream: Bool
        let thinking: Thinking
        let outputConfig: OutputConfig
        let messages: [ChatMessage]

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case stream
            case thinking
            case outputConfig = "output_config"
            case messages
        }
    }

    static func userMessage(transcript: String) -> String {
        "<TRANSCRIPT>\n\(transcript)\n</TRANSCRIPT>"
    }

    static func openAIBody(systemPrompt: String, transcript: String) -> OpenAIBody {
        OpenAIBody(
            model: KoreanCleanupModels.openAI,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userMessage(transcript: transcript)),
            ],
            reasoningEffort: KoreanCleanupModels.openAIReasoningEffort,
            maxCompletionTokens: KoreanCleanupModels.maxTokens,
            stream: true
        )
    }

    static func anthropicBody(systemPrompt: String, transcript: String) -> AnthropicBody {
        AnthropicBody(
            model: KoreanCleanupModels.anthropic,
            maxTokens: KoreanCleanupModels.maxTokens,
            system: systemPrompt,
            stream: true,
            thinking: AnthropicBody.Thinking(type: KoreanCleanupModels.anthropicThinkingType),
            outputConfig: AnthropicBody.OutputConfig(effort: KoreanCleanupModels.anthropicOutputEffort),
            messages: [
                ChatMessage(role: "user", content: userMessage(transcript: transcript))
            ]
        )
    }

    static func openAIJSON(systemPrompt: String, transcript: String) throws -> Data {
        try JSONEncoder().encode(openAIBody(systemPrompt: systemPrompt, transcript: transcript))
    }

    static func anthropicJSON(systemPrompt: String, transcript: String) throws -> Data {
        try JSONEncoder().encode(anthropicBody(systemPrompt: systemPrompt, transcript: transcript))
    }
}

enum KoreanCleanupStreamEvent: Equatable {
    case ignore
    case done
    case content(String)
    case malformed
}

enum KoreanCleanupStreamParser {
    static func openAIEvent(fromLine line: String) -> KoreanCleanupStreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix(":") {
            return .ignore
        }
        guard trimmed.hasPrefix("data:") else {
            return .malformed
        }

        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return .done
        }
        guard let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .malformed
        }
        guard let choices = json["choices"] as? [[String: Any]],
            let delta = choices.first?["delta"] as? [String: Any]
        else {
            return .ignore
        }
        if let content = delta["content"] as? String {
            return .content(content)
        }
        return .ignore
    }

    static func anthropicEvent(fromLine line: String) -> KoreanCleanupStreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix(":") || trimmed.hasPrefix("event:") {
            return .ignore
        }
        guard trimmed.hasPrefix("data:") else {
            return .malformed
        }

        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .malformed
        }

        let type = json["type"] as? String
        if type == "error" {
            return .malformed
        }
        guard type == "content_block_delta",
            let delta = json["delta"] as? [String: Any]
        else {
            return .ignore
        }
        if (delta["type"] as? String) == "text_delta", let text = delta["text"] as? String {
            return .content(text)
        }
        return .ignore
    }
}
