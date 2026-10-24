import Foundation

/// Which submit key a dictation paste sends, so a paste never sends two.
///
/// A mode's submit key (already gated to paste output by `ModeRuntimeResolver`) goes out once,
/// at the paste transaction's settled read, and replaces the global Auto Send for that paste.
/// With the mode key off, the global Auto Send behaves as before: it is sent shortly after the
/// paste key when the user finished the recording with Return.
struct PasteSubmitPlan: Equatable {
    /// Sent by the paste transaction when the destination's read has settled.
    var settledReadKey: PasteTransaction.SubmitKey
    /// Global Auto Send key, sent shortly after the paste key.
    var autoSendKey: FinishAndSendKey

    static func resolve(
        modeSubmitKey: ModeSubmitKey,
        sendAfterPaste: Bool,
        autoSendKey: FinishAndSendKey
    ) -> PasteSubmitPlan {
        switch modeSubmitKey {
        case .enter:
            return PasteSubmitPlan(settledReadKey: .enter, autoSendKey: .none)
        case .commandEnter:
            return PasteSubmitPlan(settledReadKey: .commandEnter, autoSendKey: .none)
        case .off:
            return PasteSubmitPlan(settledReadKey: .none, autoSendKey: sendAfterPaste ? autoSendKey : .none)
        }
    }

    /// The Return key event that carries a settled-read submit key.
    static func sendKey(for submitKey: PasteTransaction.SubmitKey) -> FinishAndSendKey {
        switch submitKey {
        case .none: return .none
        case .enter: return .enter
        case .commandEnter: return .commandEnter
        }
    }
}
