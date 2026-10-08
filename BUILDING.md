# Building 술술 (Sulsul)

술술 is a modified fork of [VoiceInk](https://github.com/Beingpax/VoiceInk) by Prakash Joshi (Pax). See [NOTICE](NOTICE) and [README.md](README.md).

## Requirements

- macOS 15.0 or later
- Xcode 27 (this project was last upgraded by Xcode 26.5-era tools; `LastUpgradeCheck` is 2650). Command Line Tools selected with `xcode-select`.
- Git
- Apple silicon. The current local build path is an M5 Pro.

The Xcode target and scheme stay named `VoiceInk` so the Swift module name does not change. The built app is `Sulsul.app` (Release) or `Sulsul Dev.app` (Debug).

## Team ID

The only Team ID setting is `DEVELOPMENT_TEAM` in [Signing.xcconfig](Signing.xcconfig) at the repository root.

1. Open [Apple Developer membership](https://developer.apple.com/account) and copy the 10-character Team ID.
2. Set it with no quotes:

```
DEVELOPMENT_TEAM = ABCDE12345
```

`make local` passes an empty team and `LocalBuild.xcconfig`, so a day-to-day local build does not need this. `make release`, `make release-setup`, and Xcode archives read `Signing.xcconfig`. Do not put another person's Team ID in the project.

## Local build

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
cd /path/to/VoiceInk
make local
open ~/Downloads/Sulsul.app
```

`make local` prepares `whisper.xcframework` under `~/VoiceInk-Dependencies` (a build-tool checkout, not the app's data folder), builds the `VoiceInk` scheme in the Release configuration into `.local-build`, and copies `Sulsul.app` to `~/Downloads`.

It uses `LocalBuild.xcconfig`, `VoiceInk/VoiceInk.local.entitlements`, and the `LOCAL_BUILD` Swift flag. Without an override, it uses the only available Apple Development identity, or ad-hoc signing when none or several are found.

Choose an identity explicitly:

```bash
make local LOCAL_CODESIGN_IDENTITY="<SHA or name>"
```

Force ad-hoc signing:

```bash
make local LOCAL_CODESIGN_IDENTITY=-
```

Local builds keep iCloud dictionary sync off and do not check for updates. Ad-hoc builds may ask for macOS permissions again after each rebuild.

## Other commands

- `make check` — verify required tools
- `make whisper` — prepare `whisper.xcframework`
- `make build` — Debug build (`Sulsul Dev.app`)
- `make dev` — build and launch `Sulsul Dev.app`
- `make run` — launch `~/Downloads/Sulsul.app`, or the first match in DerivedData
- `make release` — signed, notarized DMG and Sparkle appcast (after the steps below)
- `make release-setup` — store notarization credentials; reads the Team ID from `Signing.xcconfig`
- `make clean` — remove `~/VoiceInk-Dependencies`
- `make help` — list commands

## Xcode

```bash
make setup
open VoiceInk.xcodeproj
```

Select the `VoiceInk` scheme. Run builds `Sulsul Dev.app`. Archive uses Release and produces `Sulsul.app`. `LOCAL_BUILD` applies only through `make local`.

## Notarized release

1. Set `DEVELOPMENT_TEAM` in `Signing.xcconfig`.
2. Install a Developer ID Application certificate for that team in Keychain.
3. `make release-setup` and enter the Apple ID. The notarytool profile name is `Sulsul-Notarization`.
4. Resolve packages once in Xcode so Sparkle's `generate_keys` is available, then:

```bash
# path is under DerivedData after a package resolve
generate_keys --account Sulsul
```

5. Paste the printed public key over `REPLACE_WITH_SPARKLE_PUBLIC_KEY` in `VoiceInk/Info.plist` (`SUPublicEDKey`). Until that placeholder is replaced, the app does not start Sparkle and does not contact an update server.
6. `make release NOTES=release-notes/<version>.html`

The script writes a temporary export options file with your Team ID. It does not commit, tag, or upload. Upload `Sulsul.dmg` and the generated `appcast.xml` to [github.com/qaws81877/VoiceInk/releases](https://github.com/qaws81877/VoiceInk/releases). The feed URL baked into the app is `https://github.com/qaws81877/VoiceInk/releases/latest/download/appcast.xml`.

## App icon

The current icon is a placeholder. Replace the PNGs in:

- `VoiceInk/Assets.xcassets/AppIcon.appiconset/` (`16-mac.png` through `1024-mac.png`)
- `VoiceInk/Assets.xcassets/menuBarIcon.imageset/`
- `release/dmg/volume-icon.icns` and, if you change the DMG artwork, `release/dmg/background.png` and `background.tiff`

Keep the same pixel sizes the existing images use.
