import Foundation

/// Reasoning depth for Anthropic models that cannot run with thinking off.
/// Raw values are the Messages API `output_config.effort` strings and are persisted in modes.
enum AnthropicEffort: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case xhigh
    case max

    /// The lowest level is the fastest, so it is what a mode uses until the user picks another.
    static let `default`: AnthropicEffort = .low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return String(localized: "Low")
        case .medium: return String(localized: "Medium")
        case .high: return String(localized: "High")
        case .xhigh: return String(localized: "Extra High")
        case .max: return String(localized: "Max")
        }
    }

    /// Thinking tokens count against `max_tokens`, so the answer budget needs room on top.
    /// It is a ceiling, not a target: unused room costs nothing.
    var thinkingHeadroomTokens: Int {
        switch self {
        case .low: return 2_048
        case .medium: return 4_096
        case .high: return 8_192
        case .xhigh, .max: return 16_000
        }
    }
}

/// Which `thinking` and `output_config` an Anthropic request carries for a model.
enum AnthropicReasoningPolicy {
    struct Settings: Equatable {
        let thinkingType: String
        let effort: String
        let maxTokensHeadroom: Int
    }

    /// Models that reject `thinking: {type: "disabled"}` with a 400 and take a user-chosen effort instead.
    static let effortSelectableModels: Set<String> = ["claude-sonnet-5-5"]

    static func supportsEffortSelection(_ model: String?) -> Bool {
        guard let model else { return false }
        return effortSelectableModels.contains(model)
    }

    /// Models that must go through our own request because the shared client omits
    /// `thinking` and `output_config`, which these models need.
    static func usesDirectRequest(_ model: String) -> Bool {
        model == KoreanCleanupModels.anthropic || supportsEffortSelection(model)
    }

    static func settings(model: String, effort: AnthropicEffort?) -> Settings {
        guard supportsEffortSelection(model) else {
            return Settings(
                thinkingType: KoreanCleanupModels.anthropicThinkingType,
                effort: KoreanCleanupModels.anthropicOutputEffort,
                maxTokensHeadroom: 0
            )
        }
        let level = effort ?? .default
        return Settings(
            thinkingType: "adaptive",
            effort: level.rawValue,
            maxTokensHeadroom: level.thinkingHeadroomTokens
        )
    }
}
