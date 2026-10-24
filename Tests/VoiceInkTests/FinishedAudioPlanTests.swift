import XCTest
@testable import VoiceInk

final class FinishedAudioPlanTests: XCTestCase {
    private let rate = 16_000

    private func seconds(_ value: Double) -> Int {
        Int(value * Double(rate))
    }

    // MARK: - Model kind

    func testWhisperAppleSpeechAndParakeetStayOnePiece() {
        for provider in [ModelProvider.whisper, .nativeApple, .fluidAudio] {
            XCTAssertEqual(
                FinishedAudioModelKind.classify(provider: provider, supportsStreaming: false),
                .singlePiece,
                "\(provider)"
            )
        }
    }

    func testTranscribeCppAndNonStreamingCloudModelsAreShortWindow() {
        let shortWindowProviders: [ModelProvider] = [
            .transcribeCpp, .groq, .elevenLabs, .deepgram, .mistral, .gemini, .soniox,
            .speechmatics, .assemblyAI, .xai, .cartesia, .openRouter, .custom,
        ]
        for provider in shortWindowProviders {
            XCTAssertEqual(
                FinishedAudioModelKind.classify(provider: provider, supportsStreaming: false),
                .shortWindowBatch,
                "\(provider)"
            )
        }
    }

    func testAnyStreamingCapableModelStaysOnePiece() {
        for provider in ModelProvider.allCases {
            XCTAssertEqual(
                FinishedAudioModelKind.classify(provider: provider, supportsStreaming: true),
                .singlePiece,
                "\(provider)"
            )
        }
    }

    // MARK: - Plan

    func testSinglePieceKindIsNeverCut() {
        let pieces = FinishedAudioPlan.pieces(
            kind: .singlePiece,
            sampleCount: seconds(600),
            silenceRanges: [seconds(30)..<seconds(31)]
        )
        XCTAssertEqual(pieces, [0..<seconds(600)])
    }

    func testFortySecondsOrLessStaysOnePiece() {
        let pieces = FinishedAudioPlan.pieces(
            kind: .shortWindowBatch,
            sampleCount: seconds(40),
            silenceRanges: [seconds(30)..<seconds(31)]
        )
        XCTAssertEqual(pieces, [0..<seconds(40)])
    }

    func testJustOverFortySecondsIsCut() {
        let pieces = FinishedAudioPlan.pieces(
            kind: .shortWindowBatch,
            sampleCount: seconds(40) + 1,
            silenceRanges: []
        )
        XCTAssertEqual(pieces, [0..<seconds(30), seconds(30)..<(seconds(40) + 1)])
    }

    func testUnderFortyFiveSecondsWithoutSilenceCutsAtThirty() {
        let pieces = FinishedAudioPlan.pieces(
            kind: .shortWindowBatch,
            sampleCount: seconds(42),
            silenceRanges: []
        )
        XCTAssertEqual(pieces, [0..<seconds(30), seconds(30)..<seconds(42)])
    }

    func testSilenceAtTheVeryEndDoesNotLeaveAnEmptyPiece() {
        let pieces = FinishedAudioPlan.pieces(
            kind: .shortWindowBatch,
            sampleCount: seconds(42),
            silenceRanges: [seconds(41)..<seconds(42)]
        )
        XCTAssertEqual(pieces, [0..<seconds(41), seconds(41)..<seconds(42)])
    }

    func testCutsInsideSilenceThatContainsThirtySeconds() {
        let pieces = FinishedAudioPlan.pieces(
            kind: .shortWindowBatch,
            sampleCount: seconds(50),
            silenceRanges: [seconds(28)..<seconds(33)]
        )
        XCTAssertEqual(pieces, [0..<seconds(30), seconds(30)..<seconds(50)])
    }

    func testPrefersTheSilenceNearestThirtySeconds() {
        let pieces = FinishedAudioPlan.pieces(
            kind: .shortWindowBatch,
            sampleCount: seconds(50),
            silenceRanges: [
                seconds(22)..<seconds(23),
                seconds(33)..<seconds(34),
                seconds(43)..<seconds(44),
            ]
        )
        XCTAssertEqual(pieces, [0..<seconds(33), seconds(33)..<seconds(50)])
    }

    func testIgnoresSilenceTooEarlyToMakeAUsefulPiece() {
        let pieces = FinishedAudioPlan.pieces(
            kind: .shortWindowBatch,
            sampleCount: seconds(50),
            silenceRanges: [seconds(5)..<seconds(6)]
        )
        XCTAssertEqual(pieces, [0..<seconds(45), seconds(45)..<seconds(50)])
    }

    func testHardCutsAtFortyFiveSecondsWithoutSilence() {
        let pieces = FinishedAudioPlan.pieces(
            kind: .shortWindowBatch,
            sampleCount: seconds(100),
            silenceRanges: []
        )
        XCTAssertEqual(
            pieces,
            [0..<seconds(45), seconds(45)..<seconds(90), seconds(90)..<seconds(100)]
        )
    }

    func testTailOfFortySecondsOrLessStaysOnePiece() {
        let pieces = FinishedAudioPlan.pieces(
            kind: .shortWindowBatch,
            sampleCount: seconds(85),
            silenceRanges: []
        )
        XCTAssertEqual(pieces, [0..<seconds(45), seconds(45)..<seconds(85)])
    }

    func testSilenceIsMeasuredFromEachPieceStart() {
        let pieces = FinishedAudioPlan.pieces(
            kind: .shortWindowBatch,
            sampleCount: seconds(120),
            silenceRanges: [seconds(30)..<seconds(31), seconds(61)..<seconds(62)]
        )
        XCTAssertEqual(
            pieces,
            [
                0..<seconds(30),
                seconds(30)..<seconds(61),
                seconds(61)..<seconds(106),
                seconds(106)..<seconds(120),
            ]
        )
    }

    func testPiecesAreContiguousNonOverlappingAndAtMostFortyFiveSeconds() {
        let silence = stride(from: 7.0, to: 600.0, by: 13.0).map { seconds($0)..<seconds($0 + 0.4) }
        let total = seconds(600) + 123
        let pieces = FinishedAudioPlan.pieces(kind: .shortWindowBatch, sampleCount: total, silenceRanges: silence)

        XCTAssertEqual(pieces.first?.lowerBound, 0)
        XCTAssertEqual(pieces.last?.upperBound, total)
        for (left, right) in zip(pieces, pieces.dropFirst()) {
            XCTAssertEqual(left.upperBound, right.lowerBound)
        }
        for piece in pieces {
            XCTAssertFalse(piece.isEmpty)
            XCTAssertLessThanOrEqual(piece.count, seconds(45))
        }
    }
}
