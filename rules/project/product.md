# Product

Open this before changing behavior users see, persisted data, identity, or anything that talks to the network.

- Repo: 술술 (Sulsul), a GPLv3 personal fork of VoiceInk for macOS 15+. The repo and scheme keep the name `VoiceInk`; the product is Sulsul (`com.qaws81877.sulsul`).
- Source of truth: `AGENTS.md` (structure, ANTI-PATTERNS), `README.md` / `NOTICE` (fork changes), `BUILDING.md` (builds, signing), `docs/PLAN.md` (current plan).
- Invariants: must coexist with an installed upstream VoiceInk; API keys only in Keychain, entered by each user; no contact with upstream servers; persisted raw values and the SwiftData schema order never change. Details: `AGENTS.md` ANTI-PATTERNS.
- Korean cleanup behavior is pinned by prompt fixtures and JSONL cases under `Tests/VoiceInkTests/`.
- Non-goals: redistribution of VoiceInk Refine, upstream licensing/Polar, Sparkle updates before `SUPublicEDKey` is replaced.
