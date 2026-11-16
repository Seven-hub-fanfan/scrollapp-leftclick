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
5. 点 Scrollapp 左侧盾牌图标进入「权限设置」，打开辅助功能、输入监控设置。跳过首次提示后也可从这里重新配置。
6. 在浮动提示框中按住 Scrollapp 图标行，拖到系统权限列表，再打开旁边的开关。该图标对应当前运行的应用副本。
7. 旧条目已开启但无效时，点“清除旧记录并重新授权”，确认后重新拖入并开启。部分权限更改需要退出后重新打开。

在菜单栏打开“光标皮肤”，选择豆包并点击“应用皮肤”即可使用；豆包已内置，无需下载。
其他皮肤点击“下载皮肤”，下载完成后点击“应用皮肤”。
Sweezy 的 7 款皮肤与小七、奶蛙一起展示在同一皮肤库。点“下载皮肤”后自动安装，随后点“应用皮肤”即可使用。
Sweezy 下载直接取自官网公开下载入口，校验后保存到本机；下载后可离线预览和应用，删除后可重新下载。
皮肤库前四款固定为：系统默认、奶蛙、小七、豆包。其余 7 款按官网公开添加次数降序排列，热度为 2026-11-15 的快照；收藏列表也沿用这一顺序。
7 款皮肤的文字输入、抓取、精确选择、调整大小、不可用、帮助与放大/缩小状态均由 Scrollapp 补绘，和原款保持同一配色与特征。
每款共 13 种静态状态，缺失状态会自动补齐。详情页可查看全部造型并悬停试用，系统等待动画保持原有行为。
小七与奶蛙首次下载需要能访问 GitHub，下载完成后可离线使用。下载的皮肤可在详情页点“删除下载”释放本地空间；豆包为内置资源，不显示删除按钮。
删除正在使用的皮肤会先恢复系统光标。旧版内置皮肤升级后需要按需重新下载。
“通用”页面可设置 0.5–8 倍鼠标大小。
勾选“红色点击热点”可标记真实点击位置，热点大小可独立调整为 3–16 pt。
滚动速度、鼠标大小和热点大小均使用竖向填充滑槽：向上拖动增大、向下拖动减小；聚焦后也可用方向键调节。
侧栏底部的外观按钮可切换深色、浅色或跟随系统，选择会自动保存。
退出 Scrollapp 时恢复原始系统光标。

如果旧版留下光标恢复错误：
打开“光标皮肤”点击“重试”，或点击“使用系统光标”恢复正常指针。
原始恢复备份会保留，不需要手动删除。
如仍有异常，点击“导出诊断”，将 JSON 报告反馈给维护者。

本安装包使用本地 ad-hoc 签名，未经过 Apple 公证。
包含 Apple Silicon 与 Intel 两种架构，最低部署目标 macOS 13。
光标引擎此前在 macOS 26.6.2 / Apple Silicon 和 Rosetta 路径验证过。
2.4.11 新增用户提供的豆包透明素材，完整内置 13 种静态状态，校准点击热点，保留 512 px 高清源图与原人物造型。
2.4.12 修复系统恢复后箭头、文字残留豆包图像的问题。原始光标基线长期保留，恢复时重新安装并核对原图像素和热点。
2.4.13 修正权限提示框的拖动事件归属，应用图标行用于拖出应用文件，窗口背景用于移动提示框。
2.4.14 固定系统默认、奶蛙、小七、豆包为皮肤库前四款，其余皮肤继续按热度排序。
2.4.15 新增「点击快捷键」页面：录入最多 10 组组合键，开启后每次左键点击目标应用依次执行一组；执行到末尾停止。
2.4.16 可选择左键或滚轮中键触发，默认中键；自动滚动默认双击中键。双击滚动优先，不执行序列；单击中键等待系统双击判定后执行。
2.4.17 新增「循环」按钮。开启后最后一组执行完自动回到第一组，每次点击仍只执行一组；关闭后保持末尾停止。
2.5.0 新增原生「图片反推」页面。左侧选择参考图、模型与侧重，右侧流式显示中文、英文、JSON 与负向提示词。
点击「API 接入」保存多套厂商配置，支持 OpenAI、Gemini、Claude、Qwen、火山引擎、智谱、OpenRouter、Ollama 及自定义接口；需使用支持识图的模型。
API Key 保存在 macOS 钥匙串，模型 ID 与 API 基础地址可编辑；火山引擎请填自己的视觉模型或方舟端点 ID。
支持本地打开、拖入、粘贴、图片直接链接与选区截图，最多同时打开 5 张，可依次分析全部图片，也可随时停止。
本地导入与 API 分析不需要辅助功能授权；选区截图需要系统的屏幕录制权限。
图片后台压缩为最长边 1600 px 的 JPEG，再发送至所选 API；单张原图上限 32 MB。接口用量与费用由所选厂商决定。
结果支持复制、搜索、收藏、历史恢复及 Markdown 导出；最多保留 100 条结果和本地参考图。
历史位于 ~/Library/Application Support/com.scrollapp.app/PromptStudio/。图片反推提炼可见特征，不能保证恢复原始提示词。
「点击快捷键」页获得焦点时隔离其他应用的全局快捷键，录制从原始键码读取；离开页面后解除隔离。此功能需辅助功能授权。
支持上移、下移、删除、回退一步和重置到开头。配置和进度自动保存，修改序列后从开头开始。
回退一步只调整下次执行位置，不会撤销目标应用中已执行的操作。点击 Scrollapp 自己的界面或拖动鼠标不会触发快捷键。
本地 ad-hoc 预览版每次重新编译会改变签名，旧版授权可能不再匹配；请先将当前版本安装到 Applications，再添加这一副本的权限。
7 款 Sweezy 皮肤的 77 个补绘状态继续保留，与本地预览和全局光标应用保持一致。
滑块居中排列，左侧刻度、弧形高亮、右侧数值与上方三个圆形仪表盘随拖动即时同步。红色点击热点开关、红色删除按钮与大点击区域保持不变。
macOS 13/14/15 与 Intel 实机尚未验证，不能视为全机型兼容承诺。
INSTALL
codesign --verify --deep --strict "$STAGING/payload/Scrollapp.app"
hdiutil create -srcfolder "$STAGING/payload" -volname "Scrollapp $VERSION" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 "$STAGING/Scrollapp.dmg"
mkdir -p "$(dirname "$OUTPUT_PATH")"
mv "$STAGING/Scrollapp.dmg" "$OUTPUT_PATH"
echo "Created $OUTPUT_PATH ($ARCH_LABEL)"
