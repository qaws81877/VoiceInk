---
name: verify
description: Build, launch and drive the Sulsul Dev app to observe a UI change (dashboard, settings panels) with window-only screenshots.
---

## Build and launch
- `make` builds `.build.noindex/Build/Products/Debug/Sulsul Dev.app`; open it with `open "<that path>"`.
- Do not use `make local` to verify: it replaces the user's `~/Downloads/Sulsul.app`.
- Debug keeps its own data (`~/Library/Application Support/com.qaws81877.sulsul.dev`, defaults domain `com.qaws81877.sulsul.dev`), so it starts in onboarding. To reach the main UI: `defaults write com.qaws81877.sulsul.dev hasCompletedOnboardingV2 -bool YES`, relaunch; afterwards `defaults delete com.qaws81877.sulsul.dev hasCompletedOnboardingV2`. A "새로운 소식" sheet appears first; Escape does not close it, click its X.

## Capture
- Capture only the app window: find its id with CoreGraphics `CGWindowListCopyWindowInfo` filtered by the app PID (the main window is the 950x782 one named 술술), then `screencapture -x -o -l <id> out.png`. Never use `screencapture -R` or full-screen capture: other apps' windows overlap and end up in the image.
- `log show` returns nothing for this app from an agent shell.

## Drive
- System Events `click at` lands on a group, not on SwiftUI buttons, and the AX tree is empty. Post real mouse events with CGEvent (`leftMouseDown`/`leftMouseUp` at a screen point).
- Before every click, `activate` the app, check System Events' frontmost process is "Sulsul Dev", and read `position of window 1` (it moves between displays); click at window position + offset. Without that check the click lands in whatever app is on top.
- Typing: `keystroke` guarded by `if frontmost`.
- For connection tests in custom provider panels, use an unreachable local endpoint (`http://127.0.0.1:9/...`) so nothing leaves the machine; do not press "모델 추가" (writes Keychain and settings).
