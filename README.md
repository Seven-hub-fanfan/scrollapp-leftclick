# Scrollapp

[![GitHub Downloads](https://img.shields.io/github/downloads/Seven-hub-fanfan/scrollapp-leftclick/total.svg)](https://github.com/Seven-hub-fanfan/scrollapp-leftclick/releases)

A native macOS utility for auto-scrolling, cursor skins, click-triggered shortcuts
and image-to-prompt analysis. Double middle-click enables auto-scroll by default;
move your cursor to control scrolling speed and direction.

<img src="img/scrollappicon.png" width="100" alt="Scrollapp Icon">

## Features

- **Auto-scrolling**: Activate with configurable mouse/key combinations, move cursor to control scrolling
- **7 Activation Methods**: Choose from middle-click, modified clicks, side buttons, or double-click
- **Trackpad Support**: Option+Scroll activation for trackpad users
- **Adjustable Sensitivity**: Slider control from 0.2x to 3.0x speed with exponential slow-speed scaling
- **Intuitive Controls**: Move cursor up/down to control scroll direction and speed
- **Customizable Direction**: Option to invert scrolling direction based on preference
- **Launch at Login**: Optional automatic startup
- **Menu Bar Integration**: Quick access via status menu in the menu bar
- **Global Cursor Skins**: System Default, Nai Wa and Xiao Qi, with favorites and previews
- **Optional Skin Downloads**: Download only the skins you want, use them offline, and delete local downloads
- **Persistent Permissions Page**: Reopen permission settings after skipping the first launch prompt
- **Cursor Size**: Adjustable from 0.5× to 8×, with immediate local feedback
- **High-resolution Xiao Qi**: Five PNG resolutions up to 512 px, generated from a 4× restored reference
- **Cursor Recovery**: Restores the original cursors on quit or app crash
- **Image to Prompt**: Native reference/result workspace with local images, clipboard, image URLs and region capture
- **Multiple Vision APIs**: Save and switch OpenAI-compatible, Gemini and Anthropic connections, including local Ollama; keys stay in macOS Keychain
- **Prompt History**: Chinese/English/JSON/negative results, five-image sequential analysis, cancellation, favorites and Markdown export

## Installation

1. **Download**: Download `Scrollapp-2.5.0-universal.dmg` from the [v2.5.0 release](https://github.com/Seven-hub-fanfan/scrollapp-leftclick/releases/tag/v2.5.0). It contains Apple Silicon and Intel binaries.
2. **Install**: Open the DMG file and drag Scrollapp to your Applications folder.
3. **Security Override**: Since the app is distributed without Apple notarization, you'll need to manually allow it:
   - **Method 1**: Right-click on Scrollapp.app → "Open" → "Open" in the dialog
   - **Method 2**: If you see "can't be opened" error, go to System Settings → Privacy & Security → scroll down to find "Scrollapp was blocked" → click "Open Anyway"
4. **Grant Permissions**:
   - When prompted, grant Accessibility and Input Monitoring permissions.
   - If you miss a prompt, open **Permissions** from the app sidebar or menu bar to return to System Settings:
     - Go to `System Settings > Privacy & Security > Accessibility` and add Scrollapp.
     - Go to `System Settings > Privacy & Security > Input Monitoring` and enable Scrollapp.
   - You may need to restart the app after granting permissions.

Quit an older Scrollapp before replacing it. The new app may need its
Accessibility and Input Monitoring permissions granted again.

Open **Cursor Skins** from the menu bar, select a skin, download it, then apply it.
First download requires access to GitHub; installed skins work offline.
**Delete Download** frees local storage and first restores system cursors if the
skin is active. Upgrading from bundled skins requires downloading them again.
Open **General** to adjust cursor size and enable the red click hotspot. Its
3–16 pt diameter is independent of cursor size. **Reset** selects the system
skin while keeping size and hotspot settings; quitting restores the original cursors.

## How to Use

### Activating Auto-scroll

**With Mouse (Configurable):**
Choose your preferred activation method from the menu bar:
- **Middle Click**
- **Shift + Middle Click**
- **Cmd + Middle Click** 
- **Option + Middle Click**
- **Mouse Button 4** (side button)
- **Mouse Button 5** (side button)
- **Double Middle Click** (default)

Use your chosen method to toggle auto-scroll on/off, or click any other mouse button to exit.

**With Trackpad:**
- Hold Option key and perform a two-finger scroll to activate auto-scroll
- Click anywhere to exit auto-scroll mode

### Controlling Scrolling

Once auto-scroll is activated:
- Move cursor **up** to scroll **up**
- Move cursor **down** to scroll **down**
- Move further from the center point for faster scrolling
- Move closer to the center point for slower, more precise scrolling

### Customization

**Scroll Speed:**
- Use the sensitivity slider in the menu (0.2x - 3.0x)
- Speeds below 1.0x use exponential scaling for fine control
- Real-time adjustment with immediate feedback

**Activation Method:**
- Choose from 7 different mouse/key combinations
- Avoid conflicts with browser middle-click link opening
- Supports modifier keys (Shift, Cmd, Option) and side buttons

### Menu Options

Access additional options from the menu bar icon:
- **Start/Stop Auto-Scroll** - Manual toggle
- **Scroll Speed** - Sensitivity slider (0.2x - 3.0x)
- **Activation Method** - Choose your preferred mouse/key combination
- **Invert Scrolling Direction** - Reverse up/down behavior
- **Launch at Login** - Automatic startup option
- **About Scrollapp** - App information and usage tips

## System Requirements

- Deployment target: macOS 13.0 or later
- Mouse with middle button, side buttons, or trackpad support
- 2.5.0 includes Apple Silicon (arm64) and Intel (x86_64) binaries

Global cursor skins use private macOS interfaces and have been verified on
macOS 26.6.2 / Apple M2 Pro. The x86_64 path has passed Rosetta tests.
Intel hardware and macOS 13/14/15 have not been tested. A deployment target
and a Universal binary do not certify those environments. App-drawn cursors
may not follow global cursor replacements.

2.5.0 is a preview distribution: it has no Developer ID signature or Apple
notarization, and Gatekeeper assessment rejects the ad-hoc signature.
See the attached validation report for tested and pending scenarios.

## Privacy & Security

- **Permissions**: Accessibility and Input Monitoring support global scrolling and shortcuts. Region capture needs Screen Recording; local image import does not.
- **Images and APIs**: Image analysis sends a resized reference image and instructions only to the API you select. Provider fees and data handling apply. Local Ollama can keep analysis on your Mac. API keys use macOS Keychain; history and reference copies stay in local application storage.
- **Code Signing**: The app is ad-hoc signed for free distribution. While this triggers macOS security warnings, the source code is fully open and auditable on GitHub.

## License

[GNU General Public License v3.0](LICENSE)

## Building from Source

Clone `https://github.com/Seven-hub-fanfan/scrollapp-leftclick` and check out
`v2.5.0` for the release source. Install Xcode Command Line Tools. From the source root:

```bash
bash scripts/build_app.sh
bash scripts/create_dmg_from_app.sh
```

The scripts produce `build/Scrollapp.app` and a versioned DMG. No Xcode project
or third-party runtime dependencies are required. See [build scripts](scripts/README.md)
and [cursor theme resources](Scrollapp/Skins/README.md) for details.

## Feedback and Contributions

Feedback and contributions are welcome! Please feel free to submit issues or pull requests.
