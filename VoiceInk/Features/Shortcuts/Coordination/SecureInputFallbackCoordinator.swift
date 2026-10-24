import AppKit
import Carbon.HIToolbox
import Foundation
import os

/// Inputs the plan needs from the shortcut managers, gathered only while secure input is held.
struct SecureInputShortcutInputs {
    var shortcuts: [ShortcutAction: Shortcut]
    var cancelShortcut: (action: ShortcutAction, shortcut: Shortcut)?
    var isRecording: Bool
}

/// Polls Secure Event Input on the main run loop and applies `SecureInputPlan`: Carbon hot keys
/// after the hold passes the activation delay, removed on the first poll after it ends.
/// There is no public notification for secure input changes, so polling bounds both edges.
@MainActor
final class SecureInputFallbackCoordinator {
    private static let pollInterval: TimeInterval = 0.25

    private let inputs: @MainActor () -> SecureInputShortcutInputs
    private let onNoticeChange: @MainActor (SecureInputMenuNotice?) -> Void
    private let logger = Logger(subsystem: AppIdentity.loggerSubsystem, category: "SecureInputFallback")
    private var registrar: SecureInputHotKeyRegistrar!
    private var timer: Timer?
    private var heldSince: TimeInterval?
    private var notice: SecureInputMenuNotice?
    private let isEnabled = SecureInputFallbackCoordinator.isEnabled(environment: ProcessInfo.processInfo.environment)

    /// False in the XCTest host (same check as `KeychainService`), so tests never register Carbon hot keys.
    nonisolated static func isEnabled(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
    }

    var isPolling: Bool {
        timer != nil
    }

    init(
        inputs: @escaping @MainActor () -> SecureInputShortcutInputs,
        onPress: @escaping @MainActor (ShortcutAction, _ isDown: Bool) -> Void,
        onNoticeChange: @escaping @MainActor (SecureInputMenuNotice?) -> Void
    ) {
        self.inputs = inputs
        self.onNoticeChange = onNoticeChange
        registrar = SecureInputHotKeyRegistrar { [weak self] action, isDown in
            guard let self else { return }
            // A hot key that fires after secure input ended would double the tap's dispatch.
            guard IsSecureEventInputEnabled() else {
                self.evaluate()
                return
            }
            onPress(action, isDown)
        }
    }

    func start() {
        guard isEnabled, timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        heldSince = nil
        registrar.unregisterAll()
        setNotice(nil)
    }

    /// Re-applies the plan now, e.g. after shortcuts or the recording state changed.
    func evaluate() {
        guard isEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard IsSecureEventInputEnabled() else {
            heldSince = nil
            if !registrar.isEmpty || notice != nil {
                registrar.unregisterAll()
                setNotice(nil)
                logger.info("Secure input ended; fallback removed")
            }
            return
        }

        let start = heldSince ?? now
        heldSince = start
        let holdDuration = now - start
        guard holdDuration >= SecureInputPlan.activationDelay else { return }

        let current = inputs()
        let plan = SecureInputPlan(
            holdDuration: holdDuration,
            holder: Self.currentHolder(),
            shortcuts: current.shortcuts,
            cancelShortcut: current.cancelShortcut,
            isRecording: current.isRecording
        )
        let wasEmpty = registrar.isEmpty
        registrar.apply(plan.registrations)
        if wasEmpty && !registrar.isEmpty {
            logger.info("Secure input held; fallback active for \(plan.registrations.count) shortcuts")
        }
        setNotice(plan.menuNotice)
    }

    private func setNotice(_ newNotice: SecureInputMenuNotice?) {
        guard newNotice != notice else { return }
        notice = newNotice
        onNoticeChange(newNotice)
    }

    private static func currentHolder() -> SecureInputHolder {
        let properties = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        return SecureInputHolder.resolve(sessionProperties: properties) { pid in
            NSRunningApplication(processIdentifier: pid)?.localizedName
        }
    }
}
