import XCTest

@testable import VoiceInk

final class PasteTransactionTests: XCTestCase {
    private let published: TimeInterval = 100

    private func transaction(
        restore: Bool = true,
        pasteKey: PasteTransaction.PasteKey = .posted(at: 100.1),
        reads: [TimeInterval] = [],
        ownershipTaken: Bool = false,
        submitKey: PasteTransaction.SubmitKey = .none
    ) -> PasteTransaction {
        PasteTransaction(
            publishedAt: published,
            restoreEnabled: restore,
            submitKey: submitKey,
            pasteKey: pasteKey,
            readTimes: reads,
            ownershipTaken: ownershipTaken
        )
    }

    func testPasteKeyNeverPostedRestoresAboutHalfASecondAfterPublication() {
        let tx = transaction(pasteKey: .notPosted)
        XCTAssertEqual(tx.decision(at: 100.2), .wait(until: 100.5))
        XCTAssertEqual(tx.decision(at: 100.5), .finish(clipboard: .restorePrevious, submitKey: .none))
    }

    func testReadBeforePasteKeyDoesNotRestore() {
        // A clipboard manager (or Sulsul itself) reads right after publication.
        let tx = transaction(pasteKey: .posted(at: 100.1), reads: [100.02])
        XCTAssertEqual(tx.decision(at: 100.5), .wait(until: 108))
    }

    func testReadsBeforePasteKeyIsAttemptedDoNotCount() {
        let tx = transaction(pasteKey: .pending, reads: [100.02])
        XCTAssertEqual(tx.decision(at: 100.5), .wait(until: 108))
    }

    func testCountedReadRestoresOnlyAfterReadsAreQuietFor200ms() {
        let tx = transaction(reads: [100.25])
        XCTAssertEqual(tx.decision(at: 100.3), .wait(until: 100.45))
        XCTAssertEqual(tx.decision(at: 100.45), .finish(clipboard: .restorePrevious, submitKey: .none))
    }

    func testRepeatedReadsKeepTheTranscriptUntilTheLastReadSettles() {
        let tx = transaction(reads: [100.125, 100.25, 100.375])
        XCTAssertEqual(tx.decision(at: 100.5), .wait(until: 100.575))
        XCTAssertEqual(tx.decision(at: 100.575), .finish(clipboard: .restorePrevious, submitKey: .none))
    }

    func testReadDuringPasteKeyPostingCounts() {
        // `posted(at:)` is when the attempt started; Cmd-V events are still going out.
        let tx = transaction(pasteKey: .posted(at: 100.1), reads: [100.1])
        XCTAssertEqual(tx.decision(at: 100.3), .finish(clipboard: .restorePrevious, submitKey: .none))
    }

    func testUnreadTranscriptRestoresEightSecondsAfterPublication() {
        let tx = transaction()
        XCTAssertEqual(tx.decision(at: 104), .wait(until: 108))
        XCTAssertEqual(tx.decision(at: 108), .finish(clipboard: .restorePrevious, submitKey: .none))
    }

    func testReadsThatNeverSettleBeforeTheCapRestoreAtTheCap() {
        let tx = transaction(reads: [107.875])
        XCTAssertEqual(tx.decision(at: 107.95), .wait(until: 108))
        XCTAssertEqual(tx.decision(at: 108), .finish(clipboard: .restorePrevious, submitKey: .none))
    }

    func testUserCopyDuringTheWaitIsLeftInPlace() {
        let tx = transaction(reads: [100.25], ownershipTaken: true)
        XCTAssertEqual(tx.decision(at: 100.2), .finish(clipboard: .leaveUserCopy, submitKey: .none))
        XCTAssertEqual(
            transaction(pasteKey: .notPosted, ownershipTaken: true).decision(at: 100.2),
            .finish(clipboard: .leaveUserCopy, submitKey: .none)
        )
    }

    func testRestoreOffLeavesTheTranscriptWithoutWaiting() {
        XCTAssertEqual(
            transaction(restore: false, pasteKey: .pending).decision(at: 100),
            .finish(clipboard: .leaveTranscript, submitKey: .none)
        )
        XCTAssertEqual(
            transaction(restore: false, pasteKey: .notPosted).decision(at: 100.2),
            .finish(clipboard: .leaveTranscript, submitKey: .none)
        )
        XCTAssertFalse(transaction(restore: false).needsReadObservation)
        XCTAssertTrue(transaction(restore: true).needsReadObservation)
    }

    // MARK: - Submit key (the mode field and UI arrive with ticket #6)

    func testSubmitKeyIsSentAtTheSettledReadEvenWithRestoreOff() {
        let tx = transaction(restore: false, reads: [100.25], submitKey: .enter)
        XCTAssertTrue(tx.needsReadObservation)
        XCTAssertEqual(tx.decision(at: 100.3), .wait(until: 100.45))
        XCTAssertEqual(tx.decision(at: 100.45), .finish(clipboard: .leaveTranscript, submitKey: .enter))
        XCTAssertEqual(
            transaction(reads: [100.25], submitKey: .commandEnter).decision(at: 100.45),
            .finish(clipboard: .restorePrevious, submitKey: .commandEnter)
        )
    }

    func testSubmitKeyIsNotSentWithoutASettledRead() {
        XCTAssertEqual(
            transaction(submitKey: .enter).decision(at: 108),
            .finish(clipboard: .restorePrevious, submitKey: .none)
        )
        XCTAssertEqual(
            transaction(pasteKey: .notPosted, submitKey: .enter).decision(at: 100.5),
            .finish(clipboard: .restorePrevious, submitKey: .none)
        )
        XCTAssertEqual(
            transaction(restore: false, pasteKey: .notPosted, submitKey: .enter).decision(at: 100.2),
            .finish(clipboard: .leaveTranscript, submitKey: .none)
        )
        XCTAssertEqual(
            transaction(reads: [100.25], ownershipTaken: true, submitKey: .enter).decision(at: 100.4),
            .finish(clipboard: .leaveUserCopy, submitKey: .none)
        )
    }
}
