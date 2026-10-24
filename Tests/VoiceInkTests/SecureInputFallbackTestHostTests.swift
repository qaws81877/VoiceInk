import XCTest

@testable import VoiceInk

@MainActor
final class SecureInputFallbackTestHostTests: XCTestCase {
    func testFallbackIsOffWhenHostedByXCTest() {
        XCTAssertFalse(
            SecureInputFallbackCoordinator.isEnabled(environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"])
        )
        XCTAssertTrue(SecureInputFallbackCoordinator.isEnabled(environment: [:]))
    }

    func testStartDoesNotPollInTheTestHost() {
        let coordinator = SecureInputFallbackCoordinator(
            inputs: { SecureInputShortcutInputs(shortcuts: [:], isRecording: false) },
            onPress: { _, _ in XCTFail("No hot key may fire in the test host") },
            onNoticeChange: { _ in }
        )
        coordinator.start()
        XCTAssertFalse(coordinator.isPolling)
        coordinator.stop()
    }
}
