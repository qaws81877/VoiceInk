# Verification

Open this before reporting a code change as done, or before testing the app at runtime.

- Gate: `make` (check + Debug build of scheme `VoiceInk`).
- Tests: the `VoiceInkTests` target when touching `Features/Enhancement/`, `Features/Dictionary/`, `Core/Enhancement/AIPrompts.swift`, or test fixtures.
- Korean cleanup changes: update the JSONL fixture cases with the prompt.
- A green build or test run is not evidence that mic capture, paste, TCC permissions, or a live provider response work; say which runtime behavior was not exercised.

## Build and test quirks
- `make` / `make local` failing with "Multiple commands produce …/Resources/AGENTS.md" is the untracked subfolder `AGENTS.md` files (excluded in `.git/info/exclude`) being bundled by the synchronized group. Move them aside for the build and restore them after; changing `project.pbxproj` membership needs the user's approval.
- The scheme's test action builds Release with an empty team, so the plain `xcodebuild test` command fails on signing and on `@testable import`. Run: `xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -only-testing:VoiceInkTests CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES -derivedDataPath .build.noindex`

## Runtime checks
- Several copies with the same bundle ID make macOS launch whichever it picks. Before a runtime test, confirm the running path with `pgrep -lf Sulsul` is `~/Downloads/Sulsul.app`; keep build output in `*.noindex` folders and do not leave extra `.app` copies.
- To diagnose a dictation or cleanup result, read the transcript store first (`~/Library/Application Support/com.qaws81877.sulsul/*.store`, table `ZTRANSCRIPTION`: `ZAIENHANCEMENTMODELNAME`, `ZENHANCEMENTDURATION`, `ZENHANCEDTEXT`, `ZPROMPTNAME`). `log show` returned nothing for the cleanup category. The installed app may be built from a different branch than HEAD.
