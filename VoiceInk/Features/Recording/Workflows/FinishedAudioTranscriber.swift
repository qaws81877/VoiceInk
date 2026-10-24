import Foundation
import os

/// Runs `FinishedAudioPlan` on a finished audio file: cuts it into piece files when the plan asks for
/// more than one piece, recognizes the pieces in order and joins them with `FinishedAudioJoin`.
///
/// Any piece that throws fails the whole call, so no partial transcript reaches the caller.
@MainActor
enum FinishedAudioTranscriber {
    private struct PreparedPieces: Sendable {
        let directory: URL
        let urls: [URL]
    }

    private static let logger = Logger(subsystem: AppIdentity.loggerSubsystem, category: "FinishedAudioTranscriber")

    static func transcribe(
        audioURL: URL,
        kind: FinishedAudioModelKind,
        thresholds: FinishedAudioPlan.Thresholds = .default,
        transcribePiece: (URL) async throws -> String
    ) async throws -> String {
        guard kind == .shortWindowBatch else {
            return try await transcribePiece(audioURL)
        }

        let duration = await AudioFileMetadata.duration(for: audioURL)
        if duration > 0, duration <= thresholds.singlePieceSeconds {
            return try await transcribePiece(audioURL)
        }

        let prepared = try await Task.detached(priority: .userInitiated) {
            try await preparePieces(of: audioURL, kind: kind, thresholds: thresholds)
        }.value
        guard let prepared else {
            return try await transcribePiece(audioURL)
        }
        defer { try? FileManager.default.removeItem(at: prepared.directory) }

        logger.notice("Transcribing finished audio in \(prepared.urls.count, privacy: .public) pieces")
        var texts: [String] = []
        texts.reserveCapacity(prepared.urls.count)
        for pieceURL in prepared.urls {
            try Task.checkCancellation()
            texts.append(try await transcribePiece(pieceURL))
        }
        return FinishedAudioJoin.join(texts)
    }

    /// Returns nil when the plan keeps the audio as one piece.
    nonisolated private static func preparePieces(
        of audioURL: URL,
        kind: FinishedAudioModelKind,
        thresholds: FinishedAudioPlan.Thresholds
    ) async throws
        -> PreparedPieces?
    {
        let processor = AudioProcessor()
        let samples = try await processor.processAudioToSamples(audioURL)
        let pieces = FinishedAudioPlan.pieces(
            kind: kind,
            sampleCount: samples.count,
            silenceRanges: FinishedAudioSilence.ranges(in: samples),
            thresholds: thresholds
        )
        guard pieces.count > 1 else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinishedAudioPieces-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let baseName = audioURL.deletingPathExtension().lastPathComponent
            var urls: [URL] = []
            for (index, range) in pieces.enumerated() {
                try Task.checkCancellation()
                let url = directory.appendingPathComponent("\(baseName)-piece\(index + 1).wav")
                try processor.saveSamplesAsWav(samples: Array(samples[range]), to: url)
                urls.append(url)
            }
            return PreparedPieces(directory: directory, urls: urls)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
