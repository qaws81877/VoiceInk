import XCTest
@testable import VoiceInk

final class FinishedAudioPlanTests: XCTestCase {
    private let rate = 16_000

    private func seconds(_ value: Double) -> Int {
        Int(value * Double(rate))
    }

    // MARK: - Model kind

    private let languages = ["en": "English", "ko": "Korean"]

    func testWhisperAppleSpeechAndParakeetStayOnePiece() {
        let whisper = WhisperModel(
            name: "w", displayName: "W", size: "1", supportedLanguages: languages, description: "",
            speed: 1, accuracy: 1, ramUsage: 1
        )
        let imported = ImportedWhisperModel(fileBaseName: "imported")
        let apple = NativeAppleModel(
            name: "a", displayName: "A", description: "", isMultilingualModel: true, supportedLanguages: languages
        )
        let parakeet = FluidAudioModel(
            name: "p", displayName: "P", description: "", size: "1", speed: 1, accuracy: 1, ramUsage: 1,
            supportsStreaming: false, supportedLanguages: languages
        )
        let models: [any TranscriptionModel] = [whisper, imported, apple, parakeet]
        for model in models {
            XCTAssertEqual(model.finishedAudioKind, .singlePiece, model.name)
        }
    }

    func testTranscribeCppAndNonStreamingCloudModelsAreShortWindow() {
        let cohere = TranscribeCppModel(
            name: "c", displayName: "C", description: "", size: "1", speed: 1, accuracy: 1, ramUsage: 1,
            publisher: "", supportedLanguages: languages
        )
        let cloud = CloudModel(
            name: "g", displayName: "G", description: "", provider: .groq, isMultilingual: true,
            supportsStreaming: false, supportedLanguages: languages
        )
        let custom = CustomCloudModel(
            name: "x", displayName: "X", description: "", apiEndpoint: "https://example.invalid", modelName: "m"
        )
        let models: [any TranscriptionModel] = [cohere, cloud, custom]
        for model in models {
            XCTAssertEqual(model.finishedAudioKind, .shortWindowBatch, model.name)
        }
    }

    func testStreamingCapableCloudModelStaysOnePiece() {
        let cloud = CloudModel(
            name: "d", displayName: "D", description: "", provider: .deepgram, isMultilingual: true,
            supportsStreaming: true, supportedLanguages: languages
        )
        XCTAssertEqual(cloud.finishedAudioKind, .singlePiece)
    }

    func testBuiltInCloudModelsAreCutOnlyWhenTheyCannotStream() {
        let cloudModels = CloudProviderRegistry.allProviders.flatMap { $0.models }
        XCTAssertTrue(cloudModels.contains { $0.supportsStreaming })
        XCTAssertTrue(cloudModels.contains { !$0.supportsStreaming })
        for model in cloudModels {
            XCTAssertEqual(
                model.finishedAudioKind,
                model.supportsStreaming ? .singlePiece : .shortWindowBatch,
                model.name
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
