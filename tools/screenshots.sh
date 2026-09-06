#!/bin/zsh
# Regenerates docs/screenshots/*.png from the real SwiftUI views.
#
# Rendered with SwiftUI's ImageRenderer rather than captured from a running window:
# no Screen Recording permission required, and the output is identical on every
# machine, so the README stays reproducible.
#
# The app is sandboxed, so the test host writes into its own container and this
# script copies the results out. The renders also run as part of the normal test
# suite, which keeps a crash-on-render regression from reaching main.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/docs/screenshots"
mkdir -p "$DEST"

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

xcodebuild \
  -project "$ROOT/HermesVoice/HermesVoice.xcodeproj" \
  -scheme HermesVoice \
  -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:HermesVoiceTests/ScreenshotTests \
  test >"$LOG" 2>&1 || { grep -E 'error:' "$LOG" | head -5; exit 1; }

COUNT=0
while IFS= read -r line; do
  SRC="${line#wrote }"
  SRC="${SRC% \(*}"
  [[ -f "$SRC" ]] || continue
  cp "$SRC" "$DEST/"
  COUNT=$((COUNT + 1))
  echo "  $(basename "$SRC")"
done < <(grep -E '^wrote ' "$LOG")

if [[ $COUNT -eq 0 ]]; then
  echo "No screenshots produced." >&2
  exit 1
fi
echo "$COUNT screenshots written to docs/screenshots/"
