import Foundation

extension Transcription {
    /// Whether this transcription is a usable result to list on the dashboard:
    /// non-empty text, not failed or canceled, and not a stored failure message.
    var isDashboardDisplayable: Bool {
        let text = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return false
        }

        if transcriptionStatus == TranscriptionStatus.failed.rawValue
            || transcriptionStatus == TranscriptionStatus.canceled.rawValue
        {
            return false
        }

        return text.range(of: "Transcription Failed:", options: [.caseInsensitive, .anchored]) == nil
    }
}
