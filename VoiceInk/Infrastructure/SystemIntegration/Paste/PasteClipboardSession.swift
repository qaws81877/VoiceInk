import AppKit
import os

/// Drives one `PasteTransaction` against the real pasteboard: publishes the transcript,
/// records when the destination reads it, and restores the previous clipboard.
///
/// The transcript is published as a lazily provided `.string`, because the data provider
/// callback is the only public hook that observes a read. The pasteboard server caches
/// provided data, so only the first read of `.string` reaches the provider. For that reason
/// this type never reads the transcript back, and ownership is checked with `changeCount`.
///
/// Known macOS limit: because of that cache, a second read by the destination after the first
/// is not observable. The transaction settles 200 ms after the first observed read; an editor
/// that reads again later than that receives the restored clipboard.
///
/// Sulsul's own reads must not count as the destination's read. String reads go through
/// `ownClipboardString()` (answered from memory while the transcript is published); any other
/// synchronous access runs inside `performOwnClipboardAccess`, whose reads the observer ignores.
@MainActor
final class PasteClipboardSession {
    private typealias ItemSnapshot = [(NSPasteboard.PasteboardType, Data)]
    private typealias Snapshot = [ItemSnapshot]

    private static let logger = Logger(subsystem: AppIdentity.loggerSubsystem, category: "PasteClipboardSession")
    private static let pollInterval: TimeInterval = 0.05

    /// The session still waiting to restore, so a quick follow-up paste restores the
    /// clipboard from before the first paste instead of the first transcript.
    private static weak var pending: PasteClipboardSession?
    /// The most recent session that published a lazily provided transcript.
    private static weak var observing: PasteClipboardSession?
    /// Nesting depth of `performOwnClipboardAccess`; reads inside it are Sulsul's own.
    private(set) static var ownAccessDepth = 0
    /// Observers whose transcript stays on the clipboard after the transaction ends.
    private static var lingeringObservers: [TranscriptReadObserver] = []

    private let pasteboard: NSPasteboard
    private let snapshot: Snapshot?
    private let observer: TranscriptReadObserver?
    private let publishedChangeCount: Int
    private var transaction: PasteTransaction
    private var isSettled = false

    static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    /// Runs Sulsul's own synchronous pasteboard access; provider reads inside it are not counted.
    static func performOwnClipboardAccess<T>(_ body: () throws -> T) rethrows -> T {
        ownAccessDepth += 1
        defer { ownAccessDepth -= 1 }
        return try body()
    }

    /// The clipboard string for Sulsul's own use (context capture), without counting as,
    /// or pre-empting, the destination's read of a published transcript.
    static func ownClipboardString(on pasteboard: NSPasteboard = .general) -> String? {
        let session = observing
        let source = OwnClipboardReadSource.resolve(
            publishedTranscript: session?.observer?.text,
            publishedChangeCount: session?.publishedChangeCount,
            currentChangeCount: pasteboard.changeCount
        )
        switch source {
        case .transcript(let text):
            return text
        case .pasteboard:
            return performOwnClipboardAccess { pasteboard.string(forType: .string) }
        }
    }

    /// Puts `text` on the general pasteboard. Returns nil when the pasteboard rejected it.
    static func publish(
        _ text: String,
        restoreEnabled: Bool,
        submitKey: PasteTransaction.SubmitKey = .none
    ) -> PasteClipboardSession? {
        let pasteboard = NSPasteboard.general
        var transaction = PasteTransaction(
            publishedAt: now(),
            restoreEnabled: restoreEnabled,
            submitKey: submitKey
        )

        guard transaction.needsReadObservation else {
            // Restore off and nothing to send: the transcript simply stays, as before.
            guard ClipboardManager.setClipboard(text, transient: false, sessionID: nil) else { return nil }
            return PasteClipboardSession(
                pasteboard: pasteboard,
                snapshot: nil,
                observer: nil,
                changeCount: pasteboard.changeCount,
                transaction: transaction
            )
        }

        let snapshot: Snapshot? = restoreEnabled ? previousClipboard(on: pasteboard) : nil
        let observer = TranscriptReadObserver(text: text)
        let item = NSPasteboardItem()
        guard item.setDataProvider(observer, forTypes: [.string]) else { return nil }
        for (type, data) in ClipboardManager.pasteSessionMarkers(transient: restoreEnabled, sessionID: UUID().uuidString) {
            item.setData(data, forType: type)
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return nil }
        transaction.publishedAt = now()

        let session = PasteClipboardSession(
            pasteboard: pasteboard,
            snapshot: snapshot,
            observer: observer,
            changeCount: pasteboard.changeCount,
            transaction: transaction
        )
        observing = session
        if restoreEnabled {
            pending = session
        }
        return session
    }

    private init(
        pasteboard: NSPasteboard,
        snapshot: Snapshot?,
        observer: TranscriptReadObserver?,
        changeCount: Int,
        transaction: PasteTransaction
    ) {
        self.pasteboard = pasteboard
        self.snapshot = snapshot
        self.observer = observer
        self.publishedChangeCount = changeCount
        self.transaction = transaction
    }

    /// Records the paste key result. `attemptedAt` is taken before the key events go out,
    /// so a destination that reads while they are still being posted is counted.
    func pasteKeyFinished(posted: Bool, attemptedAt: TimeInterval) {
        transaction.pasteKey = posted ? .posted(at: attemptedAt) : .notPosted
    }

    /// Waits for the transaction to finish, applies the clipboard action and returns the
    /// submit key to send (always `.none` until a mode can choose one).
    @discardableResult
    func settle() async -> PasteTransaction.SubmitKey {
        while true {
            transaction.readTimes = observer?.readTimes ?? []
            transaction.ownershipTaken = pasteboard.changeCount != publishedChangeCount
            let now = Self.now()
            switch transaction.decision(at: now) {
            case .wait(let until):
                let interval = min(max(until - now, 0), Self.pollInterval)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            case .finish(let clipboard, let submitKey):
                apply(clipboard)
                return submitKey
            }
        }
    }

    private func apply(_ action: PasteTransaction.ClipboardAction) {
        guard !isSettled else { return }
        isSettled = true
        if Self.pending === self {
            Self.pending = nil
        }

        switch action {
        case .restorePrevious:
            pasteboard.clearContents()
            if let snapshot, !snapshot.isEmpty {
                pasteboard.writeObjects(Self.pasteboardItems(from: snapshot))
            }
        case .leaveTranscript:
            if let observer, !observer.isFinished {
                Self.keepAlive(observer)
            }
        case .leaveUserCopy:
            Self.logger.debug("Clipboard changed during paste; leaving it in place")
        }
    }

    private static func keepAlive(_ observer: TranscriptReadObserver) {
        lingeringObservers.append(observer)
        observer.onFinished = { [weak observer] in
            lingeringObservers.removeAll { $0 === observer }
        }
    }

    /// The clipboard to restore later. While an earlier paste still owns the pasteboard,
    /// that paste's saved clipboard is the real previous one; the earlier session sees the
    /// ownership change and leaves the pasteboard to this one.
    private static func previousClipboard(on pasteboard: NSPasteboard) -> Snapshot {
        if let pending, !pending.isSettled, let saved = pending.snapshot,
            pasteboard.changeCount == pending.publishedChangeCount
        {
            return saved
        }
        return performOwnClipboardAccess {
            (pasteboard.pasteboardItems ?? []).map { item in
                item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            }
        }
    }

    private static func pasteboardItems(from snapshot: Snapshot) -> [NSPasteboardItem] {
        snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            return item
        }
    }
}

/// Supplies the transcript when a consumer asks for it and records when that happened.
/// AppKit calls the provider on the main thread, synchronously inside the reading call when
/// the reader is Sulsul itself, so `PasteClipboardSession.ownAccessDepth` identifies own reads.
final class TranscriptReadObserver: NSObject, NSPasteboardItemDataProvider {
    let text: String
    private(set) var readTimes: [TimeInterval] = []
    private(set) var isFinished = false
    var onFinished: (() -> Void)?

    init(text: String) {
        self.text = text
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        let isOwnRead = MainActor.assumeIsolated { PasteClipboardSession.ownAccessDepth > 0 }
        if !isOwnRead {
            readTimes.append(ProcessInfo.processInfo.systemUptime)
        }
        item.setString(text, forType: type)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        isFinished = true
        onFinished?()
        onFinished = nil
    }
}
