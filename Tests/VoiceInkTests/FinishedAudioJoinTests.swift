import XCTest
@testable import VoiceInk

final class FinishedAudioJoinTests: XCTestCase {
    // MARK: - Join

    func testTwoLatinSidesGetOneSpace() {
        XCTAssertEqual(FinishedAudioJoin.join(["Hello world", "this is Sulsul"]), "Hello world this is Sulsul")
    }

    func testPunctuationBeforeTheBoundaryStillCountsAsALatinSide() {
        XCTAssertEqual(FinishedAudioJoin.join(["It works.", "Next part"]), "It works. Next part")
    }

    func testHangulSidesAreJoinedWithoutAnInsertedSpace() {
        XCTAssertEqual(FinishedAudioJoin.join(["오늘은 회의가", "있습니다"]), "오늘은 회의가있습니다")
    }

    func testMixedLatinAndHangulSidesGetNoSpace() {
        XCTAssertEqual(FinishedAudioJoin.join(["회의 자료는", "Claude"]), "회의 자료는Claude")
        XCTAssertEqual(FinishedAudioJoin.join(["Claude", "가 정리했다"]), "Claude가 정리했다")
    }

    func testCJKSidesGetNoSpace() {
        XCTAssertEqual(FinishedAudioJoin.join(["今天天气", "很好"]), "今天天气很好")
    }

    func testAccentedLatinLettersAreLatin() {
        XCTAssertEqual(FinishedAudioJoin.join(["café", "été"]), "café été")
    }

    func testPiecesAreTrimmedAndEmptyPiecesDropped() {
        XCTAssertEqual(FinishedAudioJoin.join(["  first part ", "", "   ", "second part\n"]), "first part second part")
    }

    func testNoTextIsInventedForAllEmptyPieces() {
        XCTAssertEqual(FinishedAudioJoin.join(["", " "]), "")
        XCTAssertEqual(FinishedAudioJoin.join([]), "")
    }

    func testSinglePieceIsReturnedTrimmed() {
        XCTAssertEqual(FinishedAudioJoin.join([" 한 조각 "]), "한 조각")
    }

    // MARK: - Silence

    private let rate = 16_000

    private func speech(seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { $0.isMultiple(of: 2) ? 0.3 : -0.3 }
    }

    private func quiet(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(rate)))
    }

    func testFindsTheQuietGapInsideSpeech() {
        let samples = speech(seconds: 29) + quiet(seconds: 2) + speech(seconds: 29)
        let ranges = FinishedAudioSilence.ranges(in: samples)

        XCTAssertEqual(ranges, [(29 * rate)..<(31 * rate)])
    }

    func testContinuousSpeechHasNoSilence() {
        XCTAssertEqual(FinishedAudioSilence.ranges(in: speech(seconds: 10)), [])
    }

    func testQuietGapsAreFoundAboveARoomNoiseFloor() {
        let noise: (Double) -> [Float] = { seconds in
            (0..<Int(seconds * 16_000)).map { $0.isMultiple(of: 2) ? 0.01 : -0.01 }
        }
        let samples = speech(seconds: 10) + noise(1) + speech(seconds: 10) + noise(1) + speech(seconds: 10)
        let ranges = FinishedAudioSilence.ranges(in: samples)

        XCTAssertEqual(ranges, [(10 * rate)..<(11 * rate), (21 * rate)..<(22 * rate)])
    }

    func testEmptyAudioHasNoSilence() {
        XCTAssertEqual(FinishedAudioSilence.ranges(in: []), [])
    }
}
