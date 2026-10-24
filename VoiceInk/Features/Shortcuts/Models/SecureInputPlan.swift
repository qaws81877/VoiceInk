import AppKit
import Carbon.HIToolbox
import Foundation

/// The process that currently holds Secure Event Input.
enum SecureInputHolder: Equatable {
    case app(name: String)
    case unknown

    // CGSession has no public constant for this WindowServer property.
    static let sessionPIDKey = "kCGSSessionSecureInputPID"

    static func resolve(
        sessionProperties: [String: Any],
        appName: (pid_t) -> String?
    ) -> SecureInputHolder {
        guard let pid = (sessionProperties[sessionPIDKey] as? NSNumber)?.int32Value, pid > 0,
            let name = appName(pid)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else {
            return .unknown
        }

        return .app(name: name)
    }
}

/// Menu bar text shown while the fallback is active. It names the holder only, never keys.
enum SecureInputMenuNotice: Equatable {
    case heldBy(appName: String)
    case heldByUnknownApp

    var text: String {
        switch self {
        case .heldBy(let appName):
            return String(format: String(localized: "Keyboard held by %@"), appName)
        case .heldByUnknownApp:
            return String(localized: "Keyboard held by an unknown app")
        }
    }
}

/// Decides which shortcuts get a side registration while another process holds Secure Event Input.
///
/// Secure input hides key events from event taps but not modifier changes, so only shortcuts
/// with a non-modifier key need the fallback. Carbon hot keys have no fn modifier, so a key
/// shortcut that includes fn cannot be covered.
struct SecureInputPlan: Equatable {
    static let activationDelay: TimeInterval = 3

    let registrations: [ShortcutAction: Shortcut]
    let menuNotice: SecureInputMenuNotice?

    /// - Parameters:
    ///   - holdDuration: how long secure input has been on, or nil when it is off.
    ///   - shortcuts: the active global shortcuts (main, mode and utility actions).
    ///   - cancelShortcut: the cancel action and shortcut in use while recording.
    init(
        holdDuration: TimeInterval?,
        holder: SecureInputHolder,
        shortcuts: [ShortcutAction: Shortcut],
        cancelShortcut: (action: ShortcutAction, shortcut: Shortcut)?,
        isRecording: Bool
    ) {
        guard let holdDuration, holdDuration >= Self.activationDelay else {
            registrations = [:]
            menuNotice = nil
            return
        }

        var registrations = shortcuts.filter { Self.canRegister($0.value) }
        if isRecording, let cancelShortcut, Self.canRegister(cancelShortcut.shortcut) {
            registrations[cancelShortcut.action] = cancelShortcut.shortcut
        }

        self.registrations = registrations
        switch holder {
        case .app(let name):
            menuNotice = .heldBy(appName: name)
        case .unknown:
            menuNotice = .heldByUnknownApp
        }
    }

    /// True for a shortcut that secure input blocks and the fallback cannot cover.
    static func needsUncoveredNote(_ shortcut: Shortcut?) -> Bool {
        guard let shortcut, shortcut.kind == .key else { return false }
        return carbonModifiers(for: shortcut) == nil
    }

    /// Carbon hot key modifiers for a key shortcut, or nil when it cannot be expressed (fn, non-key).
    static func carbonModifiers(for shortcut: Shortcut) -> UInt32? {
        guard shortcut.kind == .key else { return nil }
        let flags = shortcut.modifierFlags
        guard !flags.contains(.function) else { return nil }

        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        return UInt32(modifiers)
    }

    private static func canRegister(_ shortcut: Shortcut) -> Bool {
        carbonModifiers(for: shortcut) != nil
    }
}
