import Foundation
import os

/// Streams the default Korean cleanup call.
/// OpenAI `gpt-6-luna` is primary. Anthropic `claude-haiku-5-5` is the fallback.
/// If neither key can produce text, the raw transcript is returned.
enum KoreanCleanupClient {
    private static let logger = Logger(subsystem: "com.qaws81877.sulsul", category: "KoreanCleanup")

    static func clean(
        transcript: String,
        systemPrompt: String,
        credentials: KoreanCleanupCredentials,
        selectedProvider: String? = nil
    ) async -> String {
        let keys = credentials.keys
        switch KoreanCleanupPolicy.route(keys: keys, selectedProvider: selectedProvider) {
        case .pasteTranscript:
            return transcript
        case .anthropicOnly:
            guard let apiKey = credentials.anthropicToken else {
                return transcript
            }
            return await anthropicOrTranscript(
                transcript: transcript,
                systemPrompt: systemPrompt,
                apiKey: apiKey
            )
        case .openAIThenAnthropic:
            guard let apiKey = credentials.openAIToken else {
                return transcript
            }
            let openAI = await completeOpenAI(
                transcript: transcript,
                systemPrompt: systemPrompt,
                apiKey: apiKey
            )
            switch openAI {
            case .success(let text):
                return text
            case .failure(let reason):
                logger.error(
                    "OpenAI cleanup fell back reason=\(String(describing: reason), privacy: .public)"
                )
                guard KoreanCleanupPolicy.shouldFallBackToAnthropic(reason, hasAnthropicKey: keys.anthropic),
                    let anthropicKey = credentials.anthropicToken
                else {
                    return transcript
                }
                return await anthropicOrTranscript(
                    transcript: transcript,
                    systemPrompt: systemPrompt,
                    apiKey: anthropicKey
                )
            }
        }
    }

    private static func anthropicOrTranscript(
        transcript: String,
        systemPrompt: String,
        apiKey: String
    ) async -> String {
        switch await completeAnthropic(transcript: transcript, systemPrompt: systemPrompt, apiKey: apiKey) {
        case .success(let text):
            return text
        case .failure:
            logger.error("Anthropic cleanup failed; pasting the transcript")
            return transcript
        }
    }

    private static func completeOpenAI(
        transcript: String,
        systemPrompt: String,
        apiKey: String
    ) async -> Result<String, KoreanCleanupFallbackReason> {
        let body: Data
        do {
            body = try KoreanCleanupRequestBuilder.openAIJSON(
                systemPrompt: systemPrompt,
                transcript: transcript
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
        let session = makeSession(timeout: KoreanCleanupTimeouts.anthropicOverall)
        let clock = ContinuousClock()
        let started = clock.now

        let result = await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await Task.sleep(for: .seconds(KoreanCleanupTimeouts.openAIFirstToken))
                if !flag.isMarked {
                    session.invalidateAndCancel()
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(KoreanCleanupTimeouts.openAIOverall))
                session.invalidateAndCancel()
            }

            let streamed = await readStream(
                session: session,
                request: request,
                clock: clock,
                started: started,
                flag: flag,
                overallLimit: KoreanCleanupTimeouts.openAIOverall,
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
        apiKey: String
    ) async -> Result<String, KoreanCleanupFallbackReason> {
        let body: Data
        do {
            body = try KoreanCleanupRequestBuilder.anthropicJSON(
                systemPrompt: systemPrompt,
                transcript: transcript
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

        let session = makeSession(timeout: KoreanCleanupTimeouts.anthropicOverall)
        let clock = ContinuousClock()
        let started = clock.now
        let flag = FirstTokenFlag()

        let result = await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await Task.sleep(for: .seconds(KoreanCleanupTimeouts.anthropicOverall))
                session.invalidateAndCancel()
            }
            let streamed = await readStream(
                session: session,
                request: request,
                clock: clock,
                started: started,
                flag: flag,
                overallLimit: KoreanCleanupTimeouts.anthropicOverall,
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
                        enforcesFirstTokenDeadline: enforcesFirstTokenDeadline
                    )
                case .content(let piece):
                    if !piece.isEmpty, !sawToken {
                        sawToken = true
                        firstTokenElapsed = elapsed
                        flag.mark()
                        if enforcesFirstTokenDeadline, elapsed > KoreanCleanupTimeouts.openAIFirstToken {
                            return .failure(.firstTokenTimeout)
                        }
                    }
                    text += piece
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
                enforcesFirstTokenDeadline: enforcesFirstTokenDeadline
            )
        } catch {
            let elapsed = seconds(from: started.duration(to: clock.now))
            let firstTokenLimit =
                enforcesFirstTokenDeadline
                ? KoreanCleanupTimeouts.openAIFirstToken
                : overallLimit
            let reason = KoreanCleanupOpenAITiming.stalledReason(
                sawToken: flag.isMarked,
                elapsed: elapsed,
                firstTokenLimit: firstTokenLimit,
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
        enforcesFirstTokenDeadline: Bool
    ) -> Result<String, KoreanCleanupFallbackReason> {
        let decision = KoreanCleanupOpenAITiming.decision(
            failed: false,
            sawToken: sawToken,
            firstTokenElapsed: firstTokenElapsed,
            completionElapsed: completionElapsed,
            firstTokenLimit: enforcesFirstTokenDeadline
                ? KoreanCleanupTimeouts.openAIFirstToken
                : overallLimit,
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
