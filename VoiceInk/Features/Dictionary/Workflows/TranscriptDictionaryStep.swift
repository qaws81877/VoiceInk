import Foundation
import SwiftData
import os

/// The dictionary text step every final transcript goes through before
/// cleanup: exact word replacement, then Latin spelling correction from the
/// vocabulary list. Live dictation, audio import and History re-transcription
/// all call this one function. Streaming partials never do.
@MainActor
enum TranscriptDictionaryStep {
    private static let logger = Logger(
        subsystem: AppIdentity.loggerSubsystem,
        category: "TranscriptDictionaryStep"
    )

    static func apply(to text: String, using context: ModelContext) -> String {
        let replaced = WordReplacementService.shared.applyReplacements(to: text, using: context)

        let vocabulary = CustomVocabularyService.shared.vocabularyTerms(from: context)
        guard !vocabulary.isEmpty else { return replaced }

        // Text written by a replacement rule is protected so an exact
        // replacement always wins over a fuzzy correction. If the rules cannot
        // be read, skip correction rather than risk overriding one.
        let replacementOutputs: [String]
        do {
            replacementOutputs = try context.fetch(FetchDescriptor<WordReplacement>()).map(\.replacementText)
        } catch {
            logger.error("Skipping Latin spelling correction: could not load word replacements: \(error, privacy: .public)")
            return replaced
        }

        let corrected = LatinSpellingCorrector.correct(
            replaced,
            vocabulary: vocabulary,
            protectedPhrases: replacementOutputs
        )
        logger.debug("Latin spelling correction changed output=\(corrected != replaced, privacy: .public)")
        return corrected
    }
}
