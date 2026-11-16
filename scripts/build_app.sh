#!/bin/bash
#
# Build Scrollapp.app from source with swiftc (no Xcode project required).
# Includes localization resources (en / zh-Hans).
#
# Usage: ./scripts/build_app.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

SDK_PATH="$(xcrun --show-sdk-path)"
OUTPUT_APP="${SCROLLAPP_OUTPUT_DIR:-build/Scrollapp.app}"
BUNDLE_ID="${SCROLLAPP_BUNDLE_ID:-com.scrollapp.app}"
SRC="Scrollapp"
VERSION="2.5.0"
BUILD="58"
MIN_OS="13.0"
ARCHS="${SCROLLAPP_ARCHS:-arm64 x86_64}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp/}scrollapp-build.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
APP_DIR="$WORK_DIR/Scrollapp.app"

echo "==> Building $VERSION ($ARCHS, macOS $MIN_OS+)"
mkdir -p "$APP_DIR/Contents/MacOS" \
         "$APP_DIR/Contents/Resources/en.lproj" \
         "$APP_DIR/Contents/Resources/zh-Hans.lproj"

echo "==> Compiling Swift sources"
echo "==> Compiling native cursor service"
for ARCH in $ARCHS; do
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; esac
RASTER_OBJECT="$WORK_DIR/CursorRaster-$ARCH.o"
xcrun clang -isysroot "$SDK_PATH" -arch "$ARCH" -mmacosx-version-min="$MIN_OS" \
  -O2 -fobjc-arc -framework Cocoa -framework ApplicationServices -framework ImageIO \
  "$SRC/CursorService.m" "$SRC/CursorRaster.m" -o "$WORK_DIR/CursorService-$ARCH"
xcrun clang -isysroot "$SDK_PATH" -arch "$ARCH" -mmacosx-version-min="$MIN_OS" \
  -O2 -fobjc-arc -c "$SRC/CursorRaster.m" -o "$RASTER_OBJECT"
xcrun swiftc -sdk "$SDK_PATH" -target "$ARCH-apple-macos$MIN_OS" \
  -O \
  -import-objc-header "$SRC/CursorRaster.h" "$RASTER_OBJECT" \
  -F "$SDK_PATH/System/Library/Frameworks" \
  -framework SwiftUI -framework AppKit -framework Cocoa \
  -framework UserNotifications -framework ServiceManagement -framework ApplicationServices -framework Security -framework ImageIO \
  -o "$WORK_DIR/Scrollapp-$ARCH" \
  "$SRC/ScrollappApp.swift" "$SRC/Appearance.swift" "$SRC/VerticalChannelSlider.swift" "$SRC/ContentView.swift" "$SRC/Localization.swift" "$SRC/StyledDialog.swift" \
  "$SRC/CursorThemes.swift" "$SRC/CursorSkinStore.swift" "$SRC/SkinSettingsView.swift" \
  "$SRC/CursorProtocol.swift" "$SRC/PermissionSettings.swift" "$SRC/ScrollDynamics.swift" "$SRC/SkinAssets.swift" \
  "$SRC/FeaturedSkins.swift" "$SRC/LocalSkinImport.swift" "$SRC/CursorArchive.swift" "$SRC/SupplementedCursors.swift" \
  "$SRC/ShortcutSequence.swift" "$SRC/ShortcutEngine.swift" "$SRC/ShortcutSettingsView.swift" "$SRC/ShortcutInputShield.swift" \
  "$SRC/PromptVision.swift" "$SRC/PromptStudioStore.swift" "$SRC/PromptStudioView.swift"
done
xcrun lipo -create "$WORK_DIR"/CursorService-* -output "$APP_DIR/Contents/MacOS/CursorService"
xcrun lipo -create "$WORK_DIR"/Scrollapp-* -output "$APP_DIR/Contents/MacOS/Scrollapp"

echo "==> Writing Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key><string>Scrollapp</string>
	<key>CFBundleExecutable</key><string>Scrollapp</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
	<key>CFBundleName</key><string>Scrollapp</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>${BUILD}</string>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>zh-Hans</string>
	</array>
	<key>LSMinimumSystemVersion</key><string>${MIN_OS}</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSAccessibilityUsageDescription</key>
	<string>This app needs accessibility permissions to enable auto-scrolling with the mouse.</string>
	<key>NSScreenCaptureUsageDescription</key>
	<string>Select a reference image on screen to generate an image prompt.</string>
</dict>
</plist>
PLIST

echo "==> Installing localization resources"
cp "$SRC/en.lproj/InfoPlist.strings" "$APP_DIR/Contents/Resources/en.lproj/"
cp "$SRC/zh-Hans.lproj/InfoPlist.strings" "$APP_DIR/Contents/Resources/zh-Hans.lproj/"
mkdir -p "$APP_DIR/Contents/Resources/Skins"
# Catalog previews and the user-supplied Doubao package ship in the app.
# Other full verified packages are downloaded on demand.
cp "$SRC/Skins/"*.png "$APP_DIR/Contents/Resources/Skins/"
cp "$SRC/Skins/Doubao.plist" "$APP_DIR/Contents/Resources/Skins/"

echo "==> Embedding icon"
if [ ! -f build/AppIcon.icns ] && [ -f img/scrollappicon.png ]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
              "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
              "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
    px="${spec%%:*}"; name="${spec##*:}"
    sips -z "$px" "$px" img/scrollappicon.png --out "$ICONSET/${name}.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
  rm -rf "$ICONSET"
fi
if [ -f build/AppIcon.icns ]; then
  cp build/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
else
  echo "    (no icon source found, skipping)"
fi

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> Signing"
if [ -n "${SCROLLAPP_SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SCROLLAPP_SIGN_IDENTITY" "$APP_DIR/Contents/MacOS/CursorService"
  codesign --force --options runtime --timestamp --sign "$SCROLLAPP_SIGN_IDENTITY" "$APP_DIR"
else
  codesign --force --sign - "$APP_DIR/Contents/MacOS/CursorService"
  codesign --force --sign - "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"
case "$OUTPUT_APP" in *.app) ;; *) echo "Output must end in .app" >&2; exit 1 ;; esac
if [ -L "$OUTPUT_APP" ]; then echo "Refusing symlink output" >&2; exit 1; fi
mkdir -p "$(dirname "$OUTPUT_APP")"
rm -rf "$OUTPUT_APP"
ditto "$APP_DIR" "$OUTPUT_APP"

echo "Done: $OUTPUT_APP"
echo "Note: ad-hoc signature changes each build — re-grant Accessibility /"
echo "      Input Monitoring permissions after replacing the binary."
