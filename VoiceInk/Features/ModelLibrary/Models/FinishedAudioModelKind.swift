import Foundation

/// Whether a model may receive finished audio in several pieces (see `FinishedAudioPlan`).
///
/// Each `TranscriptionModel` type declares its own kind next to `supportsStreaming`, so new
/// providers decide it where they are described instead of in a provider switch elsewhere.
enum FinishedAudioModelKind: Equatable {
    /// Whisper, Apple Speech, Parakeet/FluidAudio and any streaming-capable model.
    case singlePiece
    /// SenseVoice, Cohere (transcribe.cpp) and non-streaming cloud models.
    case shortWindowBatch
}
