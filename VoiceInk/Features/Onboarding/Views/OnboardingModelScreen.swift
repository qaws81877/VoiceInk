import SwiftUI

struct OnboardingModelScreen: View {
    let contentMaxWidth: CGFloat
    let whisperModels: [WhisperModel]
    let selectedWhisperModelName: String
    let setupKind: OnboardingTranscriptionSetupKind
    let providerOptions: [any CloudProvider]
    @Binding var selectedProviderKey: String
    let isLocalDownloaded: Bool
    let isLocalDownloading: Bool
    let localDownloadProgress: Double?
    let isSetupReady: Bool
    let onSelectWhisperModel: (String) -> Void
    let onSelectSetupKind: (OnboardingTranscriptionSetupKind) -> Void
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onSkip: () -> Void
    let onVerificationChanged: () -> Void
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepScreen(
            stage: .model,
            contentMaxWidth: contentMaxWidth
        ) {
            OnboardingTranscriptionSetupCard(
                whisperModels: whisperModels,
                selectedWhisperModelName: selectedWhisperModelName,
                setupKind: setupKind,
                providerOptions: providerOptions,
                selectedProviderKey: $selectedProviderKey,
                isLocalDownloaded: isLocalDownloaded,
                isLocalDownloading: isLocalDownloading,
                localDownloadProgress: localDownloadProgress,
                onSelectWhisperModel: onSelectWhisperModel,
                onSelectSetupKind: onSelectSetupKind,
                onDownload: onDownload,
                onCancelDownload: onCancelDownload,
                onSkip: onSkip,
                onVerificationChanged: onVerificationChanged
            )
        } bottomBar: {
            OnboardingBottomBar(
                leadingTitle: "Back",
                primaryTitle: "Continue",
                isPrimaryEnabled: isSetupReady && !(setupKind == .local && isLocalDownloading),
                onLeading: onBack,
                onPrimary: onContinue
            )
        }
    }
}
