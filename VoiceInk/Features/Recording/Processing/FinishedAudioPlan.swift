import Foundation

/// Where finished audio is cut for a short-window batch model.
///
/// Audio of 40 s or less is one piece. Longer audio is cut at the silence point nearest 30 s,
/// looking only between 20 s and 45 s into the current piece; without silence there it is cut
/// hard at 45 s, even inside a word (at 30 s when less than 45 s remains). Pieces never overlap.
enum FinishedAudioPlan {
    static let sampleRate = 16_000
    static let singlePieceLimitSeconds = 40
    static let preferredCutSeconds = 30
    static let earliestCutSeconds = 20
    static let hardCutSeconds = 45

    /// - Parameters:
    ///   - sampleCount: Length of the finished audio in 16 kHz samples.
    ///   - silenceRanges: Sample ranges considered silent, in any order.
    /// - Returns: Contiguous, non-overlapping sample ranges covering `0..<sampleCount`, in order.
    static func pieces(
        kind: FinishedAudioModelKind,
        sampleCount: Int,
        silenceRanges: [Range<Int>],
        sampleRate: Int = FinishedAudioPlan.sampleRate
    ) -> [Range<Int>] {
        guard sampleCount > 0 else { return [] }
        guard kind == .shortWindowBatch else { return [0..<sampleCount] }

        let singlePieceLimit = singlePieceLimitSeconds * sampleRate
        let preferred = preferredCutSeconds * sampleRate
        let earliest = earliestCutSeconds * sampleRate
        let hardCut = hardCutSeconds * sampleRate

        var pieces: [Range<Int>] = []
        var start = 0
        while sampleCount - start > singlePieceLimit {
            // Every cut leaves at least one sample for the next piece.
            let lastCut = sampleCount - 1
            let fallbackCut = start + hardCut <= lastCut ? start + hardCut : start + preferred
            let cut = silenceCut(
                in: silenceRanges,
                lowerBound: start + earliest,
                upperBound: min(start + hardCut, lastCut),
                target: start + preferred
            ) ?? fallbackCut
            pieces.append(start..<cut)
            start = cut
        }
        pieces.append(start..<sampleCount)
        return pieces
    }

    /// The silent sample nearest `target` within `lowerBound...upperBound`; the earlier one wins a tie.
    private static func silenceCut(
        in silenceRanges: [Range<Int>],
        lowerBound: Int,
        upperBound: Int,
        target: Int
    ) -> Int? {
        var best: Int?
        for range in silenceRanges where !range.isEmpty {
            let low = max(range.lowerBound, lowerBound)
            let high = min(range.upperBound - 1, upperBound)
            guard low <= high else { continue }
            let candidate = min(max(target, low), high)
            if let current = best {
                let candidateDistance = abs(candidate - target)
                let currentDistance = abs(current - target)
                if candidateDistance < currentDistance || (candidateDistance == currentDistance && candidate < current) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        return best
    }
}
