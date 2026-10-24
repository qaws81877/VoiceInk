import AppKit
import Carbon.HIToolbox
import XCTest

@testable import VoiceInk

final class SecureInputPlanTests: XCTestCase {
    private let letterShortcut = Shortcut.key(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.command, .shift])
    private let fnLetterShortcut = Shortcut.key(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.function, .command])
    private let modifierOnlyShortcut = Shortcut.rightCommand
    private let mouseShortcut = Shortcut.mouseButton(buttonNumber: 4)
    private let escape = Shortcut.key(keyCode: UInt16(kVK_Escape), modifierFlags: [])
    private let modeId = UUID()

    private func plan(
        heldFor holdDuration: TimeInterval?,
        holder: SecureInputHolder = .app(name: "Terminal"),
        shortcuts: [ShortcutAction: Shortcut]? = nil,
        cancel: (action: ShortcutAction, shortcut: Shortcut)? = nil,
        isRecording: Bool = false
    ) -> SecureInputPlan {
        SecureInputPlan(
            holdDuration: holdDuration,
            holder: holder,
            shortcuts: shortcuts ?? [.primaryRecording: letterShortcut],
            cancelShortcut: cancel ?? (.recorderPanelEscape, escape),
            isRecording: isRecording
        )
    }

    // MARK: - Hold threshold

    func testNothingIsRegisteredOrShownWhileSecureInputIsOff() {
        let plan = plan(heldFor: nil, isRecording: true)

        XCTAssertEqual(plan.registrations, [:])
        XCTAssertNil(plan.menuNotice)
    }

    func testNothingIsRegisteredOrShownBeforeThreeSeconds() {
        let plan = plan(heldFor: 2.9, isRecording: true)

        XCTAssertEqual(plan.registrations, [:])
        XCTAssertNil(plan.menuNotice)
    }

    func testLetterShortcutIsRegisteredOnceHeldForThreeSeconds() {
        let plan = plan(heldFor: 3.0)

        XCTAssertEqual(plan.registrations, [.primaryRecording: letterShortcut])
        XCTAssertEqual(plan.menuNotice, .heldBy(appName: "Terminal"))
    }

    // MARK: - Per-shortcut kind

    func testEveryLetterShortcutIsRegisteredAcrossMainModeAndUtilityActions() {
        let paste = Shortcut.key(keyCode: UInt16(kVK_ANSI_V), modifierFlags: [.option, .command])
        let mode = Shortcut.key(keyCode: UInt16(kVK_ANSI_1), modifierFlags: [.control])
        let plan = plan(
            heldFor: 10,
            shortcuts: [
                .primaryRecording: letterShortcut,
                .pasteLastTranscription: paste,
                .mode(modeId): mode,
            ]
        )

        XCTAssertEqual(
            plan.registrations,
            [.primaryRecording: letterShortcut, .pasteLastTranscription: paste, .mode(modeId): mode]
        )
    }

    func testModifierOnlyAndMouseShortcutsStayOnTheirCurrentListener() {
        let plan = plan(
            heldFor: 10,
            shortcuts: [
                .primaryRecording: modifierOnlyShortcut,
                .secondaryRecording: mouseShortcut,
                .openQuickHistory: letterShortcut,
            ]
        )

        XCTAssertEqual(plan.registrations, [.openQuickHistory: letterShortcut])
    }

    func testFnShortcutIsNotRegistered() {
        let plan = plan(heldFor: 10, shortcuts: [.primaryRecording: fnLetterShortcut])

        XCTAssertEqual(plan.registrations, [:])
        XCTAssertEqual(plan.menuNotice, .heldBy(appName: "Terminal"))
    }

    func testFunctionKeyWithoutFnModifierIsRegistered() {
        let f5 = Shortcut.key(keyCode: UInt16(kVK_F5), modifierFlags: [.function])
        let plan = plan(heldFor: 10, shortcuts: [.primaryRecording: f5])

        XCTAssertEqual(plan.registrations, [.primaryRecording: f5])
    }

    // MARK: - Cancel during recording

    func testCancelIsRegisteredOnlyWhileRecording() {
        XCTAssertNil(plan(heldFor: 10, isRecording: false).registrations[.recorderPanelEscape])
        XCTAssertEqual(plan(heldFor: 10, isRecording: true).registrations[.recorderPanelEscape], escape)
    }

    func testCustomCancelShortcutIsRegisteredWhileRecording() {
        let custom = Shortcut.key(keyCode: UInt16(kVK_ANSI_X), modifierFlags: [.control, .option])
        let plan = plan(heldFor: 10, cancel: (.cancelRecorder, custom), isRecording: true)

        XCTAssertEqual(plan.registrations[.cancelRecorder], custom)
        XCTAssertNil(plan.registrations[.recorderPanelEscape])
    }

    func testFnCancelShortcutIsNotRegistered() {
        let plan = plan(heldFor: 10, cancel: (.cancelRecorder, fnLetterShortcut), isRecording: true)

        XCTAssertNil(plan.registrations[.cancelRecorder])
    }

    // MARK: - Holder

    func testUnknownHolderStillGetsTheFallback() {
        let plan = plan(heldFor: 10, holder: .unknown)

        XCTAssertEqual(plan.registrations, [.primaryRecording: letterShortcut])
        XCTAssertEqual(plan.menuNotice, .heldByUnknownApp)
    }

    func testHolderResolvesNameFromSessionPID() {
        let holder = SecureInputHolder.resolve(
            sessionProperties: ["kCGSSessionSecureInputPID": NSNumber(value: 42)],
            appName: { $0 == 42 ? "Terminal" : nil }
        )

        XCTAssertEqual(holder, .app(name: "Terminal"))
    }

    func testHolderIsUnknownWithoutPIDOrName() {
        XCTAssertEqual(SecureInputHolder.resolve(sessionProperties: [:], appName: { _ in "X" }), .unknown)
        XCTAssertEqual(
            SecureInputHolder.resolve(
                sessionProperties: ["kCGSSessionSecureInputPID": NSNumber(value: 7)],
                appName: { _ in nil }
            ),
            .unknown
        )
        XCTAssertEqual(
            SecureInputHolder.resolve(
                sessionProperties: ["kCGSSessionSecureInputPID": NSNumber(value: 7)],
                appName: { _ in "  " }
            ),
            .unknown
        )
    }

    func testMenuTextNamesTheHolderAndNeverTheKeys() {
        let text = SecureInputMenuNotice.heldBy(appName: "Terminal").text

        XCTAssertTrue(text.contains("Terminal"))
        XCTAssertFalse(text.contains(letterShortcut.displayString))
        XCTAssertFalse(text.contains("⌘"))
    }

    // MARK: - Settings note

    func testSettingsNoteAppearsOnlyForFnShortcuts() {
        XCTAssertTrue(SecureInputPlan.needsUncoveredNote(fnLetterShortcut))
        XCTAssertFalse(SecureInputPlan.needsUncoveredNote(letterShortcut))
        XCTAssertFalse(SecureInputPlan.needsUncoveredNote(modifierOnlyShortcut))
        XCTAssertFalse(SecureInputPlan.needsUncoveredNote(mouseShortcut))
        XCTAssertFalse(SecureInputPlan.needsUncoveredNote(nil))
        XCTAssertFalse(
            SecureInputPlan.needsUncoveredNote(.key(keyCode: UInt16(kVK_F5), modifierFlags: [.function]))
        )
    }

    // MARK: - Carbon modifiers

    func testCarbonModifiersMapEachShortcutModifier() {
        let shortcut = Shortcut.key(
            keyCode: UInt16(kVK_ANSI_D),
            modifierFlags: [.command, .shift, .option, .control]
        )

        XCTAssertEqual(
            SecureInputPlan.carbonModifiers(for: shortcut),
            UInt32(cmdKey | shiftKey | optionKey | controlKey)
        )
        XCTAssertEqual(SecureInputPlan.carbonModifiers(for: escape), 0)
        XCTAssertNil(SecureInputPlan.carbonModifiers(for: fnLetterShortcut))
        XCTAssertNil(SecureInputPlan.carbonModifiers(for: modifierOnlyShortcut))
    }
}
