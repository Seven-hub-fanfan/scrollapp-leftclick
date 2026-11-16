#!/bin/bash
# All release builds share one source list, deployment target and signing path.
set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
SCROLLAPP_ARCHS="arm64 x86_64" bash "$SCRIPT_DIR/build_app.sh"
