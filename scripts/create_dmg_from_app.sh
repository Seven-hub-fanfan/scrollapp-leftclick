#!/bin/bash
# Package an existing signed app without changing its identity or signature.
# Usage: bash scripts/create_dmg_from_app.sh [APP_PATH] [OUTPUT_PATH]
set -euo pipefail

PROJECT_ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
APP_PATH="${1:-$PROJECT_ROOT/build/Scrollapp.app}"
if [ ! -f "$APP_PATH/Contents/MacOS/Scrollapp" ]; then
    echo "ERROR: Build Scrollapp.app first with scripts/build_app.sh." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ARCHITECTURES="$(lipo -archs "$APP_PATH/Contents/MacOS/Scrollapp")"
case "$ARCHITECTURES" in
    arm64|x86_64) ARCH_LABEL="$ARCHITECTURES" ;;
    "arm64 x86_64"|"x86_64 arm64") ARCH_LABEL="universal" ;;
    *) echo "ERROR: Unsupported app architecture: $ARCHITECTURES" >&2; exit 1 ;;
esac
OUTPUT_PATH="${2:-$PROJECT_ROOT/build/Scrollapp-$VERSION-$ARCH_LABEL.dmg}"
if [ -e "$OUTPUT_PATH" ]; then
    echo "ERROR: Output already exists: $OUTPUT_PATH" >&2
    exit 1
fi
codesign --verify --deep --strict "$APP_PATH"

STAGING="$(mktemp -d "${TMPDIR:-/tmp/}scrollapp-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir "$STAGING/payload"
ditto "$APP_PATH" "$STAGING/payload/Scrollapp.app"
ln -s /Applications "$STAGING/payload/Applications"
cat > "$STAGING/payload/安装说明.txt" <<'INSTALL'
Scrollapp 安装说明

1. 退出正在运行的旧版 Scrollapp。
2. 将 Scrollapp.app 拖到 Applications（应用程序）。
3. 打开应用程序中的 Scrollapp。
4. 如 macOS 阻止打开，在“系统设置 → 隐私与安全性”中选择“仍要打开”。
5. 按提示授予辅助功能、输入监控权限，然后重新打开 Scrollapp。

在菜单栏打开“光标皮肤”，选择皮肤并点击“应用皮肤”。
“通用”页面可设置 0.5–8 倍鼠标大小。
退出 Scrollapp 时恢复原始系统光标。

本安装包使用本地 ad-hoc 签名，未经过 Apple 公证。
INSTALL
codesign --verify --deep --strict "$STAGING/payload/Scrollapp.app"
hdiutil create -srcfolder "$STAGING/payload" -volname "Scrollapp $VERSION" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 "$STAGING/Scrollapp.dmg"
mkdir -p "$(dirname "$OUTPUT_PATH")"
mv "$STAGING/Scrollapp.dmg" "$OUTPUT_PATH"
echo "Created $OUTPUT_PATH ($ARCH_LABEL)"
