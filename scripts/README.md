# Build Scripts

This directory contains the build automation scripts for Scrollapp.

## Scripts

### `build_app.sh`
Builds a universal Apple Silicon + Intel app with a macOS 13 deployment target.
Requires recent Xcode Command Line Tools (tested with SDK 15.5 / Swift 6.1.2).
Catalog previews and the user-supplied Doubao package are bundled. Other full skins
download from the pinned sources in `SkinAssets.swift`.
`FeaturedSkins.swift` contains seven Sweezy entries ordered by publicly displayed
addition counts observed on 2026-11-15. They share the existing All/Favorites library
and download/apply/delete workflow with the two original skins.
Downloads use official first-party complete-pack endpoints, pinned sizes and SHA256.
`CursorArchive.swift` decodes only the pointer/hand CUR entries in memory and never
extracts paths or executes pack contents. `LocalSkinImport.swift` preserves click
hotspots and produces exact 1x/2x images plus native density where available.
`SupplementedCursors.swift` supplies the missing eleven roles using per-skin style
tokens and the user's locally downloaded material. The original pointer/hand remain
unchanged. Completed roles have exact 1x/2x/4x/8x images and semantic hotspots.
Versioned, source-keyed caches are generated off the UI thread on download/startup
and removed together with the local skin. The waiting cursor retains macOS behavior.
Sweezy artwork is downloaded for personal use and is not redistributed in the application bundle.
Set `SCROLLAPP_SIGN_IDENTITY` to a Developer ID Application identity for distribution signing.
Without an identity the build uses an ad-hoc signature and is not notarized.

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

Compile it together with `CursorThemes.swift`, `SkinAssets.swift` and `Localization.swift`, link an
Objective-C object built from `CursorRaster.m`, and pass
`-import-objc-header Scrollapp/CursorRaster.h` and `-D SCROLLAPP_TESTING`.
Run the executable with an external output directory and the source
`Scrollapp/Skins` directory. It installs full resources into isolated test storage,
does not need a bundle, and makes no global
cursor changes. Pass a `system-cursors.plist` exported by the current helper
in the output directory to verify native previews. Quit any active Scrollapp before exporting genuine system
images or running the separate global service checks.

## Quick Start

### `verify_shortcuts.swift`

Verifies the 10-step cap, order, completion without looping, back/reset,
configuration normalization, persistence, recording suspension, target selection,
and failure/permission boundaries using an injected event delivery.

```bash
xcrun swiftc Scrollapp/ShortcutSequence.swift Scrollapp/ShortcutEngine.swift \
  Scrollapp/Localization.swift scripts/verify_shortcuts.swift -o /tmp/verify-shortcuts
/tmp/verify-shortcuts
```

### `verify_prompt_vision.swift` / `verify_prompt_vision.py`

Offline integration checks for all three vision protocols, SSE streaming,
ordinary JSON gateways, authentication error redaction, cancellation, direct
image URLs, size/MIME rejection and history round trips. The Python fixture binds
only loopback and uses a synthetic image and fake key; it does not call a provider
or change the application's profiles/history.

```bash
xcrun swiftc -O Scrollapp/PromptVision.swift Scrollapp/Localization.swift \
  scripts/verify_prompt_vision.swift -o /tmp/verify-prompt-vision
python3 scripts/verify_prompt_vision.py /tmp/verify-prompt-vision
```

Open the native page with `open build/Scrollapp.app --args --show-prompt`.
For an isolated preview, build to a separate app with
`SCROLLAPP_BUNDLE_ID=com.scrollapp.prompt-preview`, then launch it with
`--prompt-preview --show-prompt`. This mode skips global cursor and input services.

```bash
bash scripts/build_app.sh
bash scripts/create_dmg_from_app.sh
```

`build_universal.sh` forwards to the canonical universal build.

### Download and lifecycle validation (2.4.0)

`verify_skin_assets.swift` compiles with `SkinAssets.swift`, `FeaturedSkins.swift`,
`LocalSkinImport.swift`, `CursorArchive.swift` and `Localization.swift`. It tests both original
packages, checksum/image/metadata rejection, bounded HTTP responses, cancellation,
duplicate requests, corrupt local files, offline relaunch and storage failures.
Pass the source `Scrollapp/Skins` directory. All writes go to a disposable temporary directory.

`verify_skin_lifecycle.swift` compiles with `-D SCROLLAPP_TESTING`, catalog,
store, protocol, localization, source metadata/import/archive/supplemented artwork and the raster object. Place it in an isolated
bundle with its own identifier and the built `CursorService` helper. Pass an empty
external test directory. It downloads actual release assets, verifies 13 roles,
applies skins and checks that active deletion restores first. **Quit Scrollapp and
all other cursor test helpers before running it.** Never run global tests concurrently.

`generate_skin_previews.swift` regenerates 64 px catalog PNGs from validated source
packages. Full plist resources are retained in source but excluded from the app.
