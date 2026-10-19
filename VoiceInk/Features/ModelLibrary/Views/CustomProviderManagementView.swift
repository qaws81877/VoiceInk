import SwiftUI

struct CustomProviderManagementView: View {
    @ObservedObject var customModelManager: CustomCloudModelManager
    @ObservedObject var customAIProviderManager: CustomAIProviderManager

    let onAddTranscriptionModel: () -> Void
    let onEditTranscriptionModel: (CustomCloudModel) -> Void
    let onDeleteTranscriptionModel: (CustomCloudModel) -> Void
    let onAddEnhancementModel: () -> Void
    let onEditEnhancementModel: (CustomAIProviderConfig) -> Void
    let onDeleteEnhancementModel: (CustomAIProviderConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            customTranscriptionSection
            customEnhancementSection
        }
    }

    private var customTranscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Custom Transcription Models",
                subtitle: "Supports any provider that uses the same API format as OpenAI transcription.",
                addHelp: "Add transcription model",
                onAdd: onAddTranscriptionModel
            )

            if customModelManager.customModels.isEmpty {
                CustomProviderEmptyState(
                    systemImage: "waveform",
                    title: "No Custom Transcription Models"
                )
            } else {
                ForEach(customModelManager.customModels) { model in
                    CustomModelCardView(
                        model: model,
                        deleteAction: {
                            onDeleteTranscriptionModel(model)
                        },
                        editAction: onEditTranscriptionModel
                    )
                }
            }
        }
    }

    private var customEnhancementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Custom Enhancement Models",
                subtitle: "Supports any provider that uses the same API format as OpenAI chat completion.",
                addHelp: "Add enhancement model",
                onAdd: onAddEnhancementModel
            )

            if customAIProviderManager.providers.isEmpty {
                CustomProviderEmptyState(
                    systemImage: "sparkles",
                    title: "No Custom Enhancement Models"
                )
            } else {
                ForEach(customAIProviderManager.providers) { provider in
                    CustomEnhancementModelRow(
                        provider: provider,
                        onEdit: {
                            onEditEnhancementModel(provider)
                        },
                        onDelete: {
                            onDeleteEnhancementModel(provider)
                        }
                    )
                }
            }
        }
    }

    private func sectionHeader(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        addHelp: LocalizedStringResource,
        onAdd: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderSectionHeader(title: title, subtitle: subtitle)

            Spacer(minLength: 8)

            AddIconButton(helpText: addHelp, action: onAdd)
        }
    }

}

private struct CustomProviderEmptyState: View {
    let systemImage: String
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .background(ProviderSurface(cornerRadius: 10))
    }
}

private struct CustomEnhancementModelRow: View {
    let provider: CustomAIProviderConfig
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(AppTheme.Surface.control)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(AppTheme.Border.control.opacity(0.45), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(provider.name)
                    .font(.system(size: 13, weight: .semibold))

                Group {
                    if provider.modelName.isEmpty {
                        Text("No model configured")
                    } else {
                        Text(provider.modelName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Menu {
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
        }
        .padding(14)
        .background(ProviderSurface(cornerRadius: 10))
    }
}

#if DEBUG
    private enum CustomModelsPreviewPanel {
        case transcription
        case enhancement
    }

    private struct CustomModelsSidePanelPreview: View {
        @State private var activePanel: CustomModelsPreviewPanel? = .transcription

        private var isPanelOpen: Binding<Bool> {
            Binding(
                get: { activePanel != nil },
                set: { if !$0 { activePanel = nil } }
            )
        }

        var body: some View {
            VStack(spacing: 0) {
                AppScreenHeader(title: "Model Catalog") {
                    AppIconButton(systemName: "plus.circle.fill", help: "Add custom model") {
                        activePanel = .transcription
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        customSectionHeader(
                            title: "Custom Transcription Models",
                            subtitle: "Supports any provider that uses the same API format as OpenAI transcription.",
                            action: { activePanel = .transcription }
                        )

                        CustomModelCardView(
                            model: Self.sampleTranscriptionModel,
                            deleteAction: {},
                            editAction: { _ in activePanel = .transcription }
                        )

                        customSectionHeader(
                            title: "Custom Enhancement Models",
                            subtitle: "Supports any provider that uses the same API format as OpenAI chat completion.",
                            action: { activePanel = .enhancement }
                        )

                        CustomEnhancementModelRow(
                            provider: Self.sampleEnhancementProvider,
                            onEdit: { activePanel = .enhancement },
                            onDelete: {}
                        )
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(width: 920, height: 640)
            .background(AppTheme.Surface.window)
            .sidePanel(isPresented: isPanelOpen) {
                panelContent
            }
        }

        @ViewBuilder
        private var panelContent: some View {
            switch activePanel {
            case .transcription:
                CustomTranscriptionModelEditorPanel(
                    editingModel: Self.sampleTranscriptionModel,
                    customModelManager: .shared,
                    onClose: { activePanel = nil },
                    onSave: { activePanel = nil }
                )
            case .enhancement:
                CustomEnhancementModelEditorPanel(
                    editingProvider: Self.sampleEnhancementProvider,
                    manager: .shared,
                    onClose: { activePanel = nil },
                    onSave: { activePanel = nil }
                )
            case nil:
                EmptyView()
            }
        }

        private func customSectionHeader(
            title: LocalizedStringKey, subtitle: LocalizedStringKey, action: @escaping () -> Void
        ) -> some View {
            HStack(alignment: .top, spacing: 12) {
                ProviderSectionHeader(title: title, subtitle: subtitle)

                Spacer()

                AddIconButton(helpText: "Add model", action: action)
            }
        }

        private static let sampleTranscriptionModel = CustomCloudModel(
            name: "acme-transcribe",
            displayName: "Acme Transcribe",
            description: "OpenAI-compatible transcription endpoint for previewing custom model cards.",
            apiEndpoint: "https://api.example.com/v1/audio/transcriptions",
            modelName: "acme-transcribe-large",
            isMultilingual: true
        )

        private static let sampleEnhancementProvider = CustomAIProviderConfig(
            name: "Acme Enhance",
            baseURL: "https://api.example.com/v1/chat/completions",
            models: ["acme-enhance-pro"],
            selectedModel: "acme-enhance-pro"
        )
    }

    #Preview("Custom AI Models - Side Panel") {
        CustomModelsSidePanelPreview()
    }
#endif
