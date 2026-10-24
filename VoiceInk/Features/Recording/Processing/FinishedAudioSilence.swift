import Foundation

/// Finds quiet stretches in finished 16 kHz audio, as input for `FinishedAudioPlan`.
///
/// The audio is measured in 100 ms windows. A window is silent when its RMS level is at most twice
/// the recording's quiet level (10th percentile), capped at half its speech level (90th percentile),
/// so the threshold follows the room noise of each recording instead of a fixed dBFS floor.
enum FinishedAudioSilence {
    static let samplesPerWindow = 1_600
    private static let absoluteSilence: Float = 0.000_1

    static func ranges(
        in samples: [Float],
        samplesPerWindow: Int = FinishedAudioSilence.samplesPerWindow
    ) -> [Range<Int>] {
        guard !samples.isEmpty, samplesPerWindow > 0 else { return [] }

        let levels = stride(from: 0, to: samples.count, by: samplesPerWindow).map { start -> Float in
            let end = min(start + samplesPerWindow, samples.count)
            var sum: Float = 0
            for index in start..<end {
                sum += samples[index] * samples[index]
            }
            return (sum / Float(end - start)).squareRoot()
        }

        let sorted = levels.sorted()
        let quietLevel = percentile(0.1, of: sorted)
        let speechLevel = percentile(0.9, of: sorted)
        let threshold = max(min(quietLevel * 2, speechLevel * 0.5), absoluteSilence)

        var ranges: [Range<Int>] = []
        var silentStart: Int?
        for (index, level) in levels.enumerated() {
            let start = index * samplesPerWindow
            if level <= threshold {
                if silentStart == nil { silentStart = start }
            } else if let open = silentStart {
                ranges.append(open..<start)
                silentStart = nil
            }
        }
        if let open = silentStart {
            ranges.append(open..<samples.count)
        }
        return ranges
    }

    private static func percentile(_ fraction: Double, of sorted: [Float]) -> Float {
        let index = Int((Double(sorted.count - 1) * fraction).rounded(.down))
        return sorted[index]
    }
}
