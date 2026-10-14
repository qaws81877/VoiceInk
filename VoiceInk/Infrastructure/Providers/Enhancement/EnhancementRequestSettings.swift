import Foundation

enum EnhancementRequestSettings {
    static let timeoutKey = "EnhancementTimeoutSeconds"
    static let retryOnTimeoutKey = "EnhancementRetryOnTimeout"
    static let defaultTimeoutSeconds = 7
    static let defaultRetryOnTimeout = true
    static let maximumAttempts = 3

    static var timeout: TimeInterval {
        let configuredTimeout = UserDefaults.standard.integer(forKey: timeoutKey)
        return TimeInterval(configuredTimeout > 0 ? configuredTimeout : defaultTimeoutSeconds)
    }

    static let secondsPerCharacter: TimeInterval = 0.03
    static let maximumScaledTimeout: TimeInterval = 300

    /// The configured timeout, raised for long input so a long dictation is not cut off.
    /// Never lower than the user's setting; capped so a stalled request still ends.
    static func timeout(forCharacters characters: Int, configured: TimeInterval = timeout) -> TimeInterval {
        let scaled = min(maximumScaledTimeout, TimeInterval(characters) * secondsPerCharacter)
        return max(configured, scaled)
    }

    static var retryOnTimeout: Bool {
        guard UserDefaults.standard.object(forKey: retryOnTimeoutKey) != nil else {
            return defaultRetryOnTimeout
        }
        return UserDefaults.standard.bool(forKey: retryOnTimeoutKey)
    }
}
