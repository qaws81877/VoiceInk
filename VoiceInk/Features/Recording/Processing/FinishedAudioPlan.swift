import Foundation

/// Where finished audio is cut for a short-window batch model.
///
/// With the default thresholds, audio of 40 s or less is one piece. Longer audio is cut at the
/// silence point nearest 30 s, looking only between 20 s and 45 s into the current piece; without
/// silence there it is cut hard at 45 s, even inside a word (at 30 s when less than 45 s remains).
/// A model that publishes a shorter input limit scales these down (`Thresholds`). Pieces never overlap.
enum FinishedAudioPlan {
    static let sampleRate = 16_000

    /// The cut points in seconds, measured from the start of the current piece.
    struct Thresholds: Equatable {
        /// Audio at or below this length is one piece.
        let singlePieceSeconds: Double
        /// The silence search prefers a cut nearest this point.
        let preferredCutSeconds: Double
        /// Silence before this point is ignored.
        let earliestCutSeconds: Double
        /// No piece is longer than this.
        let hardCutSeconds: Double

        static let `default` = Thresholds(
            singlePieceSeconds: 40,
            preferredCutSeconds: 30,
            earliestCutSeconds: 20,
            hardCutSeconds: 45
        )

        /// Room left below a model's input limit, so a piece never sits exactly on it.
        static let limitMarginSeconds = 1.0

        private init(
            singlePieceSeconds: Double,
            preferredCutSeconds: Double,
            earliestCutSeconds: Double,
            hardCutSeconds: Double
        ) {
            self.singlePieceSeconds = singlePieceSeconds
            self.preferredCutSeconds = preferredCutSeconds
            self.earliestCutSeconds = earliestCutSeconds
            self.hardCutSeconds = hardCutSeconds
        }

        /// - Parameter maximumInputMilliseconds: The longest audio the model accepts in one run, or
        ///   zero (or less) when it publishes no limit. Below the default hard cut, both the one-piece
        ///   threshold and the hard cut drop to the limit minus a margin (at most 10% of the limit),
        ///   and the preferred and earliest cuts shrink in proportion so they stay below the hard cut.
        init(maximumInputMilliseconds: Int64) {
            let base = Thresholds.default
            guard maximumInputMilliseconds > 0 else {
                self = base
                return
            }
            let limit = Double(maximumInputMilliseconds) / 1_000
            let usable = limit - min(Thresholds.limitMarginSeconds, limit * 0.1)
            guard usable < base.hardCutSeconds else {
                self = base
                return
            }
            let scale = usable / base.hardCutSeconds
            self.init(
                singlePieceSeconds: min(base.singlePieceSeconds, usable),
                preferredCutSeconds: base.preferredCutSeconds * scale,
                earliestCutSeconds: base.earliestCutSeconds * scale,
                hardCutSeconds: usable
            )
        }
    }

    /// - Parameters:
    ///   - sampleCount: Length of the finished audio in 16 kHz samples.
    ///   - silenceRanges: Sample ranges considered silent, in any order.
    ///   - thresholds: Cut points, scaled to the model's input limit when it has one.
    /// - Returns: Contiguous, non-overlapping sample ranges covering `0..<sampleCount`, in order.
    static func pieces(
        kind: FinishedAudioModelKind,
        sampleCount: Int,
        silenceRanges: [Range<Int>],
        thresholds: Thresholds = .default,
        sampleRate: Int = FinishedAudioPlan.sampleRate
    ) -> [Range<Int>] {
        guard sampleCount > 0 else { return [] }
        guard kind == .shortWindowBatch else { return [0..<sampleCount] }

        func samples(_ seconds: Double) -> Int { max(1, Int(seconds * Double(sampleRate))) }
        let singlePieceLimit = samples(thresholds.singlePieceSeconds)
        let preferred = samples(thresholds.preferredCutSeconds)
        let earliest = samples(thresholds.earliestCutSeconds)
        let hardCut = samples(thresholds.hardCutSeconds)

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
