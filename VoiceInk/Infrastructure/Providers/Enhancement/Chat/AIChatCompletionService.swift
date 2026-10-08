import Foundation
import LLMkit

struct AIChatCompletionResult: Sendable {
    let text: String
    let openRouterCompletion: OpenRouterCompletion?
}

extension AIService {
    func performChatCompletion(
        provider: AIProvider,
        modelName: String?,
        messages: [ChatMessage],
        systemPrompt: String? = nil,
        localUserPrompt: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> AIChatCompletionResult {
        let resolvedModel = modelName?.isEmpty == false ? modelName! : selectedModel(for: provider)

        let result: String
        var openRouterCompletion: OpenRouterCompletion? = nil
        switch provider {
        case .gemini:
            result = try await GeminiLLMClient.chatCompletion(
                apiKey: try chatAPIKey(for: provider, modelName: resolvedModel),
                model: resolvedModel,
                messages: messages,
                systemPrompt: systemPrompt,
                thinkingLevel: ReasoningConfig.geminiThinkingLevel(for: resolvedModel),
                store: false,
                timeout: timeout
            )
        case .anthropic:
            if resolvedModel == KoreanCleanupModels.anthropic {
                result = try await completeAnthropicHaiku(
                    apiKey: try chatAPIKey(for: provider, modelName: resolvedModel),
                    messages: messages,
                    systemPrompt: systemPrompt,
                    timeout: timeout
                )
            } else {
                result = try await AnthropicLLMClient.chatCompletion(
                    apiKey: try chatAPIKey(for: provider, modelName: resolvedModel),
                    model: resolvedModel,
                    messages: messages,
                    systemPrompt: systemPrompt,
                    timeout: timeout
                )
            }
        case .openRouter:
            let policy = OpenRouterRequestPolicy.lowLatency(
                modelName: resolvedModel,
                modelMetadata: openRouterModelMetadata(for: resolvedModel)
            )
            let completion = try await OpenRouterClient.chatCompletion(
                apiKey: try chatAPIKey(for: provider, modelName: resolvedModel),
                model: policy.model,
                messages: messages,
                systemPrompt: systemPrompt,
                temperature: policy.temperature,
                reasoning: policy.reasoning,
                provider: policy.provider,
                includeRouterMetadata: true,
                appReferer: URL(string: "https://github.com/qaws81877/VoiceInk"),
                appTitle: "술술",
                timeout: timeout
            )
            guard !OpenRouterRequestPolicy.outputWasTruncated(finishReason: completion.finishReason) else {
                throw EnhancementError.outputTruncated
            }
            result = completion.text
            openRouterCompletion = completion
        case .custom:
            guard
                let customConfiguration = CustomAIProviderManager.shared.requestConfiguration(forModel: resolvedModel),
                let baseURL = URL(string: customConfiguration.baseURL)
            else {
                throw EnhancementError.notConfigured
            }
            result = try await OpenAILLMClient.chatCompletion(
                baseURL: baseURL,
                apiKey: customConfiguration.apiKey,
                model: customConfiguration.modelName,
                messages: messages,
                systemPrompt: systemPrompt,
                temperature: 0.3,
                timeout: timeout
            )
        case .ollama:
            result = try await enhanceWithOllama(
                text: localUserPrompt ?? chatPrompt(from: messages),
                systemPrompt: systemPrompt ?? "",
                model: resolvedModel,
                timeout: timeout
            )
        case .localCLI:
            result = try await enhanceWithLocalCLI(
                systemPrompt: systemPrompt ?? "",
                userPrompt: localUserPrompt ?? chatPrompt(from: messages)
            )
        default:
            guard let baseURL = URL(string: provider.baseURL) else {
                throw EnhancementError.notConfigured
            }
            let reasoningEffort = ReasoningConfig.getReasoningParameter(
                for: provider,
                modelName: resolvedModel
            )
            let extraBody = ReasoningConfig.getExtraBodyParameters(
                for: provider,
                modelName: resolvedModel
            )
            result = try await OpenAILLMClient.chatCompletion(
                baseURL: baseURL,
                apiKey: try chatAPIKey(for: provider, modelName: resolvedModel),
                model: resolvedModel,
                messages: messages,
                systemPrompt: systemPrompt,
                temperature: 0.3,
                reasoningEffort: reasoningEffort,
                extraBody: extraBody,
                timeout: timeout
            )
        }

        return AIChatCompletionResult(text: result, openRouterCompletion: openRouterCompletion)
    }

    func completeChat(
        provider: AIProvider,
        modelName: String?,
        messages: [ChatMessage],
        systemPrompt: String? = nil,
        timeout: TimeInterval = 30
    ) async throws -> String {
        let completion = try await performChatCompletion(
            provider: provider,
            modelName: modelName,
            messages: messages,
            systemPrompt: systemPrompt,
            timeout: timeout
        )
        let result = completion.text
        let filteredResult = AIEnhancementOutputFilter.filter(result)
        guard provider != .openRouter || !filteredResult.isEmpty else {
            throw EnhancementError.enhancementFailed
        }
        return filteredResult
    }

    /// LLMkit's Anthropic client defaults to 8192. The Korean cleanup path keeps its own 600-token cap.
    private static let anthropicHaikuMaxTokens = 8192

    private struct AnthropicHaikuResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let content: [Block]
    }

    /// Manual `claude-haiku-5-5` selections bypass LLMkit. That client omits
    /// `thinking` and `output_config`, which Haiku 5.5 needs, and this path
    /// must not send `temperature`.
    private func completeAnthropicHaiku(
        apiKey: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        timeout: TimeInterval
    ) async throws -> String {
        let system: String?
        let conversation: [ChatMessage]
        if let systemPrompt {
            system = systemPrompt
            conversation = messages.filter { $0.role != "system" }
        } else {
            let systemMessages = messages.filter { $0.role == "system" }
            system = systemMessages.isEmpty ? nil : systemMessages.map(\.content).joined(separator: "\n")
            conversation = messages.filter { $0.role != "system" }
        }

        let body = KoreanCleanupRequestBuilder.anthropicMessagesBody(
            model: KoreanCleanupModels.anthropic,
            systemPrompt: system,
            messages: conversation.map {
                KoreanCleanupRequestBuilder.ChatMessage(role: $0.role, content: $0.content)
            },
            maxTokens: Self.anthropicHaikuMaxTokens,
            stream: false
        )

        let payload: Data
        do {
            payload = try JSONEncoder().encode(body)
        } catch {
            throw EnhancementError.customError(error.localizedDescription)
        }

        guard let url = URL(string: AIProvider.anthropic.baseURL) else {
            throw EnhancementError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(KoreanCleanupModels.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = payload

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw EnhancementError.timeout
        } catch {
            throw EnhancementError.networkError
        }

        guard let http = response as? HTTPURLResponse else {
            throw EnhancementError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 429 { throw EnhancementError.rateLimitExceeded }
            if http.statusCode == 408 { throw EnhancementError.timeout }
            if (500...599).contains(http.statusCode) { throw EnhancementError.serverError }
            throw EnhancementError.customError("HTTP \(http.statusCode): \(message)")
        }

        let decoded: AnthropicHaikuResponse
        do {
            decoded = try JSONDecoder().decode(AnthropicHaikuResponse.self, from: data)
        } catch {
            throw EnhancementError.invalidResponse
        }
        return decoded.content.filter { $0.type == "text" }.compactMap(\.text).joined()
    }

    private func chatAPIKey(for provider: AIProvider, modelName: String) throws -> String {
        if provider == .custom {
            guard let customConfiguration = CustomAIProviderManager.shared.requestConfiguration(forModel: modelName)
            else {
                throw EnhancementError.notConfigured
            }
            return customConfiguration.apiKey
        }

        guard let key = APIKeyManager.shared.getAPIKey(forProvider: provider.rawValue), !key.isEmpty else {
            throw EnhancementError.notConfigured
        }
        return key
    }

    private func chatPrompt(from messages: [ChatMessage]) -> String {
        let formattedMessages = messages.map { message in
            let label: String
            switch message.role {
            case "assistant":
                label = "assistant"
            case "user":
                label = "user"
            case "system":
                label = "system"
            default:
                label = "other"
            }
            return """
                <message role="\(label)">
                \(message.content)
                </message>
                """
        }
        .joined(separator: "\n\n")

        return """
            <conversation>
            \(formattedMessages)
            </conversation>
            """
    }
}
