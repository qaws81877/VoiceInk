import Foundation
import LLMkit

struct OllamaRefreshResult {
    let models: [OllamaModel]
    let errorMessage: String?
}

class AIService: ObservableObject {
    @Published var apiKey: String = ""
    @Published var isAPIKeyValid: Bool = false
    @Published var customBaseURL: String = UserDefaults.standard.string(forKey: "customProviderBaseURL") ?? "" {
        didSet {
            userDefaults.set(customBaseURL, forKey: "customProviderBaseURL")
        }
    }
    @Published var customModel: String = UserDefaults.standard.string(forKey: "customProviderModel") ?? "" {
        didSet {
            userDefaults.set(customModel, forKey: "customProviderModel")
        }
    }
    @Published var selectedProvider: AIProvider {
        didSet {
            userDefaults.set(selectedProvider.rawValue, forKey: "selectedAIProvider")
            applyCredentialState(for: selectedProvider)
            if selectedProvider == .ollama {
                Task {
                    await refreshOllamaAvailability()
                }
            }
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published private var selectedModels: [AIProvider: String] = [:]
    private let userDefaults = UserDefaults.standard
    private lazy var ollamaService = OllamaService()
    private lazy var localCLIService = LocalCLIService()
    private var apiKeyChangeObserver: NSObjectProtocol?
    private var settingsChangeObserver: NSObjectProtocol?

    @Published private var openRouterModels: [String] = []
    @Published private var openRouterModelCatalog: [OpenRouterModel] = []
    private var isOpenRouterCatalogRefreshing = false
    @Published private(set) var isOllamaRefreshing = false

    var connectedProviders: [AIProvider] {
        AIProvider.allCases.filter(isConnected)
    }

    func isConnected(_ provider: AIProvider) -> Bool {
        guard provider.supportsEnhancement else {
            return false
        }

        if provider == .custom {
            return CustomAIProviderManager.shared.hasConfiguredModels
        } else if provider == .ollama {
            return ollamaService.isConnected
        } else if provider == .localCLI {
            return localCLIService.isConfigured
        } else if provider.requiresAPIKey {
            return APIKeyManager.shared.hasAPIKey(forProvider: provider.rawValue)
        }
        return false
    }

    var currentModel: String {
        if let selectedModel = selectedModels[selectedProvider],
            !selectedModel.isEmpty,
            (selectedProvider.supportsCustomModelID || selectedProvider == .ollama
                || availableModels.contains(selectedModel))
        {
            return selectedModel
        }
        return selectedProvider.defaultModel
    }

    func selectedModel(for provider: AIProvider) -> String {
        if let selectedModel = selectedModels[provider], !selectedModel.isEmpty {
            return selectedModel
        }
        return provider.defaultModel
    }

    func customModelID(for provider: AIProvider) -> String {
        guard provider.supportsCustomModelID else { return "" }
        let key = "\(provider.rawValue)CustomModelID"
        if let savedModel = userDefaults.string(forKey: key), !savedModel.isEmpty {
            return savedModel
        }
        let selectedModel = selectedModel(for: provider)
        return provider.availableModels.contains(selectedModel) ? "" : selectedModel
    }

    var availableModels: [String] {
        availableModels(for: selectedProvider)
    }

    var localCLICommandTemplate: String {
        localCLIService.commandTemplate
    }

    var localCLITimeoutSeconds: Double {
        localCLIService.timeoutSeconds
    }

    func availableModels(for provider: AIProvider) -> [String] {
        if provider == .ollama {
            return ollamaService.availableModels.map { $0.name }
        } else if provider == .openRouter {
            return openRouterModels
        }
        return provider.availableModels
    }

    init() {
        if userDefaults.string(forKey: "selectedAIProvider") == "GROQ" {
            userDefaults.set("Groq", forKey: "selectedAIProvider")
        }

        if let savedProvider = userDefaults.string(forKey: "selectedAIProvider"),
            let provider = AIProvider(rawValue: savedProvider)
        {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .gemini
        }

        applyCredentialState(for: selectedProvider)

        loadSavedModelSelections()
        loadSavedOpenRouterModels()
        initializeAutoLearnSelectionIfNeeded()

        apiKeyChangeObserver = NotificationCenter.default.addObserver(
            forName: .aiProviderKeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.reloadSelectedProviderConfiguration()
                self.initializeAutoLearnSelectionIfNeeded()
            }
        }

        settingsChangeObserver = NotificationCenter.default.addObserver(
            forName: .AppSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.initializeAutoLearnSelectionIfNeeded()
        }
    }

    deinit {
        if let apiKeyChangeObserver {
            NotificationCenter.default.removeObserver(apiKeyChangeObserver)
        }
        if let settingsChangeObserver {
            NotificationCenter.default.removeObserver(settingsChangeObserver)
        }
    }

    private func reloadSelectedProviderConfiguration() {
        if selectedProvider == .custom {
            customBaseURL = userDefaults.string(forKey: "customProviderBaseURL") ?? ""
            customModel = userDefaults.string(forKey: "customProviderModel") ?? ""
        }

        let selectedModelKey = "\(selectedProvider.rawValue)SelectedModel"
        if let savedModel = userDefaults.string(forKey: selectedModelKey), !savedModel.isEmpty {
            selectedModels[selectedProvider] = savedModel
        }

        applyCredentialState(for: selectedProvider)
    }

    private func applyCredentialState(for provider: AIProvider) {
        if provider.requiresAPIKey {
            if let savedKey = APIKeyManager.shared.getAPIKey(forProvider: provider.rawValue) {
                apiKey = savedKey
                isAPIKeyValid = true
            } else {
                apiKey = ""
                isAPIKeyValid = false
            }
        } else {
            apiKey = ""
            isAPIKeyValid = provider == .localCLI ? localCLIService.isConfigured : true
        }
    }

    private func initializeAutoLearnSelectionIfNeeded() {
        if let selectedProvider = AutoLearnSettings.selectedProvider,
            AutoLearnProviderPolicy.isSupported(selectedProvider)
        {
            return
        }

        let availableProviders = connectedProviders.filter {
            AutoLearnProviderPolicy.isSupported($0)
                && ($0 != .ollama || !availableModels(for: $0).isEmpty)
        }
        let provider = availableProviders.contains(selectedProvider)
            ? selectedProvider
            : availableProviders.first
        guard let provider else { return }

        AutoLearnSettings.initializeSelectionIfNeeded(
            provider: provider,
            model: initialAutoLearnModel(for: provider)
        )
    }

    private func initialAutoLearnModel(for provider: AIProvider) -> String {
        let selectedModel = selectedModel(for: provider)
        let availableModels = availableModels(for: provider)
        return provider.supportsCustomModelID || availableModels.contains(selectedModel)
            ? selectedModel
            : (availableModels.contains(provider.defaultModel) ? provider.defaultModel : availableModels.first)
                ?? selectedModel
    }

    private func loadSavedModelSelections() {
        for provider in AIProvider.allCases {
            let key = "\(provider.rawValue)SelectedModel"
            if let savedModel = userDefaults.string(forKey: key), !savedModel.isEmpty {
                selectedModels[provider] = savedModel
            }
        }
    }

    private func loadSavedOpenRouterModels() {
        if let catalog = OpenRouterCatalogStore.shared.models(for: .enhancement) {
            openRouterModelCatalog = catalog
            openRouterModels = catalog.filter(isOpenRouterEnhancementModel).map(\.id)
            reconcileOpenRouterSelection(selectInitialIfNeeded: true)
            return
        }

        openRouterModels = OpenRouterCatalogStore.shared.legacyEnhancementModelIDs
    }

    private func saveOpenRouterModels() {
        OpenRouterCatalogStore.shared.saveLegacyEnhancementModelIDs(openRouterModels)
        try? OpenRouterCatalogStore.shared.save(openRouterModelCatalog, for: .enhancement)
    }

    private func isOpenRouterEnhancementModel(_ model: OpenRouterModel) -> Bool {
        guard let architecture = model.architecture else { return true }
        return architecture.inputModalities.contains("text")
            && architecture.outputModalities.contains("text")
    }

    @discardableResult
    private func reconcileOpenRouterSelection(selectInitialIfNeeded: Bool = false) -> Bool {
        let selected = selectedModels[.openRouter]
        if let selected, openRouterModels.contains(selected) { return false }
        guard selected != nil || (selectInitialIfNeeded && selectedProvider == .openRouter) else { return false }

        if let replacement = openRouterModels.first(where: { $0 == AIProvider.openRouter.defaultModel })
            ?? openRouterModels.first
        {
            selectedModels[.openRouter] = replacement
            userDefaults.set(replacement, forKey: "OpenRouterSelectedModel")
        } else {
            selectedModels.removeValue(forKey: .openRouter)
            userDefaults.removeObject(forKey: "OpenRouterSelectedModel")
        }
        return selected != selectedModels[.openRouter]
    }

    func selectModel(_ model: String) {
        selectModel(model, for: selectedProvider)
    }

    func selectModel(_ model: String, for provider: AIProvider) {
        let resolvedInput = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedInput.isEmpty else { return }

        if provider == .custom {
            guard CustomAIProviderManager.shared.applyConfiguration(forModel: resolvedInput) else { return }
        }

        selectedModels[provider] = resolvedInput
        let key = "\(provider.rawValue)SelectedModel"
        userDefaults.set(resolvedInput, forKey: key)
        if provider.supportsCustomModelID, !provider.availableModels.contains(resolvedInput) {
            userDefaults.set(resolvedInput, forKey: "\(provider.rawValue)CustomModelID")
        }

        if provider == .ollama {
            updateSelectedOllamaModel(resolvedInput)
        } else if provider == .custom {
            reloadSelectedProviderConfiguration()
        }

        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    func saveAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard selectedProvider.requiresAPIKey else {
            completion(true, nil)
            return
        }

        verifyAPIKey(key) { [weak self] isValid, errorMessage in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if isValid {
                    self.apiKey = key
                    self.isAPIKeyValid = true
                    APIKeyManager.shared.saveAPIKey(key, forProvider: self.selectedProvider.rawValue)
                    NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
                    NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
                } else {
                    self.isAPIKeyValid = false
                }
                completion(isValid, errorMessage)
            }
        }
    }

    func verifyAPIKey(_ key: String, completion: @escaping (Bool, String?) -> Void) {
        guard selectedProvider.requiresAPIKey else {
            completion(true, nil)
            return
        }

        Task {
            let result = await verifyAPIKey(
                key,
                for: selectedProvider,
                model: currentModel
            )
            DispatchQueue.main.async {
                completion(result.isValid, result.errorMessage)
            }
        }
    }

    func verifyAPIKey(_ key: String, for provider: AIProvider, model: String? = nil) async -> (
        isValid: Bool, errorMessage: String?
    ) {
        guard provider.requiresAPIKey else {
            return (true, nil)
        }

        let verificationModel = model ?? selectedModel(for: provider)

        switch provider {
        case .anthropic:
            return await AnthropicLLMClient.verifyAPIKey(key)
        case .elevenLabs:
            return await ElevenLabsClient.verifyAPIKey(key)
        case .deepgram:
            return await DeepgramClient.verifyAPIKey(key)
        case .mistral:
            return await MistralTranscriptionClient.verifyAPIKey(key)
        case .soniox:
            return await SonioxClient.verifyAPIKey(key)
        case .speechmatics:
            return await SpeechmaticsClient.verifyAPIKey(key)
        case .assemblyAI:
            return await AssemblyAIClient.verifyAPIKey(key)
        case .openRouter:
            return await OpenRouterClient.verifyAPIKey(key)
        case .openAI:
            return await OpenAILLMClient.verifyAPIKey(key)
        case .gemini:
            return await GeminiLLMClient.verifyAPIKey(key)
        default:
            guard let baseURL = URL(string: provider.baseURL) else {
                return (false, "Invalid or missing base URL configuration")
            }
            return await OpenAILLMClient.verifyAPIKey(
                baseURL: baseURL,
                apiKey: key,
                model: verificationModel
            )
        }
    }

    func clearAPIKey() {
        guard selectedProvider.requiresAPIKey else { return }

        apiKey = ""
        isAPIKeyValid = false
        APIKeyManager.shared.deleteAPIKey(forProvider: selectedProvider.rawValue)
        NotificationCenter.default.post(name: .aiProviderKeyChanged, object: nil)
    }

    func checkOllamaConnection(completion: @escaping (Bool) -> Void) {
        Task { [weak self] in
            guard let self = self else { return }
            _ = await self.refreshOllamaAvailability()
            await MainActor.run {
                completion(self.ollamaService.isConnected)
            }
        }
    }

    func refreshOllamaAvailabilityInBackground() {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.refreshOllamaAvailability()
        }
    }

    @MainActor
    @discardableResult
    func refreshOllamaConnectionAndModels() async -> [OllamaModel] {
        let result = await refreshOllamaAvailability()
        return result.models
    }

    @MainActor
    func refreshOllamaAvailability() async -> OllamaRefreshResult {
        guard !isOllamaRefreshing else {
            return OllamaRefreshResult(models: ollamaService.availableModels, errorMessage: nil)
        }

        isOllamaRefreshing = true
        defer {
            isOllamaRefreshing = false
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }

        let result = await ollamaService.refreshConnectionAndModels()
        switch result {
        case .success(let models):
            return OllamaRefreshResult(models: models, errorMessage: nil)
        case .failure(let error):
            return OllamaRefreshResult(models: [], errorMessage: ollamaErrorMessage(for: error))
        }
    }

    private func ollamaErrorMessage(for error: Error) -> String {
        if let llmKitError = error as? LLMKitError {
            return ollamaErrorMessage(for: llmKitError)
        }

        if let localAIError = error as? LocalAIError,
            let errorDescription = localAIError.errorDescription
        {
            return errorDescription
        }

        let nsError = error as NSError
        var details = [nsError.localizedDescription]

        if let failingURL = nsError.userInfo["NSErrorFailingURLKey"] as? URL {
            details.append("URL: \(failingURL.absoluteString)")
        } else if let failingURLString = nsError.userInfo["NSErrorFailingURLStringKey"] as? String {
            details.append("URL: \(failingURLString)")
        }

        details.append("Code: \(nsError.domain) \(nsError.code)")

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("Underlying: \(underlyingError.localizedDescription)")
            details.append("Underlying code: \(underlyingError.domain) \(underlyingError.code)")
        }

        if let streamErrorCode = nsError.userInfo["_kCFStreamErrorCodeKey"] {
            details.append("Network code: \(streamErrorCode)")
        }

        return details.joined(separator: "\n")
    }

    private func ollamaErrorMessage(for error: LLMKitError) -> String {
        switch error {
        case .httpError(let statusCode, let message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedMessage.isEmpty else { return "HTTP \(statusCode)" }
            return "HTTP \(statusCode): \(trimmedMessage)"
        default:
            return error.localizedDescription
        }
    }

    func enhanceWithOllama(text: String, systemPrompt: String, model: String? = nil, timeout: TimeInterval = 30)
        async throws -> String
    {
        try await ollamaService.enhance(text, withSystemPrompt: systemPrompt, model: model, timeout: timeout)
    }

    func reviewAutoLearnCandidates(
        payload: String,
        systemPrompt: String,
        provider: AIProvider,
        modelName: String?
    ) async throws -> String {
        guard AutoLearnProviderPolicy.isSupported(provider) else {
            throw EnhancementError.notConfigured
        }

        return try await performChatCompletion(
            provider: provider,
            modelName: modelName,
            messages: [.user(payload)],
            systemPrompt: systemPrompt,
            localUserPrompt: payload,
            timeout: EnhancementRequestSettings.timeout
        ).text
    }

    func updateOllamaBaseURL(_ newURL: String) {
        ollamaService.baseURL = newURL
        userDefaults.set(newURL, forKey: "ollamaBaseURL")
    }

    func updateSelectedOllamaModel(_ modelName: String) {
        ollamaService.selectedModel = modelName
        userDefaults.set(modelName, forKey: "ollamaSelectedModel")
    }

    func loadLocalCLITemplate(_ template: LocalCLITemplate) {
        localCLIService.loadTemplate(template)
        refreshLocalCLIConfigurationState()
    }

    func updateLocalCLICommandTemplate(_ command: String) {
        localCLIService.commandTemplate = command
        refreshLocalCLIConfigurationState()
    }

    func updateLocalCLITimeoutSeconds(_ timeout: Double) {
        localCLIService.timeoutSeconds = timeout
        refreshLocalCLIConfigurationState()
    }

    func enhanceWithLocalCLI(systemPrompt: String, userPrompt: String) async throws -> String {
        try await localCLIService.enhance(systemPrompt: systemPrompt, userPrompt: userPrompt)
    }

    private func refreshLocalCLIConfigurationState() {
        if selectedProvider == .localCLI {
            isAPIKeyValid = localCLIService.isConfigured
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    func openRouterModelMetadata(for modelName: String) -> OpenRouterModel? {
        openRouterModelCatalog.first(where: { $0.id == modelName })
    }

    @MainActor
    func fetchOpenRouterModelsIfNeededForMigration() async {
        guard openRouterModelCatalog.isEmpty,
            APIKeyManager.shared.hasAPIKey(forProvider: AIProvider.openRouter.rawValue)
        else {
            return
        }

        await fetchOpenRouterModels()
    }

    @MainActor
    func fetchOpenRouterModels() async {
        guard !isOpenRouterCatalogRefreshing else { return }
        isOpenRouterCatalogRefreshing = true
        defer { isOpenRouterCatalogRefreshing = false }

        do {
            let catalog = try await OpenRouterClient.fetchModelCatalog()
            openRouterModelCatalog = catalog
            openRouterModels = catalog.filter(isOpenRouterEnhancementModel).map(\.id)
            saveOpenRouterModels()
            if reconcileOpenRouterSelection(selectInitialIfNeeded: true) {
                NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            }
        } catch {
            // Keep the last successful catalog during transient OpenRouter failures.
        }
    }
}
