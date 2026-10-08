#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SIGNING_XCCONFIG="$REPO_ROOT/Signing.xcconfig"
PROFILE_NAME="${VOICEINK_NOTARY_PROFILE:-Sulsul-Notarization}"
TEAM_ID="${VOICEINK_DEVELOPMENT_TEAM:-}"
if [[ -z "$TEAM_ID" && -f "$SIGNING_XCCONFIG" ]]; then
    TEAM_ID="$(awk -F= '/^DEVELOPMENT_TEAM[[:space:]]*=/ { gsub(/[[:space:]]|\/\/.*/, "", $2); print $2; exit }' "$SIGNING_XCCONFIG")"
fi

if [[ -z "$TEAM_ID" ]]; then
    printf 'error: Set DEVELOPMENT_TEAM in Signing.xcconfig before make release-setup\n' >&2
    exit 1
fi

printf 'Apple Developer Apple ID: '
read -r APPLE_ID || true

if [[ -z "$APPLE_ID" ]]; then
    printf 'error: Apple ID is required\n' >&2
    exit 1
fi

printf '\nnotarytool will securely prompt for your app-specific password.\n'
printf 'Team ID: %s\n' "$TEAM_ID"
xcrun notarytool store-credentials "$PROFILE_NAME" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --validate

printf '\nSaved and validated notarytool profile: %s\n' "$PROFILE_NAME"
