---
name: verify-cleanup-model-catalog
description: Check that every Korean cleanup model constant is selectable in the AI provider model catalog. Run after changing KoreanCleanupModels or AIProvider model lists.
---

## Purpose
1. Keep `KoreanCleanupModels` (`openAI`, `anthropic`) selectable in the mode screen.
2. Catch a cleanup default that points to a model missing from `AIProvider.availableModels`.
3. Keep starter modes and adoption on models the picker can show.

## Related Files
| File | Purpose |
|---|---|
| VoiceInk/Features/Enhancement/KoreanCleanup/KoreanCleanupRequest.swift | `KoreanCleanupModels` constants |
| VoiceInk/Features/Enhancement/Models/AIProvider.swift | `AIProvider.availableModels` catalog |
| VoiceInk/Features/Enhancement/KoreanCleanup/KoreanCleanupAdoption.swift | adoption writes these models |
| VoiceInk/Features/Modes/Templates/StarterModeFactory.swift | starter modes write these models |

## Workflow
1. Check each cleanup model constant against the catalog:
   ```bash
   for m in $(grep -oE 'static let (openAI|anthropic) = "[^"]+"' VoiceInk/Features/Enhancement/KoreanCleanup/KoreanCleanupRequest.swift | cut -d'"' -f2); do grep -q "\"$m\"," VoiceInk/Features/Enhancement/Models/AIProvider.swift && echo "OK $m" || echo "MISSING $m"; done
   ```
   - PASS: every line is `OK`.
   - FAIL: any `MISSING <model>`; add it to the matching `AIProvider` case list.

## Exceptions
- A model listed only under a different provider case still prints `OK`. The command checks presence in the file, not the case, so confirm the case by eye when a model moves provider.
- Models chosen through a custom provider (`CustomAIProviderManager`) are not in the static catalog and are not violations.

## Output
| Check | Status | Evidence |
|---|---|---|
| cleanup models in catalog | PASS/FAIL | `OK`/`MISSING` lines |
