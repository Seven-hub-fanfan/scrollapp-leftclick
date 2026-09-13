# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Fork of `fromis-9/scrollapp` — macOS menu bar app for Windows-style auto-scrolling via middle-click. Adds left-click interruption toggle, settings window, and activation HUD.

Written in Swift, compiled from command line (no Xcode required). macOS 11.0+, Apple Silicon.

## Build and install

Use the build script (compiles sources, writes Info.plist, generates the icon from
`img/scrollappicon.png`, installs localization resources, ad-hoc signs):

```bash
./scripts/build_app.sh   # -> build/Scrollapp.app
```

It compiles `Scrollapp/{ScrollappApp,ContentView,Localization}.swift` with
`xcrun swiftc -target arm64-apple-macos15.0` (SwiftUI APIs used require 15.0).

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

All logic in `ScrollappApp.swift` (~760 lines), a single `AppDelegate: NSObject, NSApplicationDelegate` class.

**Event monitors:**
- `globalMonitor`/`localMonitor` — detect activation button (middle-click by default) via `.otherMouseDown`
- `clickMonitor` — tracks left/right/other clicks to exit auto-scroll, respects `leftClickDoesNotInterrupt` flag
- `optionKeyMonitor` — detects Option key for trackpad activation
- `scrollMonitor` — detects two-finger scroll while Option is held

**Scroll loop:** `performScroll()` runs at 0.01s intervals via `Timer`, calculates cursor offset from `originalPoint`, applies quadratic acceleration + sensitivity scaling, posts `CGEvent(scrollWheelEvent2Source:)` to `.cgSessionEventTap`.

**Settings sync:** `ContentView` uses `@AppStorage` with `.onChange` handlers posting custom `NotificationCenter` notifications. `AppDelegate` observes these (not `UserDefaults.didChangeNotification`, which caused `SMAppService` loop issues).

**Dock icon:** `LSUIElement=true` by default (no Dock). `showSettingsWindow()` calls `NSApp.setActivationPolicy(.regular)`; `windowShouldClose` restores `.accessory`.

## Permissions

Requires **Accessibility** and **Input Monitoring** in System Settings. Every rebuild changes the ad-hoc signature, invalidating TCC permissions — must re-grant after replacing binary.

## GitHub Releases

Releases uploaded via API (curl with `gh auth token`). DMG at `build/Scrollapp.dmg`.
