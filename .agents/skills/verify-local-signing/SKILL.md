---
name: verify-local-signing
description: Check that make local signs Sulsul.app with the Apple Development identity instead of ad-hoc, so TCC permissions survive rebuilds. Run after changing LocalBuild.xcconfig, the Makefile local/build targets, or signing settings, and when macOS asks again for microphone or accessibility permission.
---

## Purpose
1. Keep `LocalBuild.xcconfig` from setting `CODE_SIGN_IDENTITY`; `-xcconfig` settings override the identity `make local` passes on the command line.
2. Confirm the resolved Release setting for target VoiceInk is the Apple Development identity, not `-`.
3. Confirm the installed `~/Downloads/Sulsul.app` is signed by a certificate, so its designated requirement is not a per-build cdhash.

## Related Files
| File | Purpose |
|------|---------|
| `LocalBuild.xcconfig` | Settings applied only by `make local`; must not set `CODE_SIGN_IDENTITY` |
| `Makefile` | `RESOLVE_SIGNING_IDENTITY` picks the identity; `VERIFY_SIGNATURE` prints the result after `make local` |
| `VoiceInk/VoiceInk.local.entitlements` | Entitlements for `make local`; no profile-only keys, so Apple Development signing works without a team |
| `VoiceInk/VoiceInk.debug.entitlements` | Debug entitlements; `keychain-access-groups` needs a provisioning profile, so "Sulsul Dev" stays ad-hoc |

## Workflow
1. Static override check:
   `grep -nE '^\s*CODE_SIGN_IDENTITY' LocalBuild.xcconfig`
   - PASS: no output (exit 1).
   - FAIL: any line; that value replaces the identity from the Makefile.
2. Resolved build setting (read-only, no build):
   `xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release -xcconfig LocalBuild.xcconfig CODE_SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development: /{print $2; exit}')" -skipPackagePluginValidation -skipMacroValidation -showBuildSettings 2>/dev/null | awk '/Build settings for action build and target VoiceInk:/{f=1} f && /^ *CODE_SIGN_IDENTITY =/{print; exit}'`
   - PASS: `CODE_SIGN_IDENTITY = <40-hex SHA of the Apple Development identity>`.
   - FAIL: `CODE_SIGN_IDENTITY = -` or empty.
3. Installed app signature:
   `codesign -dvv ~/Downloads/Sulsul.app 2>&1 | grep '^Authority=Apple Development'`
   - PASS: one `Authority=Apple Development: …` line.
   - FAIL: no line (`Signature=adhoc`; `codesign -d -r-` shows `cdhash`). The "Using stable local signing identity" log line is not evidence; it is only an echo.

## Exceptions
- No Apple Development identity, or more than one without `LOCAL_CODESIGN_IDENTITY`: `make local` falls back to ad-hoc by design and prints a WARNING; steps 2–3 failing is expected there.
- `LOCAL_CODESIGN_IDENTITY=-` is an intentional ad-hoc build.
- "Sulsul Dev" from `make` / `make dev` is ad-hoc on purpose (debug entitlements need a profile); do not report it.
- Step 3 checks the last installed build; if `~/Downloads/Sulsul.app` predates the change, rebuild with `make local` before judging.

## Output
| Check | Status | Evidence |
|-------|--------|----------|
| xcconfig does not set CODE_SIGN_IDENTITY | PASS/FAIL | grep output |
| Resolved Release identity | PASS/FAIL | `CODE_SIGN_IDENTITY = …` line |
| Installed app signed by certificate | PASS/FAIL | `Authority=` line |
