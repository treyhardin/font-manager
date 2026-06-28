#!/usr/bin/env bash
#
# One-time: generate the Sparkle EdDSA update-signing key. The private key is stored
# in your login Keychain; the printed SUPublicEDKey goes in project.yml (info.properties).
#
set -euo pipefail
cd "$(dirname "$0")/.."

GENERATE_KEYS="$(find ~/Library/Developer/Xcode/DerivedData/FontManager-*/SourcePackages/artifacts/sparkle/Sparkle/bin -name generate_keys 2>/dev/null | head -1)"
[ -n "$GENERATE_KEYS" ] || { echo "Build the app once first so SwiftPM fetches Sparkle, then re-run."; exit 1; }
"$GENERATE_KEYS"
