# Build Scripts

This directory contains the build automation scripts for Scrollapp.

## Scripts

### `build_app.sh`
Builds the current Apple Silicon release using the system Swift and Clang tools.
Requires macOS 15 or later and Xcode Command Line Tools.

**Usage:**
```bash
bash scripts/build_app.sh
```

**Output:** `build/Scrollapp.app`

### `create_dmg_from_app.sh`
Creates a distributable DMG file from a built Scrollapp.app.

**Usage:**
```bash
bash scripts/create_dmg_from_app.sh
# Optional app and destination:
bash scripts/create_dmg_from_app.sh /path/to/Scrollapp.app /path/to/Scrollapp.dmg
```

**Output:** `build/Scrollapp-<app-version>-<architecture>.dmg`

The disk image includes an Applications shortcut and installation instructions.
Packaging verifies and preserves the app signature. It refuses to overwrite an
existing output. Version and architecture come from the built app.

### `run_app.sh`

`bash scripts/run_app.sh` builds and opens an isolated skin preview.
The preview skips scrolling permission requests and event listeners, while
cursor skins still apply globally.

### `verify_cursor_service.py`

Runs integration checks against the real WindowServer. Export current theme
payloads to an external temporary directory before invoking it:

```bash
python3 scripts/verify_cursor_service.py --global \
  build/Scrollapp.app/Contents/MacOS/CursorService /path/to/payloads
```

The checks temporarily replace cursors and verify complete recovery.

## Quick Start

```bash
bash scripts/build_app.sh
bash scripts/create_dmg_from_app.sh
```

`build_universal.sh` is a legacy script and does not build the current cursor
skin release.
