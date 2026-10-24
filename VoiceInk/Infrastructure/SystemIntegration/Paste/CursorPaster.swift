import AppKit
import Carbon
import Foundation
import os

class CursorPaster {
    private static let logger = Logger(subsystem: AppIdentity.loggerSubsystem, category: "CursorPaster")

    enum PasteResult: Equatable {
        case commandPosted
        case commandNotPosted

        var didPostPasteCommand: Bool {
            self == .commandPosted
        }
    }

    struct PasteOutcome {
        let result: PasteResult
        let autoLearnGeneration: UInt64?
        /// Finishes when the paste transaction settles, with the submit key it decided to send
        /// (`.none` when the paste was not read, the key never went out, or the user copied).
        let settledSubmitKey: Task<PasteTransaction.SubmitKey, Never>
    }

    private static let prePasteDelay: TimeInterval = 0.10
    private static let pasteShortcutEventDelay: TimeInterval = 0.01

    static func pasteAtCursor(_ text: String) {
        Task {
            let pasteTask = await MainActor.run {
                startPasteAtCursor(text)
            }
            _ = await pasteTask.value
        }
    }

    @MainActor
    @discardableResult
    static func startPasteAtCursor(
        _ text: String,
        submitKey: PasteTransaction.SubmitKey = .none
    ) -> Task<PasteOutcome, Never> {
        Task { @MainActor in
            await performPasteSession(text, submitKey: submitKey)
        }
    }

    @MainActor
    private static func performPasteSession(_ text: String, submitKey: PasteTransaction.SubmitKey) async -> PasteOutcome {
        let shouldRestoreClipboard = UserDefaults.standard.bool(forKey: "restoreClipboardAfterPaste")
        guard
            let clipboard = PasteClipboardSession.publish(
                text, restoreEnabled: shouldRestoreClipboard, submitKey: submitKey)
        else {
            logger.error("Failed to prepare clipboard for paste")
            return PasteOutcome(
                result: .commandNotPosted, autoLearnGeneration: nil, settledSubmitKey: Task { .none })
        }

        await wait(prePasteDelay)

        let isAutoLearnEnabled = AutoLearnSettings.isEnabled
        let targetProcessID = isAutoLearnEnabled ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
        let pasteKeyAttemptedAt = PasteClipboardSession.now()
        let pasteResult = await postPasteCommand()
        clipboard.pasteKeyFinished(posted: pasteResult.didPostPasteCommand, attemptedAt: pasteKeyAttemptedAt)
        // Restore and the mode's submit key both wait for the destination's read to settle.
        let settledSubmitKey = Task { @MainActor in
            await clipboard.settle()
        }

        let autoLearnGeneration: UInt64?
        if isAutoLearnEnabled {
            autoLearnGeneration = await AutoLearnService.shared.pasteDidFinish(
                text: text,
                processID: targetProcessID,
                commandPosted: pasteResult.didPostPasteCommand
            )
        } else {
            autoLearnGeneration = nil
        }

        return PasteOutcome(
            result: pasteResult, autoLearnGeneration: autoLearnGeneration, settledSubmitKey: settledSubmitKey)
    }

    @MainActor
    private static func postPasteCommand() async -> PasteResult {
        if PasteMethod.current() == .appleScript {
            return pasteUsingAppleScript() ? .commandPosted : .commandNotPosted
        } else {
            return await pasteFromClipboard()
        }
    }

    // MARK: - AppleScript paste

    // "X – QWERTY ⌘" layouts remap to QWERTY when Command is held, so keystroke "v" resolves
    // the wrong key code. key code 9 (physical V) bypasses layout translation for those layouts.
    private static func makeScript(_ source: String) -> NSAppleScript? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }

    private static let pasteScriptKeystroke = makeScript(
        "tell application \"System Events\" to keystroke \"v\" using command down")
    private static let pasteScriptKeyCode = makeScript(
        "tell application \"System Events\" to key code 9 using command down")

    @MainActor
    private static var layoutSwitchesToQWERTYOnCommand: Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let nameRef = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return false }
        return (Unmanaged<CFString>.fromOpaque(nameRef).takeUnretainedValue() as String).hasSuffix("⌘")
    }

    @MainActor
    private static func pasteUsingAppleScript() -> Bool {
        guard let script = layoutSwitchesToQWERTYOnCommand ? pasteScriptKeyCode : pasteScriptKeystroke else {
            logger.error("AppleScript paste script is unavailable")
            return false
        }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            logger.error("AppleScript paste failed: \(String(describing: error), privacy: .public)")
        }
        return error == nil
    }

    // MARK: - CGEvent paste

    // Posts Cmd+V via CGEvent without modifying the active input source.
    @MainActor
    private static func pasteFromClipboard() async -> PasteResult {
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission is required to paste with simulated key events")
            return .commandNotPosted
        }

        let source = CGEventSource(stateID: .privateState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        else {
            logger.error("Failed to create Cmd+V keyboard events")
            return .commandNotPosted
        }

        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        cmdDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vDown.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        vUp.post(tap: .cghidEventTap)
        await wait(pasteShortcutEventDelay)
        cmdUp.post(tap: .cghidEventTap)

        return .commandPosted
    }

    private static func wait(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    // MARK: - Send Key

    static func performSendKey(_ key: FinishAndSendKey) {
        guard key.isEnabled else { return }
        guard AXIsProcessTrusted() else { return }

        let source = CGEventSource(stateID: .privateState)
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)

        switch key {
        case .none: return
        case .enter: break
        case .shiftEnter:
            enterDown?.flags = .maskShift
            enterUp?.flags = .maskShift
        case .commandEnter:
            enterDown?.flags = .maskCommand
            enterUp?.flags = .maskCommand
        }

        enterDown?.post(tap: .cghidEventTap)
        enterUp?.post(tap: .cghidEventTap)
    }
}
