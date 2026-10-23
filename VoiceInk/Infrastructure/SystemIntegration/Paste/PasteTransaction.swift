import Foundation

/// Pure decision for one dictation paste: when to restore the previous clipboard,
/// when to leave the clipboard alone, and whether to send a submit key.
///
/// The caller records what it has observed so far (all times on one monotonic clock)
/// and asks for the decision at `now`. `.wait(until:)` means "ask again by then, or
/// sooner if something new is observed"; `.finish` ends the transaction.
struct PasteTransaction: Equatable {
    enum PasteKey: Equatable {
        /// The paste key has not been attempted yet.
        case pending
        /// The paste key went out; `at` is when the attempt started, so a read the
        /// destination makes while the key events are still being posted counts.
        case posted(at: TimeInterval)
        case notPosted
    }

    /// Key sent once the destination's read has settled. Not persisted.
    enum SubmitKey: Equatable {
        case none
        case enter
        case commandEnter
    }

    enum ClipboardAction: Equatable {
        case restorePrevious
        case leaveTranscript
        /// Someone else took clipboard ownership during the wait; their copy stays.
        case leaveUserCopy
    }

    enum Decision: Equatable {
        case wait(until: TimeInterval)
        case finish(clipboard: ClipboardAction, submitKey: SubmitKey)
    }

    /// Reads must be quiet this long before the transcript counts as read.
    static let readQuietPeriod: TimeInterval = 0.2
    /// Measured from publication: restore even if nothing read the transcript.
    static let unreadRestoreDeadline: TimeInterval = 8
    /// Measured from publication: restore quickly when the paste key never went out.
    static let notPostedRestoreDelay: TimeInterval = 0.5

    var publishedAt: TimeInterval
    var restoreEnabled: Bool
    var submitKey: SubmitKey = .none
    var pasteKey: PasteKey = .pending
    /// Every observed read of the transcript; reads before the paste key are ignored here.
    var readTimes: [TimeInterval] = []
    var ownershipTaken = false

    /// Whether the caller has to watch for reads at all. With restore off and no
    /// submit key, the transcript simply stays on the clipboard.
    var needsReadObservation: Bool {
        restoreEnabled || submitKey != .none
    }

    func decision(at now: TimeInterval) -> Decision {
        if ownershipTaken {
            return .finish(clipboard: .leaveUserCopy, submitKey: .none)
        }
        guard needsReadObservation else {
            return .finish(clipboard: .leaveTranscript, submitKey: .none)
        }

        let settledClipboard: ClipboardAction = restoreEnabled ? .restorePrevious : .leaveTranscript
        let deadline = publishedAt + Self.unreadRestoreDeadline

        switch pasteKey {
        case .notPosted:
            guard restoreEnabled else {
                return .finish(clipboard: .leaveTranscript, submitKey: .none)
            }
            let restoreAt = publishedAt + Self.notPostedRestoreDelay
            return now >= restoreAt
                ? .finish(clipboard: .restorePrevious, submitKey: .none)
                : .wait(until: restoreAt)

        case .pending:
            return now >= deadline
                ? .finish(clipboard: settledClipboard, submitKey: .none)
                : .wait(until: deadline)

        case .posted(let postedAt):
            let settleAt = readTimes.filter { $0 >= postedAt }.max().map { $0 + Self.readQuietPeriod }
            if let settleAt, settleAt <= deadline, now >= settleAt {
                return .finish(clipboard: settledClipboard, submitKey: submitKey)
            }
            if now >= deadline {
                return .finish(clipboard: settledClipboard, submitKey: .none)
            }
            return .wait(until: min(settleAt ?? deadline, deadline))
        }
    }
}
