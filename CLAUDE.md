# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Fork of `fromis-9/scrollapp` — macOS menu bar app for Windows-style auto-scrolling via middle-click. Adds left-click interruption toggle, settings window, and activation HUD.

Written in Swift and a small Objective-C cursor service, compiled from command
line (no Xcode project required). Universal arm64/x86_64, macOS 13 deployment target.
Actual validation is macOS 26.6.2 / M2 Pro plus Rosetta; do not claim older OS
or Intel hardware coverage from compilation alone.

## Build and install

Use the build script (compiles sources, writes Info.plist, generates the icon from
`img/scrollappicon.png`, installs localization resources, ad-hoc signs):

```bash
./scripts/build_app.sh   # -> build/Scrollapp.app
```

It compiles the app's Swift sources with both architecture targets at macOS 13,
and `CursorService.m` with Clang. Newer cursor APIs are availability guarded.
Only small preview PNGs ship in the bundle; full packages are downloaded using
the versioned URLs and pinned hashes in `SkinAssets.swift`.
`bash scripts/run_app.sh` opens an isolated skin preview; reusable launch
configuration is in `.trae/environments/run.json`.

## Localization

UI is bilingual: English by default, Simplified Chinese when the system language
is Chinese.

- All user-facing strings live in `Scrollapp/Localization.swift` (`L10n.t("key")`),
  an in-code table (English + zh-Hans) — chosen over `.strings` files because the
  app is built with plain `swiftc`. Missing zh keys fall back to English.
- Language is resolved once at launch from `Locale.preferredLanguages`; override
  for testing with `defaults write com.scrollapp.app ScrollappLanguage zh-Hans`
  (or pass `-ScrollappLanguage zh-Hans` on the command line).
- **Never localize persisted values.** `ActivationMethod.rawValue` (and the
  matching raw strings in `ContentView.activationMethods`) stay English because
  they are stored in `UserDefaults`; `displayName` is the localized label.
- Menu items are located by selector/tag (`sensitivityMenuItemTag`,
  `activationMenuItemTag`), never by title — titles are localized.
- `Info.plist` strings are localized via `Scrollapp/{en,zh-Hans}.lproj/InfoPlist.strings`,
  copied into the bundle by the build script.

## Architecture

**Image to Prompt:** `PromptStudioView` is an AppKit/SwiftUI settings page with
reference input on the left and a selectable native text result on the right.
`PromptStudioStore` owns a five-image sequential queue, cancellation tokens,
profile selection, import/capture and a 100-entry local history. ImageIO prepares
1600 px JPEGs and 240 px thumbnails off the main actor; no original full raster
is sent or stored in history. `PromptVision` supports OpenAI-compatible, Gemini
and Anthropic vision protocols, incremental SSE and ordinary JSON gateways.
Provider presets are editable; model availability depends on the user's account.
Profiles go to defaults without secrets; keys are stored in the bundle's Keychain
service. History and reference copies live under
`~/Library/Application Support/<bundle-id>/PromptStudio`.
`--show-prompt` opens the page; `--prompt-preview` skips cursor service startup,
global scroll/shortcut listeners, login registration and introductory permissions.
Use a distinct bundle identifier for isolated tests/previews. Local image import
and API analysis do not require Accessibility; only Capture needs Screen Recording.
Do not add image processing or networking to the scroll loop.

**Cursor skins:** `SettingsRootView` also supplies General / Cursor Skins /
Click Shortcuts / Permissions navigation.
`CursorCatalog` separates theme artwork from system cursor mappings; resources
and extension instructions are in `Scrollapp/Skins`. `CursorSkinStore` serializes
service requests and stores only successfully applied theme IDs.
`CursorService.m` is independently implemented and uses dynamically resolved
private APIs, an atomic recovery journal and a kqueue parent-lifetime guard.
Normal quit waits for restoration; app crash restores via the helper; helper
crash triggers one recovery reconnect. Preserve Wait/Empty/busy/disappearing
states. Do not add skin rendering or reload work to the 10 ms scroll loop.

**Scrolling:** logic in `ScrollappApp.swift`, in `AppDelegate: NSObject, NSApplicationDelegate`.

**Click shortcuts:** `ShortcutSequence` stores up to 10 keycode/modifier chords
and the next-step position in one versioned defaults value. `ShortcutEngine`
listens separately for the selected left/middle mouse-up after a click (middle
by default), sends a complete key-down/up
chord to the clicked foreground process, then advances. Optional Loop wraps at
the end; it is off by default. Enabling Loop after completion rearms the first
step without sending it immediately. App-local clicks and drags are ignored. Back changes the next position,
not an external app's undo state. Recording temporarily suspends execution;
edits reset progress. Permissions, secure input and held modifiers are checked
before delivery. Middle singles wait for the system double-click interval when
double-middle auto-scroll is selected; doubles cancel both shortcut deliveries.
Auto-scroll defaults to double middle click. Keep this engine out of the scroll loop.
`ShortcutInputShield` installs a head HID event tap only while the shortcut page
is focused, swallows outside hotkeys and records original physical keycodes.
Ordinary page keys are delivered through NSApplication's local queue, and
direct-to-process injected keys cannot become recorded chords.

**Event monitors:**
- `globalMonitor`/`localMonitor` — detect activation button (middle-click by default) via `.otherMouseDown`
- `clickMonitor` — tracks left/right/other clicks to exit auto-scroll, respects `leftClickDoesNotInterrupt` flag
- `optionKeyMonitor` — detects Option key for trackpad activation
- `scrollMonitor` — detects two-finger scroll while Option is held

**Scroll loop:** `performScroll()` runs at 0.01s intervals via `Timer`, calculates cursor offset from `originalPoint`, applies quadratic acceleration + sensitivity scaling, posts `CGEvent(scrollWheelEvent2Source:)` to `.cgSessionEventTap`.

**Settings sync:** `ContentView` uses `@AppStorage` with `.onChange` handlers posting custom `NotificationCenter` notifications. `AppDelegate` observes these (not `UserDefaults.didChangeNotification`, which caused `SMAppService` loop issues).

**Dock icon:** `LSUIElement=true` by default (no Dock). `showSettingsWindow()` calls `NSApp.setActivationPolicy(.regular)`; `windowShouldClose` restores `.accessory`.

## Permissions

Automatic scrolling requires **Accessibility**; **Input Monitoring** supports global input.
`PermissionStore` refreshes status on activation and the persistent permissions
page links to System Settings. Ad-hoc rebuilds change signing identity and may
require removing the old authorization entry and adding the current app again.
Cursor skins operate separately from scrolling permission.

## GitHub Releases

Use `gh release` for uploads. The canonical package is
`build/Scrollapp-<version>-universal.dmg`. Without a provisioned Developer ID
and notarization, distribute as a clearly labeled prerelease; do not claim
Gatekeeper acceptance. If changes are not committed, include a source snapshot
and explain that the tag's commit does not represent that snapshot.
