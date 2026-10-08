# 술술 (Sulsul)

술술 is a modified fork of [VoiceInk](https://github.com/Beingpax/VoiceInk) by Prakash Joshi (Pax), licensed under the GNU General Public License v3.0. Original copyright notices stay in the source. This fork does not grant any trademark rights in the VoiceInk name.

Upstream: https://github.com/Beingpax/VoiceInk

This copy is a personal build for a few people. Each person enters their own API keys. No API keys are bundled. See [NOTICE](NOTICE) for the change list and [BUILDING.md](BUILDING.md) for how to build it.

Changes in this fork:

- The app is 술술 (product name Sulsul, bundle ID `com.qaws81877.sulsul`) and keeps its own Application Support folder, Keychain service, and preferences so it does not share data with an installed copy of VoiceInk.
- The license, trial, and purchase system, including Polar, is removed. Release builds are unlocked.
- The app no longer contacts the original author's servers (announcements, Sparkle appcast, GitHub star prompt, Polar, and in-app documentation links).
- VoiceInk Refine and its XPC service are removed. That model's license does not allow redistribution.
- iCloud dictionary sync is off. It depended on the original iCloud container.
- Onboarding can skip the transcription-model download or pick a Whisper model. It does not require Parakeet.

The Xcode scheme is still named `VoiceInk`. Set your Apple Developer Team ID only in [Signing.xcconfig](Signing.xcconfig).

## Build

```bash
make local
open ~/Downloads/Sulsul.app
```

Details, notarization, and where to put a real app icon are in [BUILDING.md](BUILDING.md).

## Features

- Local and cloud transcription
- Modes that switch with the frontmost app or a spoken trigger
- Optional AI enhancement with your own provider key
- Global keyboard and mouse shortcuts
- Personal dictionary and text replacements

## Requirements

- macOS 15.0 or later

## License

GNU General Public License v3.0. The full text is in [LICENSE](LICENSE).

## Acknowledgments

### Core technology

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — Whisper inference
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet models
- [TranscribeCpp for Swift](https://github.com/Beingpax/Transcribe-cpp-swift) — SwiftPM distribution of [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp)
- [SenseVoice Small](https://huggingface.co/FunAudioLLM/SenseVoiceSmall) by FunAudioLLM / Alibaba, under the [FunASR Model Open Source License Agreement](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE)

### Dependencies

- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin)
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter)
- [Zip](https://github.com/marmelroy/Zip)
- [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit)
- [Swift Atomics](https://github.com/apple/swift-atomics)

VoiceInk was made by Pax.
