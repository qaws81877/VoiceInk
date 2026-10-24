import XCTest

@testable import VoiceInk

final class KeychainTestHostTests: XCTestCase {
    // KeychainService skips the login keychain when this variable is present; if the test host stops
    // receiving it, every `make test` run raises a keychain prompt again.
    func testTestHostReceivesXCTestConfigurationPath() {
        XCTAssertNotNil(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"])
    }

    func testKeychainIsNotTouchedInTheTestHost() {
        let key = "KeychainTestHostTests.probe"
        XCTAssertFalse(KeychainService.shared.save("value", forKey: key, syncable: false))
        XCTAssertFalse(KeychainService.shared.exists(forKey: key, syncable: false))
        XCTAssertNil(KeychainService.shared.getString(forKey: key, syncable: false))
    }
}
