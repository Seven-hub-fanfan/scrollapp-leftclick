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

### `verify_cursor_recovery.py`

Runs fault injection against genuine recovery journals: native core cache
drift, invalid original descriptors, named cursor readback mismatch and an
unreadable journal. Checks that the service remains alive, blocks new writes,
retains backups, supports retry and archives before explicitly returning to
native cursors. It restores the original baseline after the test.

```bash
python3 scripts/verify_cursor_recovery.py --global \
  build/Scrollapp.app/Contents/MacOS/CursorService /path/to/payloads
```

Quit all running Scrollapp instances first. The directory must contain
`frog.plist`; use an external test directory so fixtures and backup images
do not enter the repository.

### `verify_cursor_raster.swift`

Checks fixed master selection across previous resolution thresholds, explicit
1x/2x representations, marker geometry and padding, animation frame order,
local cursor sizes/hotspots, and repeated shrink/grow cycles for both skins.
It exports current payloads and preview PNGs to an external test directory.

Compile it together with `CursorThemes.swift` and `Localization.swift`, link an
Objective-C object built from `CursorRaster.m`, and pass
`-import-objc-header Scrollapp/CursorRaster.h`. Place the executable under
`Test.app/Contents/MacOS` and copy current `Skins` resources to
`Test.app/Contents/Resources/Skins` so `Bundle.main` resolves them. Run the
executable with the output directory as its sole argument. It makes no global
cursor changes. Pass a `system-cursors.plist` exported by the current helper
in the output directory to verify native previews. Quit any active Scrollapp before exporting genuine system
images or running the separate global service checks.

## Quick Start

```bash
bash scripts/build_app.sh
bash scripts/create_dmg_from_app.sh
```

`build_universal.sh` is a legacy script and does not build the current cursor
skin release.
