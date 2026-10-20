# Verification

Open this before reporting a code change as done, or before testing the app at runtime.

- Gate: `make` (check + Debug build of scheme `VoiceInk`).
- Tests: the `VoiceInkTests` target when touching `Features/Enhancement/`, `Features/Dictionary/`, `Core/Enhancement/AIPrompts.swift`, or test fixtures.
- Korean cleanup changes: update the JSONL fixture cases with the prompt.
- A green build or test run is not evidence that mic capture, paste, TCC permissions, or a live provider response work; say which runtime behavior was not exercised.

## Build and test quirks
- `make` / `make local` failing with "Multiple commands produce …/Resources/AGENTS.md" is the untracked subfolder `AGENTS.md` files (excluded in `.git/info/exclude`) being bundled by the synchronized group. Move them aside for the build and restore them after; changing `project.pbxproj` membership needs the user's approval.
- Run tests with `make test`. A plain `xcodebuild test` fails on signing ("requires a development team"). The target signs ad-hoc with `LocalBuild.xcconfig` and builds into `.test-build.noindex`; pointing a test build at `.build.noindex` replaces `Sulsul Dev.app` with a `LOCAL_BUILD` binary.
- "The test runner hung before establishing connection." has come from the environment, not the change: it reproduced on a clean HEAD worktree and passed on a later rerun. Check HEAD and look for a pending macOS dialog (SecurityAgent) before changing code.

## Runtime checks
- Several copies with the same bundle ID make macOS launch whichever it picks. Before a runtime test, confirm the running path with `pgrep -lf Sulsul` is `~/Downloads/Sulsul.app`; keep build output in `*.noindex` folders and do not leave extra `.app` copies.
- To diagnose a dictation or cleanup result, read the transcript store first (`~/Library/Application Support/com.qaws81877.sulsul/*.store`, table `ZTRANSCRIPTION`: `ZAIENHANCEMENTMODELNAME`, `ZENHANCEMENTDURATION`, `ZENHANCEDTEXT`, `ZPROMPTNAME`). `log show` returns nothing for this app from an agent shell (subsystem and process predicates alike), so empty output is not evidence of no errors. The installed app may be built from a different branch than HEAD.
