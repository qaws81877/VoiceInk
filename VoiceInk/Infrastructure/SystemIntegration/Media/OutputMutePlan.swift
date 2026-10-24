import Foundation

/// What to do with the default output device's mute flag when a microphone recording starts.
enum OutputMuteStart: Equatable {
    /// Do not touch the device: the setting is off, no microphone is open,
    /// or the current mute flag could not be read.
    case leaveAlone
    /// The user had already muted the device. Sulsul never takes ownership of it,
    /// so it is neither written now nor written back later.
    case keepUserMute
    /// Set the mute flag. The volume is never changed.
    case requestMute
}

/// What to do with the mute flag when the recording ends (stop, cancel or failure).
enum OutputMuteEnd: Equatable {
    case leaveAlone
    /// Put back the previous flag (unmuted) on the device Sulsul muted.
    case restoreUnmuted
}

/// Pure decision for "mute output while the microphone is open".
/// `MediaController` is the CoreAudio adapter that reads the flag and applies the decision.
/// A failed mute request never cancels recording; callers ignore the outcome for that purpose.
enum OutputMutePlan {
    /// Existing UserDefaults key (inherited from upstream). Registered default is off.
    static let settingKey = "isSystemMuteEnabled"

    static func start(
        isSettingEnabled: Bool,
        isMicrophoneRecording: Bool,
        previousMuteFlag: Bool?
    ) -> OutputMuteStart {
        guard isSettingEnabled, isMicrophoneRecording else { return .leaveAlone }
        switch previousMuteFlag {
        case .none: return .leaveAlone
        case .some(true): return .keepUserMute
        case .some(false): return .requestMute
        }
    }

    static func end(after start: OutputMuteStart, muteRequestSucceeded: Bool) -> OutputMuteEnd {
        start == .requestMute && muteRequestSucceeded ? .restoreUnmuted : .leaveAlone
    }
}
