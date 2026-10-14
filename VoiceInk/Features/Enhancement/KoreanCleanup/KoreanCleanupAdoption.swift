import Foundation

enum KoreanCleanupAdoptionDecision: Equatable {
    case alreadyApplied
    case waitForDictationMode
    case waitForKey
    case leaveCustomized
    case enableDefaultCleanup
}

enum KoreanCleanupAdoption {
    static let didApplyKey = "DidApplyKoreanCleanupDefault"
    static let dictationModeID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

    static func decision(
        alreadyApplied: Bool,
        hasDictationMode: Bool,
        isStockDictation: Bool,
        hasCleanupKey: Bool
    ) -> KoreanCleanupAdoptionDecision {
        if alreadyApplied {
            return .alreadyApplied
        }
        guard hasDictationMode else {
            return .waitForDictationMode
        }
        guard isStockDictation else {
            return .leaveCustomized
        }
        guard hasCleanupKey else {
            return .waitForKey
        }
        return .enableDefaultCleanup
    }

    static func isStockDictation(_ mode: ModeConfig) -> Bool {
        guard mode.id == dictationModeID else {
            return false
        }
        let prompt = mode.selectedPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let provider = mode.selectedAIProvider?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !mode.isAIEnhancementEnabled && prompt.isEmpty && provider.isEmpty
    }

    @MainActor
    static func applyIfNeeded(defaults: UserDefaults = .standard) {
        let manager = ModeManager.shared
        let mode = manager.getConfiguration(with: dictationModeID)
        let credentials = KoreanCleanupCredentials(
            openAI: APIKeyManager.shared.getAPIKey(forProvider: AIProvider.openAI.rawValue),
            anthropic: APIKeyManager.shared.getAPIKey(forProvider: AIProvider.anthropic.rawValue)
        )
        let next = decision(
            alreadyApplied: defaults.bool(forKey: didApplyKey),
            hasDictationMode: mode != nil,
            isStockDictation: mode.map(isStockDictation) ?? false,
            hasCleanupKey: credentials.keys.openAI || credentials.keys.anthropic
        )

        switch next {
        case .alreadyApplied, .waitForDictationMode, .waitForKey:
            return
        case .leaveCustomized:
            defaults.set(true, forKey: didApplyKey)
        case .enableDefaultCleanup:
            guard var updated = mode else { return }
            updated.isAIEnhancementEnabled = true
            updated.selectedPrompt = PromptTemplates.organizePromptId.uuidString
            updated.selectedAIProvider = AIProvider.openAI.rawValue
            updated.selectedAIModel = KoreanCleanupModels.openAI
            manager.updateConfiguration(updated)
            defaults.set(true, forKey: didApplyKey)
        }
    }
}

/// One-time switch that makes "Organize" the default for existing users.
/// Adds the Organize prompt once and moves the stock Dictation mode off the
/// verbatim cleanup prompt only while it still uses the default provider pair.
enum KoreanOrganizeAdoption {
    static let didApplyKey = "DidApplyKoreanOrganizeDefault"

    /// Fresh installs get the prompt from `StarterModePromptSeeder`, so an empty list is left alone.
    static func ensurePrompt(in prompts: [CustomPrompt]) -> [CustomPrompt] {
        guard !prompts.isEmpty,
            !prompts.contains(where: { $0.id == PromptTemplates.organizePromptId }),
            let seed = PromptTemplates.seedPrompts.first(where: { $0.id == PromptTemplates.organizePromptId })
        else {
            return prompts
        }
        var updated = prompts
        if let index = updated.firstIndex(where: { $0.id == PromptTemplates.defaultPromptId }) {
            updated.insert(seed, at: index + 1)
        } else {
            updated.append(seed)
        }
        return updated
    }

    static func shouldSwitchToOrganize(_ mode: ModeConfig) -> Bool {
        mode.id == KoreanCleanupAdoption.dictationModeID
            && mode.selectedPrompt == PromptTemplates.defaultPromptId.uuidString
            && KoreanCleanupPolicy.isDefaultCleanupSelection(
                providerName: mode.selectedAIProvider,
                modelName: mode.selectedAIModel
            )
    }

    /// Returns the prompt list to keep. The mode switch happens only when the prompt exists.
    @MainActor
    static func applyIfNeeded(
        prompts: [CustomPrompt],
        defaults: UserDefaults = .standard
    ) -> [CustomPrompt] {
        guard !defaults.bool(forKey: didApplyKey) else {
            return prompts
        }

        let updatedPrompts = ensurePrompt(in: prompts)
        let manager = ModeManager.shared
        if updatedPrompts.contains(where: { $0.id == PromptTemplates.organizePromptId }),
            var mode = manager.getConfiguration(with: KoreanCleanupAdoption.dictationModeID),
            shouldSwitchToOrganize(mode)
        {
            mode.selectedPrompt = PromptTemplates.organizePromptId.uuidString
            manager.updateConfiguration(mode)
        }
        defaults.set(true, forKey: didApplyKey)
        return updatedPrompts
    }
}

enum KoreanCleanupPromptMigration {
    /// Unmodified M1 "Default" seed. Only this exact text is replaced.
    static let legacyUnmodifiedDefaultPromptText = """
        <TASK>
        Clean <TRANSCRIPT> into polished, readable, general-purpose text.
        </TASK>

        <RULES>
        - Preserve dictated greetings, sign-offs, headings, and informal abbreviations. Do not add any that were not spoken.
        </RULES>

        <EXAMPLES>
        Input: For the invoice folder, we need first the printed map second two markers and third the spare batteries before Saturday Please include the small change in your reply, since the rest of the arrangements are already set.
        Output:
        For the invoice folder, we need the following before Saturday:

        1. The printed map
        2. Two markers
        3. The spare batteries

        Please include the small change in your reply, since the rest of the arrangements are already set.
        </EXAMPLES>
        """

    static func migrate(_ prompts: [CustomPrompt]) -> [CustomPrompt] {
        prompts.map { prompt in
            guard prompt.id == PromptTemplates.defaultPromptId,
                prompt.promptText == legacyUnmodifiedDefaultPromptText
            else {
                return prompt
            }

            return CustomPrompt(
                id: prompt.id,
                title: prompt.title,
                promptText: KoreanCleanupPrompt.text,
                useSystemInstructions: false
            )
        }
    }
}
