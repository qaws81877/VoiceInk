import Foundation
import os

/// Streams the default Korean cleanup call.
/// OpenAI (the mode's model, `gpt-6-luna` by default) is primary and Anthropic `claude-haiku-5-5`
/// is the fallback. When the mode selects Anthropic, only the mode's Anthropic model is called.
/// Both attempts share the `anthropicOverall` deadline. If no provider produces complete text,
/// this throws so the caller pastes the raw transcript with a warning; a cancelled task throws
/// `CancellationError` without falling back.
enum KoreanCleanupClient {
    private static let logger = Logger(subsystem: "com.qaws81877.sulsul", category: "KoreanCleanup")

    static func clean(
        transcript: String,
        systemPrompt: String,
        credentials: KoreanCleanupCredentials,
        selectedProvider: String? = nil,
        selectedModel: String? = nil
    ) async throws -> String {
        let keys = credentials.keys
        let budget = KoreanCleanupBudget.forTranscript(transcript)
        let models = KoreanCleanupPolicy.models(selectedProvider: selectedProvider, selectedModel: selectedModel)
        switch KoreanCleanupPolicy.route(keys: keys, selectedProvider: selectedProvider) {
        case .pasteTranscript:
            throw KoreanCleanupFallbackReason.requestFailed
        case .anthropicOnly:
            guard let apiKey = credentials.anthropicToken else {
                throw KoreanCleanupFallbackReason.requestFailed
            }
            return try await anthropicOrThrow(
                transcript: transcript,
                systemPrompt: systemPrompt,
                apiKey: apiKey,
                budget: budget,
                models: models
            )
        case .openAIThenAnthropic:
            guard let apiKey = credentials.openAIToken else {
                throw KoreanCleanupFallbackReason.requestFailed
            }
            let clock = ContinuousClock()
            let started = clock.now
            let openAI = await completeOpenAI(
                transcript: transcript,
                systemPrompt: systemPrompt,
                apiKey: apiKey,
                budget: budget,
                models: models
            )
            switch openAI {
            case .success(let text):
                return text
            case .failure(let reason):
                try Task.checkCancellation()
                logger.error(
                    "OpenAI cleanup fell back reason=\(String(describing: reason), privacy: .public)"
                )
                guard KoreanCleanupPolicy.shouldFallBackToAnthropic(reason, hasAnthropicKey: keys.anthropic),
                    let anthropicKey = credentials.anthropicToken
                else {
                    throw reason
                }
                let openAIElapsed = seconds(from: started.duration(to: clock.now))
                guard let remaining = budget.anthropicFallbackLimit(afterOpenAIElapsed: openAIElapsed) else {
                    throw KoreanCleanupFallbackReason.overallTimeout
                }
                return try await anthropicOrThrow(
                    transcript: transcript,
                    systemPrompt: systemPrompt,
                    apiKey: anthropicKey,
                    budget: budget.withAnthropicOverall(remaining),
                    models: models
                )
            }
        }
    }

    private static func anthropicOrThrow(
        transcript: String,
        systemPrompt: String,
        apiKey: String,
        budget: KoreanCleanupBudget,
        models: KoreanCleanupModelChoice
    ) async throws -> String {
        switch await completeAnthropic(
            transcript: transcript,
            systemPrompt: systemPrompt,
            apiKey: apiKey,
            budget: budget,
            models: models
        ) {
        case .success(let text):
            return text
        case .failure(let reason):
            try Task.checkCancellation()
            logger.error(
                "Anthropic cleanup failed reason=\(String(describing: reason), privacy: .public); pasting the transcript"
            )
            throw reason
        }
    }

    private static func completeOpenAI(
        transcript: String,
        systemPrompt: String,
        apiKey: String,
        budget: KoreanCleanupBudget,
        models: KoreanCleanupModelChoice
    ) async -> Result<String, KoreanCleanupFallbackReason> {
        let body: Data
        do {
            body = try KoreanCleanupRequestBuilder.openAIJSON(
                systemPrompt: systemPrompt,
                transcript: transcript,
                maxTokens: budget.maxTokens,
                model: models.openAI
            )
        } catch {
            return .failure(.requestFailed)
        }

        guard let url = URL(string: AIProvider.openAI.baseURL) else {
            return .failure(.requestFailed)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let flag = FirstTokenFlag()
        let session = makeSession(timeout: budget.anthropicOverall)
        let clock = ContinuousClock()
        let started = clock.now

        let result = await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await Task.sleep(for: .seconds(budget.openAIFirstToken))
                if !flag.isMarked {
                    session.invalidateAndCancel()
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(budget.openAIOverall))
                session.invalidateAndCancel()
            }

            let streamed = await readStream(
                session: session,
                request: request,
                clock: clock,
                started: started,
                flag: flag,
                overallLimit: budget.openAIOverall,
                firstTokenLimit: budget.openAIFirstToken,
                enforcesFirstTokenDeadline: true,
                parse: KoreanCleanupStreamParser.openAIEvent(fromLine:)
            )
            group.cancelAll()
            return streamed
        }
        session.invalidateAndCancel()
        return result
    }

    private static func completeAnthropic(
        transcript: String,
        systemPrompt: String,
        apiKey: String,
        budget: KoreanCleanupBudget,
        models: KoreanCleanupModelChoice
    ) async -> Result<String, KoreanCleanupFallbackReason> {
        let body: Data
        do {
            body = try KoreanCleanupRequestBuilder.anthropicJSON(
                systemPrompt: systemPrompt,
                transcript: transcript,
                maxTokens: budget.maxTokens,
                model: models.anthropic
            )
        } catch {
            return .failure(.requestFailed)
        }

        guard let url = URL(string: AIProvider.anthropic.baseURL) else {
            return .failure(.requestFailed)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(KoreanCleanupModels.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = body

        let session = makeSession(timeout: budget.anthropicOverall)
        let clock = ContinuousClock()
        let started = clock.now
        let flag = FirstTokenFlag()

        let result = await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await Task.sleep(for: .seconds(budget.anthropicOverall))
                session.invalidateAndCancel()
            }
            let streamed = await readStream(
                session: session,
                request: request,
                clock: clock,
                started: started,
                flag: flag,
                overallLimit: budget.anthropicOverall,
                firstTokenLimit: budget.anthropicOverall,
                enforcesFirstTokenDeadline: false,
                parse: KoreanCleanupStreamParser.anthropicEvent(fromLine:)
            )
            group.cancelAll()
            return streamed
        }
        session.invalidateAndCancel()
        return result
    }

    private static func readStream(
        session: URLSession,
        request: URLRequest,
        clock: ContinuousClock,
        started: ContinuousClock.Instant,
        flag: FirstTokenFlag,
        overallLimit: TimeInterval,
        firstTokenLimit: TimeInterval,
        enforcesFirstTokenDeadline: Bool,
        parse: (String) -> KoreanCleanupStreamEvent
    ) async -> Result<String, KoreanCleanupFallbackReason> {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .failure(.requestFailed)
            }

            var text = ""
            var sawToken = false
            var firstTokenElapsed: TimeInterval?
            for try await line in bytes.lines {
                let elapsed = seconds(from: started.duration(to: clock.now))
                if elapsed > overallLimit {
                    return .failure(.overallTimeout)
                }
                switch parse(line) {
                case .ignore:
                    continue
                case .done:
                    return finish(
                        text: text,
                        sawToken: sawToken,
                        firstTokenElapsed: firstTokenElapsed,
                        completionElapsed: elapsed,
                        overallLimit: overallLimit,
                        firstTokenLimit: firstTokenLimit,
                        enforcesFirstTokenDeadline: enforcesFirstTokenDeadline
                    )
                case .content(let piece):
                    if !piece.isEmpty, !sawToken {
                        sawToken = true
                        firstTokenElapsed = elapsed
                        flag.mark()
                        if enforcesFirstTokenDeadline, elapsed > firstTokenLimit {
                            return .failure(.firstTokenTimeout)
                        }
                    }
                    text += piece
                case .truncated:
                    return .failure(.outputTruncated)
                case .malformed:
                    return .failure(.requestFailed)
                }
            }

            let elapsed = seconds(from: started.duration(to: clock.now))
            return finish(
                text: text,
                sawToken: sawToken,
                firstTokenElapsed: firstTokenElapsed,
                completionElapsed: elapsed,
                overallLimit: overallLimit,
                firstTokenLimit: firstTokenLimit,
                enforcesFirstTokenDeadline: enforcesFirstTokenDeadline
            )
        } catch {
            let elapsed = seconds(from: started.duration(to: clock.now))
            let reason = KoreanCleanupOpenAITiming.stalledReason(
                sawToken: flag.isMarked,
                elapsed: elapsed,
                firstTokenLimit: enforcesFirstTokenDeadline ? firstTokenLimit : overallLimit,
                overallLimit: overallLimit
            )
            return .failure(reason)
        }
    }

    private static func finish(
        text: String,
        sawToken: Bool,
        firstTokenElapsed: TimeInterval?,
        completionElapsed: TimeInterval,
        overallLimit: TimeInterval,
        firstTokenLimit: TimeInterval,
        enforcesFirstTokenDeadline: Bool
    ) -> Result<String, KoreanCleanupFallbackReason> {
        let decision = KoreanCleanupOpenAITiming.decision(
            failed: false,
            sawToken: sawToken,
            firstTokenElapsed: firstTokenElapsed,
            completionElapsed: completionElapsed,
            firstTokenLimit: enforcesFirstTokenDeadline ? firstTokenLimit : overallLimit,
            overallLimit: overallLimit
        )
        switch decision {
        case .accept:
            let filtered = AIEnhancementOutputFilter.filter(text)
            guard !filtered.isEmpty else {
                return .failure(.requestFailed)
            }
            return .success(filtered)
        case .fallBack(let reason):
            return .failure(reason)
        case .keepWaiting:
            return .failure(.requestFailed)
        }
    }

    private static func makeSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

private final class FirstTokenFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false

    func mark() {
        lock.lock()
        marked = true
        lock.unlock()
    }

    var isMarked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return marked
    }
}
