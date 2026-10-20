---
name: verify-logger-subsystem
description: Check that every Logger reads AppIdentity.loggerSubsystem instead of a subsystem string literal. Run after adding Swift files with a Logger or copying code from upstream VoiceInk.
---

## Purpose
1. Keep one source for the log subsystem, so `LogExporter` (which filters on `AppIdentity.loggerSubsystem`) exports every app log.
2. Catch literals copied from older files or from upstream VoiceInk (`com.prakashjoshipax.VoiceInk`).

## Related Files
| File | Purpose |
|------|---------|
| `VoiceInk/App/Configuration/AppIdentity.swift` | Defines `loggerSubsystem` |
| `VoiceInk/Infrastructure/Diagnostics/LogExporter.swift` | Exports logs by that subsystem |

## Workflow
1. Literal subsystem check:
   `grep -rn 'subsystem: "' VoiceInk Tests --include='*.swift'`
   - PASS: no output (exit 1).
   - FAIL: any line; replace the literal with `AppIdentity.loggerSubsystem`.

## Exceptions
- `AppIdentity.swift` defines the value as `static let loggerSubsystem = "…"`; the pattern does not match it.
- Vendored package sources under `.local-build.noindex/SourcePackages` are outside `VoiceInk/` and `Tests/` and not checked.

## Output
| Check | Status | Evidence |
|-------|--------|----------|
| No literal Logger subsystem | PASS/FAIL | grep output |
