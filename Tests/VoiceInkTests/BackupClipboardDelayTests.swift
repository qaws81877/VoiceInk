import XCTest

@testable import VoiceInk

/// The importer no longer applies `clipboardRestoreDelay` (it writes straight to `UserDefaults.standard`,
/// which the test host shares with the app, so that path is not exercised here). The field must still
/// round-trip so backups stay readable by older builds.
final class BackupClipboardDelayTests: XCTestCase {
    func testClipboardRestoreDelaySurvivesABackupRoundTrip() throws {
        let json = Data(#"{"restoreClipboardAfterPaste":true,"clipboardRestoreDelay":1.5}"#.utf8)
        let decoded = try JSONDecoder().decode(GeneralBackup.self, from: json)
        XCTAssertEqual(decoded.clipboardRestoreDelay, 1.5)

        let reencoded = try JSONDecoder().decode(GeneralBackup.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(reencoded.clipboardRestoreDelay, 1.5)
        XCTAssertEqual(reencoded.restoreClipboardAfterPaste, true)
    }
}
