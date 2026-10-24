import XCTest

@testable import VoiceInk

final class OutputMutePlanTests: XCTestCase {

    // MARK: - Start of a recording

    func testSettingOffNeverRequestsMute() {
        for previous in [false, true, nil] as [Bool?] {
            XCTAssertEqual(
                OutputMutePlan.start(
                    isSettingEnabled: false,
                    isMicrophoneRecording: true,
                    previousMuteFlag: previous
                ),
                .leaveAlone
            )
        }
    }

    func testNoMicrophoneRecordingNeverRequestsMute() {
        // File transcription has no open microphone, so it never mutes.
        XCTAssertEqual(
            OutputMutePlan.start(
                isSettingEnabled: true,
                isMicrophoneRecording: false,
                previousMuteFlag: false
            ),
            .leaveAlone
        )
    }

    func testUnmutedDeviceIsMutedWhileMicrophoneIsOpen() {
        XCTAssertEqual(
            OutputMutePlan.start(
                isSettingEnabled: true,
                isMicrophoneRecording: true,
                previousMuteFlag: false
            ),
            .requestMute
        )
    }

    func testAlreadyMutedDeviceIsKeptAsTheUserLeftIt() {
        XCTAssertEqual(
            OutputMutePlan.start(
                isSettingEnabled: true,
                isMicrophoneRecording: true,
                previousMuteFlag: true
            ),
            .keepUserMute
        )
    }

    func testUnreadableMuteFlagIsNeverToggled() {
        XCTAssertEqual(
            OutputMutePlan.start(
                isSettingEnabled: true,
                isMicrophoneRecording: true,
                previousMuteFlag: nil
            ),
            .leaveAlone
        )
    }

    // MARK: - End of a recording (stop, cancel or failure)

    func testSuccessfulMuteIsRestoredToUnmuted() {
        XCTAssertEqual(
            OutputMutePlan.end(after: .requestMute, muteRequestSucceeded: true),
            .restoreUnmuted
        )
    }

    func testFailedMuteRequestLeavesDeviceAlone() {
        XCTAssertEqual(
            OutputMutePlan.end(after: .requestMute, muteRequestSucceeded: false),
            .leaveAlone
        )
    }

    func testAlreadyMutedDeviceStaysMutedAfterRecording() {
        XCTAssertEqual(
            OutputMutePlan.end(after: .keepUserMute, muteRequestSucceeded: true),
            .leaveAlone
        )
    }

    func testNothingIsRestoredWhenNothingWasRequested() {
        XCTAssertEqual(
            OutputMutePlan.end(after: .leaveAlone, muteRequestSucceeded: false),
            .leaveAlone
        )
    }

    // MARK: - Setting default

    func testMuteSettingIsRegisteredOffByDefault() {
        AppDefaults.registerDefaults()
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        XCTAssertEqual(registered[OutputMutePlan.settingKey] as? Bool, false)
    }
}
