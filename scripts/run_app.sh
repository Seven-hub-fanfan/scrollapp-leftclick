#!/bin/bash
# Run an isolated skin preview alongside the installed Scrollapp.
# Preferences and mouse listeners are isolated; global skins are real.
set -euo pipefail
PROJECT_ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
PREVIEW_APP="${TMPDIR:-/tmp/}Scrollapp Development.app"
SCROLLAPP_OUTPUT_DIR="$PREVIEW_APP" \
SCROLLAPP_BUNDLE_ID="com.scrollapp.skins-preview" \
bash "$PROJECT_ROOT/scripts/build_app.sh"
OPEN_OPTIONS=(-W)
if [ -n "${SCROLLAPP_PREVIEW_LOG:-}" ]; then
  OPEN_OPTIONS+=(--stdout "$SCROLLAPP_PREVIEW_LOG" --stderr "${SCROLLAPP_PREVIEW_LOG}.err")
fi
open "${OPEN_OPTIONS[@]}" -a "$PREVIEW_APP" --args --skin-preview --show-skins -ScrollappLanguage zh-Hans "$@"
