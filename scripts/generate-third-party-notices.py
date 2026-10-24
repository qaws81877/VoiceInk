#!/usr/bin/env python3
"""Regenerate VoiceInk/Resources/THIRD_PARTY_NOTICES.txt.

The file holds the GPL-3.0 text of this program and the license text of every
third-party component linked into or bundled with the app, so a binary release
(DMG) gives recipients the notices those licenses require. Run it after a
dependency change, then commit the result:

    python3 scripts/generate-third-party-notices.py          # rewrite the file
    python3 scripts/generate-third-party-notices.py --check  # exit 1 if it is stale

Reads versions from Package.resolved and license texts from the SwiftPM checkouts
(build once with `make` first). Texts that SwiftPM checkouts lack live in
release/licenses/. Standard library only; no network access.
"""
import argparse
import glob
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ap = argparse.ArgumentParser()
ap.add_argument("--repo-root", default=REPO)
ap.add_argument("--checkouts", help="SwiftPM checkouts directory (default: search the build folders)")
ap.add_argument("--licenses-dir", help="default: <repo>/release/licenses")
ap.add_argument("--output", help="default: <repo>/VoiceInk/Resources/THIRD_PARTY_NOTICES.txt")
ap.add_argument("--check", action="store_true", help="do not write; exit 1 if the file differs")
args = ap.parse_args()
REPO = os.path.abspath(args.repo_root)
LIC = args.licenses_dir or f"{REPO}/release/licenses"
OUTPUT = args.output or f"{REPO}/VoiceInk/Resources/THIRD_PARTY_NOTICES.txt"
candidates = [args.checkouts] if args.checkouts else [
    f"{REPO}/.build.noindex/SourcePackages/checkouts",
    f"{REPO}/.test-build.noindex/SourcePackages/checkouts",
    f"{REPO}/.local-build/SourcePackages/checkouts",
]
C = next((c for c in candidates if c and os.path.isdir(c)), None)
if C is None:
    sys.exit("No SwiftPM checkouts found. Run `make` first or pass --checkouts.")
resolved = json.load(open(f"{REPO}/VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"))
pins = {p["identity"]: p["state"] for p in resolved["pins"]}


def ver(identity):
    s = pins[identity]
    return s.get("version") or (s.get("branch", "") + " @ " + s["revision"][:12])


def read(path):
    return open(path, encoding="utf-8").read().rstrip() + "\n"

# name, version, url, SPDX, linking, [(label, path)]
components = [
  ("whisper.cpp / ggml (whisper.framework)", "built from a local whisper.cpp checkout", "https://github.com/ggml-org/whisper.cpp", "MIT",
   "bundled framework", [("LICENSE", LIC + "/whisper.cpp.LICENSE")]),
  ("transcribe.cpp via Transcribe-cpp-swift (CTranscribe.framework)", ver("transcribe-cpp-swift"), "https://github.com/handy-computer/transcribe.cpp", "MIT",
   "bundled framework", [("LICENSE", C + "/Transcribe-cpp-swift/LICENSE"),
                          ("THIRD-PARTY-LICENSES.md (ggml, miniz statically linked into the native artifact)", C + "/Transcribe-cpp-swift/THIRD-PARTY-LICENSES.md")]),
  ("LLMkit", ver("llmkit"), "https://github.com/Beingpax/LLMkit", "MIT", "linked into the app", [("LICENSE", C + "/LLMkit/LICENSE")]),
  ("FluidAudio", ver("fluidaudio"), "https://github.com/FluidInference/FluidAudio", "Apache-2.0", "linked into the app (plus its resource bundle)",
   [("LICENSE", C + "/FluidAudio/LICENSE")] + [(f"ThirdPartyLicenses/{os.path.basename(p)}", p) for p in sorted(glob.glob(C + "/FluidAudio/ThirdPartyLicenses/*"))]),
  ("Swift Atomics", ver("swift-atomics"), "https://github.com/apple/swift-atomics", "Apache-2.0", "linked into the app", [("LICENSE.txt", C + "/swift-atomics/LICENSE.txt")]),
  ("Sparkle", ver("sparkle"), "https://github.com/sparkle-project/Sparkle", "MIT-style, with bundled components under their own terms", "bundled framework (automatic updates are disabled in this fork)", [("LICENSE", C + "/Sparkle/LICENSE")]),
  ("MediaRemoteAdapter", "branch master of https://github.com/Beingpax/mediaremote-adapter (a fork that dropped the license file; the text below is from the original project)", "https://github.com/ungive/mediaremote-adapter", "BSD-3-Clause",
   "bundled framework", [("LICENSE (original project, ungive/mediaremote-adapter)", LIC + "/mediaremote-adapter.LICENSE")]),
  ("Zip", ver("zip"), "https://github.com/marmelroy/Zip", "MIT", "linked into the app", [("LICENSE", C + "/Zip/LICENSE")]),
  ("SelectedTextKit", ver("selectedtextkit"), "https://github.com/tisfeng/SelectedTextKit", "MIT", "linked into the app", [("LICENSE", C + "/SelectedTextKit/LICENSE")]),
  ("AXSwift (via SelectedTextKit)", ver("axswift"), "https://github.com/tisfeng/AXSwift", "MIT", "linked into the app", [("LICENSE", C + "/AXSwift/LICENSE")]),
  ("KeySender (via SelectedTextKit)", ver("keysender"), "https://github.com/jordanbaird/KeySender", "MIT", "linked into the app", [("LICENSE", C + "/KeySender/LICENSE")]),
  ("swift-markdown-ui", ver("swift-markdown-ui"), "https://github.com/gonzalezreal/swift-markdown-ui", "MIT", "linked into the app", [("LICENSE", C + "/swift-markdown-ui/LICENSE")]),
  ("NetworkImage (via swift-markdown-ui)", ver("networkimage"), "https://github.com/gonzalezreal/NetworkImage", "MIT", "linked into the app", [("LICENSE", C + "/NetworkImage/LICENSE")]),
  ("swift-cmark (via swift-markdown-ui)", ver("swift-cmark"), "https://github.com/swiftlang/swift-cmark", "BSD-2-Clause and MIT, several copyright holders", "linked into the app", [("COPYING", C + "/swift-cmark/COPYING")]),
  ("Silero VAD model (ggml-silero-v5.1.2.bin)", "5.1.2, converted to ggml format by ggml-org (ggml-org/whisper-vad)", "https://github.com/snakers4/silero-vad", "MIT", "bundled resource", [("LICENSE", LIC + "/silero-vad.LICENSE")]),
]

bar = "=" * 78
out = []
out.append("""LICENSE AND THIRD-PARTY NOTICES

Sulsul (술술) is a modified fork of VoiceInk and is licensed under the GNU General
Public License v3.0 (full text in item 0 below, also LICENSE and NOTICE in the source
repository, https://github.com/qaws81877/sulsul). It includes or links the third-party
components listed below. Each component remains under its own license, reproduced
here in full as those licenses require. The GPL-3.0 does not change those terms.

The list reflects the dependency versions pinned in this release
(VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved).

CONTENTS
   0. Sulsul (this program) - GNU General Public License v3.0
""")
for i, (n, v, u, l, link, files) in enumerate(components, 1):
    out.append(f"  {i:2}. {n} - {l}\n")
out.append("""  --  Assets inherited from VoiceInk
  --  Speech models downloaded by the user (not bundled)

""")
out.append(f"\n{bar}\n0. Sulsul (this program)\n{bar}\n")
out.append("""Source  : https://github.com/qaws81877/sulsul
License : GNU General Public License v3.0 (full text below)

Sulsul is a modified fork of VoiceInk by Prakash Joshi (Pax) and the VoiceInk
contributors (https://github.com/Beingpax/VoiceInk). The list of modifications is in
the NOTICE file of the source repository. The complete corresponding source of this
release is available at the repository above, at the tagged commit.

--- LICENSE ---

""")
out.append(read(REPO + "/LICENSE"))
for i, (n, v, u, l, link, files) in enumerate(components, 1):
    out.append(f"\n{bar}\n{i}. {n}\n{bar}\n")
    out.append(f"Version : {v}\nSource  : {u}\nLicense : {l}\nUsed as : {link}\n")
    for label, path in files:
        out.append(f"\n--- {label} ---\n\n")
        out.append(read(path))

out.append(f"""
{bar}
Assets inherited from VoiceInk
{bar}
The built-in recording sounds (sound1-sound7), the app icon artwork and the browser-URL
AppleScripts (*.scpt) are byte-identical to the files in the upstream VoiceInk repository
(https://github.com/Beingpax/VoiceInk), which is licensed under GPL-3.0. Upstream does
not state a separate origin or license for the sounds or the icon.

{bar}
Speech models downloaded by the user (not bundled)
{bar}
These models are fetched from Hugging Face when the user chooses them. They are not part
of this distribution. Their licenses, as published on the model pages, are:

  - Whisper ggml models (ggerganov/whisper.cpp) .............................. MIT
  - NVIDIA Parakeet TDT 0.6B v2 and v3 (FluidInference/parakeet-tdt-0.6b-v2-coreml,
    -v3-coreml) ............................................................. CC-BY-4.0
    Created by NVIDIA; the CoreML ports are by FluidInference. Attribution required.
  - Parakeet Ultra (FluidInference/parakeet-ultra-coreml) ................... CC-BY-4.0
    Post-trained by moondream from nvidia/parakeet-tdt-0.6b-v3 (CC-BY-4.0, kept as
    the upstream checkpoint's license).
  - Parakeet Unified 0.6B (FluidInference/parakeet-unified-en-0.6b-coreml)
    The CoreML port is labelled CC-BY-4.0 on its model page. The original
    (nvidia/parakeet-unified-en-0.6b) is released by NVIDIA under the NVIDIA Open Model
    License: https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/
    The two labels disagree. Treat the NVIDIA Open Model License as the governing terms.
  - Nemotron Multilingual and Nemotron Latin (both ship in
    FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML) ... OpenMDW-1.1
    Derived from nvidia/nemotron-3.5-asr-streaming-0.6b, released by NVIDIA under
    OpenMDW-1.1 (https://openmdw.ai/license/1-1/). Attribution to NVIDIA and the
    OpenMDW-1.1 notice must be retained when redistributing.
  - Cohere Transcribe (handy-computer/cohere-transcribe-03-2026-gguf) ... Apache-2.0
  - SenseVoice Small (FunAudioLLM, Alibaba) ... FunASR Model Open Source License
    Agreement: https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE
""")
text = "".join(out)
if args.check:
    current = open(OUTPUT, encoding="utf-8").read() if os.path.exists(OUTPUT) else ""
    if current != text:
        sys.exit(f"{OUTPUT} is out of date. Run scripts/generate-third-party-notices.py")
    print("THIRD_PARTY_NOTICES.txt is up to date")
else:
    open(OUTPUT, "w", encoding="utf-8").write(text)
    print(f"wrote {OUTPUT} ({len(text)} characters)")
