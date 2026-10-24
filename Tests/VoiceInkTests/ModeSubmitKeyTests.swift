import XCTest

@testable import VoiceInk

final class ModeSubmitKeyTests: XCTestCase {
    private func decodeMode(extraFields: String = "") throws -> ModeConfig {
        let json = """
            {
              "id": "20000000-0000-0000-0000-000000000002",
              "name": "Chat",
              "isAIEnhancementEnabled": false,
              "useClipboardContext": false,
              "useSelectedTextContext": true,
              "useScreenCapture": false,
              "outputMode": "paste"\(extraFields)
            }
            """
        return try JSONDecoder().decode(ModeConfig.self, from: Data(json.utf8))
    }

    func testModeSavedBeforeTheSubmitKeyExistedDecodesAsOff() throws {
        XCTAssertEqual(try decodeMode().submitKey, .off)
    }

    func testUnknownStoredSubmitKeyDecodesAsOffInsteadOfDroppingTheMode() throws {
        XCTAssertEqual(try decodeMode(extraFields: #", "submitKey": "shiftEnter""#).submitKey, .off)
    }

    func testChosenSubmitKeySurvivesSaveAndLoad() throws {
        var mode = try decodeMode()
        mode.submitKey = .commandEnter
        let data = try JSONEncoder().encode(mode)
        XCTAssertEqual(try JSONDecoder().decode(ModeConfig.self, from: data).submitKey, .commandEnter)
    }

    func testOnlyPasteOutputSendsTheStoredSubmitKey() {
        XCTAssertEqual(ModeSubmitKey.enter.effective(for: .paste), .enter)
        XCTAssertEqual(ModeSubmitKey.commandEnter.effective(for: .paste), .commandEnter)
        XCTAssertEqual(ModeSubmitKey.enter.effective(for: .respond), .off)
        XCTAssertEqual(ModeSubmitKey.commandEnter.effective(for: .customCommand), .off)
    }

    @MainActor
    func testSwitchingAwayFromPasteKeepsTheChoiceAndSwitchingBackSendsIt() throws {
        var mode = try decodeMode()
        mode.submitKey = .enter
        mode.outputMode = .respond
        let reloaded = try JSONDecoder().decode(ModeConfig.self, from: JSONEncoder().encode(mode))
        XCTAssertEqual(reloaded.submitKey, .enter)
        XCTAssertEqual(ModeRuntimeResolver.outputConfiguration(mode: reloaded).submitKey, .off)

        var backToPaste = reloaded
        backToPaste.outputMode = .paste
        XCTAssertEqual(ModeRuntimeResolver.outputConfiguration(mode: backToPaste).submitKey, .enter)
    }

    func testNewModeDefaultsToOff() {
        XCTAssertEqual(ModeConfig(name: "New", isAIEnhancementEnabled: false).submitKey, .off)
    }
}
