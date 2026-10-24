import Foundation

/// Key a paste mode sends once the destination has read the transcript and the read has settled.
/// Raw values are persisted inside `ModeConfig`; do not rename them.
enum ModeSubmitKey: String, Codable, CaseIterable {
    case off
    case enter
    case commandEnter

    var displayName: String {
        switch self {
        case .off: return String(localized: "Off")
        case .enter: return String(localized: "Return (⏎)")
        case .commandEnter: return String(localized: "Command + Return (⌘⏎)")
        }
    }

    /// The key that actually goes out for a mode with this stored choice. Only paste output sends
    /// it; respond and custom-command outputs keep the stored choice without sending it, so
    /// switching the mode back to paste brings the choice back.
    func effective(for outputMode: ModeOutputMode) -> ModeSubmitKey {
        outputMode == .paste ? self : .off
    }
}
