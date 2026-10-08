import Foundation

/// Identifiers that must not collide with an installed copy of upstream VoiceInk.
enum AppIdentity {
    static let bundleIdentifier = "com.qaws81877.sulsul"
    static let supportDirectoryName = "com.qaws81877.sulsul"
    static let keychainService = "com.qaws81877.sulsul"
    static let keychainServiceLocalBuild = "com.qaws81877.sulsul.Local"
    static let loggerSubsystem = "com.qaws81877.sulsul"
    static let displayName = "술술"
    static let productName = "Sulsul"
    static let sparklePublicKeyPlaceholder = "REPLACE_WITH_SPARKLE_PUBLIC_KEY"
    static let sparkleFeedURL = "https://github.com/qaws81877/VoiceInk/releases/latest/download/appcast.xml"

    static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
    }
}
