import Carbon.HIToolbox
import Foundation
import os

/// Registers Carbon hot keys as a side path for key shortcuts while Secure Event Input hides
/// key events from the event tap. Never logs key codes or modifier flags.
@MainActor
final class SecureInputHotKeyRegistrar {
    typealias Handler = @MainActor (ShortcutAction, _ isDown: Bool) -> Void

    private static let signature: OSType = 0x5353_4642  // "SSFB"

    private let handler: Handler
    private let logger = Logger(subsystem: AppIdentity.loggerSubsystem, category: "SecureInputHotKeyRegistrar")
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var actionsByID: [UInt32: ShortcutAction] = [:]
    private var pressedIDs = Set<UInt32>()
    private var nextID: UInt32 = 1
    private(set) var registeredShortcuts: [ShortcutAction: Shortcut] = [:]

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isEmpty: Bool {
        hotKeyRefs.isEmpty
    }

    func apply(_ shortcuts: [ShortcutAction: Shortcut]) {
        guard shortcuts != registeredShortcuts else { return }
        unregisterAll()
        guard !shortcuts.isEmpty, installEventHandlerIfNeeded() else { return }

        for (action, shortcut) in shortcuts {
            guard let modifiers = SecureInputPlan.carbonModifiers(for: shortcut) else { continue }
            let id = nextID
            nextID &+= 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(shortcut.keyCode),
                modifiers,
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            guard status == noErr, let ref else {
                logger.error(
                    "Secure input fallback could not register \(action.storageName, privacy: .public): \(status)"
                )
                continue
            }
            hotKeyRefs[id] = ref
            actionsByID[id] = action
        }
        registeredShortcuts = shortcuts
    }

    func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs = [:]
        actionsByID = [:]
        pressedIDs = []
        registeredShortcuts = [:]
    }

    private func installEventHandlerIfNeeded() -> Bool {
        guard eventHandlerRef == nil else { return true }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let registrar = Unmanaged<SecureInputHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
            return MainActor.assumeIsolated {
                registrar.handle(event)
            }
        }
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard status == noErr else {
            logger.error("Secure input fallback could not install its hot key handler: \(status)")
            eventHandlerRef = nil
            return false
        }
        return true
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == Self.signature,
            let action = actionsByID[hotKeyID.id]
        else {
            return OSStatus(eventNotHandledErr)
        }

        let isDown = GetEventKind(event) == UInt32(kEventHotKeyPressed)
        if isDown {
            pressedIDs.insert(hotKeyID.id)
        } else if pressedIDs.remove(hotKeyID.id) == nil {
            // A release without a press seen here belongs to a press from before registration.
            return noErr
        }
        handler(action, isDown)
        return noErr
    }

    deinit {
        MainActor.assumeIsolated {
            unregisterAll()
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
            }
        }
    }
}
