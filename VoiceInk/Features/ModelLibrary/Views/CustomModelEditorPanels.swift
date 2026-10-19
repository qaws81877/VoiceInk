import SwiftUI

struct CustomTranscriptionModelEditorPanel: View {
    let editingModel: CustomCloudModel?
    @ObservedObject var customModelManager: CustomCloudModelManager
    let onClose: () -> Void
    let onSave: () -> Void

    @State private var displayName = ""
    @State private var apiEndpoint = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var isMultilingual = true
    @State private var validationErrors: [String] = []
    @State private var isSaving = false
    @State private var connectionTest: ConnectionTestState = .idle
    @State private var connectionTestTask: Task<Void, Never>?

    private var isEditing: Bool {
        editingModel != nil
    }

    private var canTestConnection: Bool {
        !apiEndpoint.trimmed.isEmpty && !apiKey.trimmed.isEmpty && !modelName.trimmed.isEmpty
    }

    private var canSave: Bool {
        canTestConnection && !displayName.trimmed.isEmpty
    }

    private func resetConnectionTest() {
        ConnectionTestRunner.reset(task: $connectionTestTask, state: $connectionTest)
    }

    private func runConnectionTest() {
        let endpoint = apiEndpoint.trimmed
        let key = apiKey.trimmed
        let model = modelName.trimmed

        ConnectionTestRunner.run(task: $connectionTestTask, state: $connectionTest) {
            await CustomModelConnectionTester.testTranscriptionEndpoint(
                endpoint: endpoint,
                apiKey: key,
                modelName: model
            )
        }
    }

    var body: some View {
        QuickPanelScaffold {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CustomModelEditorSection(title: "Details") {
                        VStack(spacing: 10) {
                            CustomModelTextField(
                                label: "Display Name", placeholder: String(localized: "My Custom Model"),
                                text: $displayName)
                            CustomModelTextField(
                                label: "API Endpoint", placeholder: "https://api.openai.com/v1/audio/transcriptions",
                                text: $apiEndpoint)
                            CustomModelTextField(
                                label: "API Key", placeholder: String(localized: "Paste API key"), text: $apiKey,
                                isSecure: true)
                            CustomModelTextField(
                                label: "Model Name", placeholder: "gpt-4o-mini-transcribe", text: $modelName)
                            CustomModelToggleRow(title: "Multilingual Model", isOn: $isMultilingual)
                            ConnectionTestRow(
                                state: connectionTest, isDisabled: !canTestConnection, action: runConnectionTest)
                        }
                    }

                    ConnectionTestResultBox(state: connectionTest)

                    if !validationErrors.isEmpty {
                        CustomModelErrorBox(messages: validationErrors)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 76)
                .padding(.bottom, 72)
            }
        } header: {
            CustomModelEditorHeader(
                title: isEditing
                    ? "Edit Custom Transcription Model" : "Add Custom Transcription Model",
                onClose: onClose
            )
        } footer: {
            CustomModelEditorFooter(
                primaryTitle: isSaving ? "Saving" : isEditing ? "Save Changes" : "Add Model",
                isPrimaryDisabled: !canSave || isSaving,
                onCancel: onClose,
                onPrimary: saveModel
            )
        }
        .onAppear(perform: loadModel)
        .onChange(of: editingModel?.id) { _, _ in
            loadModel()
        }
        .onConnectionFieldsChange(apiEndpoint, apiKey, modelName, perform: resetConnectionTest)
    }

    private func loadModel() {
        if let editingModel {
            displayName = editingModel.displayName
            apiEndpoint = editingModel.apiEndpoint
            apiKey = APIKeyManager.shared.getCustomModelAPIKey(forModelId: editingModel.id) ?? ""
            modelName = editingModel.modelName
            isMultilingual = editingModel.isMultilingualModel
        } else {
            displayName = ""
            apiEndpoint = "https://api.openai.com/v1/audio/transcriptions"
            apiKey = ""
            modelName = "gpt-4o-mini-transcribe"
            isMultilingual = true
        }

        validationErrors = []
        isSaving = false
        resetConnectionTest()
    }

    private func saveModel() {
        let trimmedDisplayName = displayName.trimmed
        let trimmedEndpoint = apiEndpoint.trimmed
        let trimmedKey = apiKey.trimmed
        let trimmedModelName = modelName.trimmed
        let generatedName = trimmedDisplayName.lowercased().replacingOccurrences(of: " ", with: "-")

        validationErrors = customModelManager.validateModelDetails(
            name: generatedName,
            displayName: trimmedDisplayName,
            apiEndpoint: trimmedEndpoint,
            modelName: trimmedModelName,
            excludingId: editingModel?.id
        )

        if trimmedKey.isEmpty {
            validationErrors.append(String(localized: "API key cannot be empty"))
        }

        guard validationErrors.isEmpty else { return }
        isSaving = true

        let model = CustomCloudModel(
            id: editingModel?.id ?? UUID(),
            name: generatedName,
            displayName: trimmedDisplayName,
            description: "Custom transcription model",
            apiEndpoint: trimmedEndpoint,
            modelName: trimmedModelName,
            isMultilingual: isMultilingual
        )

        let didSave =
            isEditing
            ? customModelManager.updateCustomModel(model, apiKey: trimmedKey)
            : customModelManager.addCustomModel(model, apiKey: trimmedKey)

        guard didSave else {
            validationErrors = [String(localized: "Failed to save API key securely")]
            isSaving = false
            return
        }

        isSaving = false
        onSave()
    }
}

struct CustomEnhancementModelEditorPanel: View {
    let editingProvider: CustomAIProviderConfig?
    @ObservedObject var manager: CustomAIProviderManager
    let onClose: () -> Void
    let onSave: () -> Void

    @State private var displayName = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var connectionTest: ConnectionTestState = .idle
    @State private var connectionTestTask: Task<Void, Never>?

    private var isEditing: Bool {
        editingProvider != nil
    }

    private var canTestConnection: Bool {
        !baseURL.trimmed.isEmpty && !apiKey.trimmed.isEmpty && !modelName.trimmed.isEmpty
    }

    private var canSave: Bool {
        canTestConnection && !displayName.trimmed.isEmpty
    }

    private func resetConnectionTest() {
        ConnectionTestRunner.reset(task: $connectionTestTask, state: $connectionTest)
    }

    private func runConnectionTest() {
        let url = baseURL.trimmed
        let key = apiKey.trimmed
        let model = modelName.trimmed

        ConnectionTestRunner.run(task: $connectionTestTask, state: $connectionTest) {
            await CustomModelConnectionTester.testEnhancementEndpoint(
                baseURL: url,
                apiKey: key,
                modelName: model
            )
        }
    }

    var body: some View {
        QuickPanelScaffold {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    CustomModelEditorSection(title: "Details") {
                        VStack(spacing: 10) {
                            CustomModelTextField(
                                label: "Display Name", placeholder: String(localized: "My Enhancement Model"),
                                text: $displayName)
                            CustomModelTextField(
                                label: "Base URL", placeholder: "https://api.openai.com/v1/chat/completions",
                                text: $baseURL)
                            CustomModelTextField(
                                label: "API Key", placeholder: String(localized: "Paste API key"), text: $apiKey,
                                isSecure: true)
                            CustomModelTextField(label: "Model Name", placeholder: "gpt-5.5", text: $modelName)
                            ConnectionTestRow(
                                state: connectionTest, isDisabled: !canTestConnection, action: runConnectionTest)
                        }
                    }

                    ConnectionTestResultBox(state: connectionTest)

                    if let errorMessage {
                        CustomModelErrorBox(messages: [errorMessage])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 76)
                .padding(.bottom, 72)
            }
        } header: {
            CustomModelEditorHeader(
                title: isEditing
                    ? "Edit Custom Enhancement Model" : "Add Custom Enhancement Model",
                onClose: onClose
            )
        } footer: {
            CustomModelEditorFooter(
                primaryTitle: isSaving ? "Saving" : isEditing ? "Save Changes" : "Add Model",
                isPrimaryDisabled: !canSave || isSaving,
                onCancel: onClose,
                onPrimary: saveProvider
            )
        }
        .onAppear(perform: loadProvider)
        .onChange(of: editingProvider?.id) { _, _ in
            loadProvider()
        }
        .onConnectionFieldsChange(baseURL, apiKey, modelName, perform: resetConnectionTest)
    }

    private func loadProvider() {
        if let editingProvider {
            displayName = editingProvider.name
            baseURL = editingProvider.baseURL
            apiKey = APIKeyManager.shared.getCustomAIProviderAPIKey(forProviderId: editingProvider.id) ?? ""
            modelName = editingProvider.modelName
        } else {
            displayName = ""
            baseURL = "https://api.openai.com/v1/chat/completions"
            apiKey = ""
            modelName = "gpt-5.5"
        }

        errorMessage = nil
        isSaving = false
        resetConnectionTest()
    }

    private func saveProvider() {
        let trimmedName = displayName.trimmed
        let trimmedURL = baseURL.trimmed
        let trimmedKey = apiKey.trimmed
        let trimmedModelName = modelName.trimmed

        var validationErrors = manager.validateProvider(
            name: trimmedName,
            baseURL: trimmedURL,
            model: trimmedModelName,
            excluding: editingProvider?.id
        )

        if trimmedKey.isEmpty {
            validationErrors.append(String(localized: "API key cannot be empty"))
        }

        guard validationErrors.isEmpty else {
            errorMessage = validationErrors.joined(separator: "\n")
            return
        }

        errorMessage = nil

        let provider = CustomAIProviderConfig(
            id: editingProvider?.id ?? UUID(),
            name: trimmedName,
            baseURL: trimmedURL,
            models: [trimmedModelName],
            selectedModel: trimmedModelName
        )

        isSaving = true
        let didSave =
            isEditing
            ? manager.updateProvider(provider, apiKey: trimmedKey)
            : manager.addProvider(provider, apiKey: trimmedKey)
        isSaving = false

        if didSave {
            onSave()
        } else if isEditing {
            errorMessage = String(localized: "Failed to save custom enhancement model")
        } else {
            errorMessage = String(localized: "Failed to save API key securely")
        }
    }
}

// MARK: - Shared editor logic

fileprivate extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Connection-test task handling shared by both editor panels. Each panel keeps its own
/// `@State` and passes bindings, so cancellation order and state transitions stay per panel.
private enum ConnectionTestRunner {
    @MainActor
    static func reset(task: Binding<Task<Void, Never>?>, state: Binding<ConnectionTestState>) {
        task.wrappedValue?.cancel()
        task.wrappedValue = nil
        state.wrappedValue = .idle
    }

    @MainActor
    static func run(
        task: Binding<Task<Void, Never>?>,
        state: Binding<ConnectionTestState>,
        test: @escaping @Sendable () async -> ConnectionTestResult
    ) {
        task.wrappedValue?.cancel()
        state.wrappedValue = .testing

        task.wrappedValue = Task {
            let result = await test()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                state.wrappedValue = ConnectionTestState(result: result)
            }
        }
    }
}

private extension View {
    /// Resets the connection test whenever any of the three connection fields changes.
    func onConnectionFieldsChange(
        _ first: String, _ second: String, _ third: String, perform action: @escaping () -> Void
    ) -> some View {
        onChange(of: first) { _, _ in action() }
            .onChange(of: second) { _, _ in action() }
            .onChange(of: third) { _, _ in action() }
    }
}

// MARK: - Editor components

private enum CustomModelEditorMetrics {
    static let labelWidth: CGFloat = 112
    static let fieldMaxWidth: CGFloat = 220
}

private struct CustomModelEditorSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: () -> Content

    init(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content()
            }
            .padding(12)
            .background(ProviderSurface(cornerRadius: 10))
        }
    }
}

private struct CustomModelTextField: View {
    let label: LocalizedStringKey
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField("", text: $text, prompt: Text(verbatim: placeholder))
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .frame(maxWidth: CustomModelEditorMetrics.fieldMaxWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ConnectionTestState: Equatable {
    case idle
    case testing
    case success
    case failure(message: String)

    init(result: ConnectionTestResult) {
        switch result {
        case .success:
            self = .success
        case .failure(let message):
            self = .failure(message: message)
        }
    }

    var isTesting: Bool {
        self == .testing
    }
}

private struct ConnectionTestRow: View {
    let state: ConnectionTestState
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Connection")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: "wifi")
                        .font(.system(size: 11))
                    Text("Test")
                        .font(.system(size: 12))
                }
            }
            .disabled(isDisabled || state.isTesting)

            inlineStatus

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inlineStatus: some View {
        switch state {
        case .idle, .failure:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Testing…")
            }
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.Text.secondary)
        case .success:
            Label("Test successful", systemImage: "checkmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.Status.positive)
                .lineLimit(1)
        }
    }
}

private struct ConnectionTestResultBox: View {
    let state: ConnectionTestState

    @ViewBuilder
    var body: some View {
        switch state {
        case .idle, .testing, .success:
            EmptyView()
        case .failure(let message):
            CustomModelErrorBox(messages: [message])
        }
    }
}

private struct CustomModelToggleRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: CustomModelEditorMetrics.labelWidth, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CustomModelErrorBox: View {
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(messages, id: \.self) { message in
                Text(message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Status.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ProviderSurface(cornerRadius: 10))
    }
}

private struct CustomModelEditorHeader: View {
    let title: LocalizedStringKey
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()

            AppIconButton(
                systemName: "xmark",
                help: "Close",
                size: 28,
                iconSize: 14,
                cornerRadius: AppTheme.Radius.control,
                action: onClose
            )
        }
        .padding(.horizontal, 20)
        .frame(height: QuickPanelMetrics.headerHeight)
    }
}

private struct CustomModelEditorFooter: View {
    let primaryTitle: LocalizedStringKey
    let isPrimaryDisabled: Bool
    let onCancel: () -> Void
    let onPrimary: () -> Void

    var body: some View {
        HStack {
            AppActionButton("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Spacer()

            AppActionButton(primaryTitle, kind: .primary, action: onPrimary)
                .disabled(isPrimaryDisabled)
        }
        .padding(.horizontal, 20)
        .frame(height: QuickPanelMetrics.footerHeight)
    }
}
