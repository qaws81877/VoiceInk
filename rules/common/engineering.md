# Engineering

Open this before editing code, build files, or user data.

- Fine to change without asking: Swift sources and tests under `VoiceInk/` and `Tests/`, prompt fixtures together with their JSONL cases, docs.
- Ask first (show the diff): the list in `CLAUDE.md` "Ask before changing" - signing/xcconfig/entitlements/Info.plist keys, schema list, persisted raw values, UserDefaults keys, `AppIdentity.swift`, `scripts/`, `appcast.xml`, anything that publishes.
- Never hand-edit `project.pbxproj` to add files; synchronized groups pick them up.
- A new `ModeConfig` field needs encode plus tolerant decode (see `Features/Modes/AGENTS.md`).
- When code changes a fact stated in an `AGENTS.md`, tell the user; local `AGENTS.md` files are untracked here.
