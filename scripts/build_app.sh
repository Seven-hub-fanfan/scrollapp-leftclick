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
APP_DIR="build/Scrollapp.app"
SRC="Scrollapp"
VERSION="1.8"
BUILD="9"

echo "==> Cleaning $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" \
         "$APP_DIR/Contents/Resources/en.lproj" \
         "$APP_DIR/Contents/Resources/zh-Hans.lproj"

echo "==> Compiling Swift sources"
xcrun swiftc -sdk "$SDK_PATH" -target arm64-apple-macos15.0 \
  -O \
  -F "$SDK_PATH/System/Library/Frameworks" \
  -framework SwiftUI -framework AppKit -framework Cocoa \
  -framework UserNotifications -framework ServiceManagement -framework ApplicationServices \
  -o "$APP_DIR/Contents/MacOS/Scrollapp" \
  "$SRC/ScrollappApp.swift" "$SRC/ContentView.swift" "$SRC/Localization.swift"

echo "==> Writing Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key><string>Scrollapp</string>
	<key>CFBundleExecutable</key><string>Scrollapp</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>com.scrollapp.app</string>
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
	<key>LSMinimumSystemVersion</key><string>11.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSAccessibilityUsageDescription</key>
	<string>This app needs accessibility permissions to enable auto-scrolling with the mouse.</string>
</dict>
</plist>
PLIST

echo "==> Installing localization resources"
cp "$SRC/en.lproj/InfoPlist.strings" "$APP_DIR/Contents/Resources/en.lproj/"
cp "$SRC/zh-Hans.lproj/InfoPlist.strings" "$APP_DIR/Contents/Resources/zh-Hans.lproj/"

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

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP_DIR"

echo "Done: $APP_DIR"
echo "Note: ad-hoc signature changes each build — re-grant Accessibility /"
echo "      Input Monitoring permissions after replacing the binary."
