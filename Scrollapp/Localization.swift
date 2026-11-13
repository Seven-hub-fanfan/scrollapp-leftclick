//
//  Localization.swift
//  Scrollapp
//
//  Lightweight in-code localization. English is the default; Simplified /
//  Traditional Chinese system languages automatically get Chinese strings.
//
//  Why not .strings files: the app is compiled directly with `swiftc` (no
//  Xcode project), so keeping the table in Swift avoids fragile resource
//  copying in the build script while still being trivially extensible.
//

import Foundation

enum L10n {

    /// Supported UI languages.
    enum Language {
        case english
        case chineseSimplified
    }

    /// Resolved once at launch from the user's preferred languages.
    static let current: Language = resolveLanguage()

    private static func resolveLanguage() -> Language {
        // Allow overriding for testing / user preference:
        //   defaults write <bundleid> ScrollappLanguage -string "zh-Hans" | "en"
        if let forced = UserDefaults.standard.string(forKey: "ScrollappLanguage") {
            if forced.hasPrefix("zh") { return .chineseSimplified }
            if forced.hasPrefix("en") { return .english }
        }

        for identifier in Locale.preferredLanguages {
            let code = identifier.lowercased()
            if code.hasPrefix("zh") { return .chineseSimplified }
            // First non-Chinese preferred language wins -> keep English default.
            return .english
        }
        return .english
    }

    /// Look up a localized string. Falls back to the English text (and finally
    /// to the key itself) so a missing translation can never blank out the UI.
    static func t(_ key: String) -> String {
        switch current {
        case .english:
            return english[key] ?? key
        case .chineseSimplified:
            return chinese[key] ?? english[key] ?? key
        }
    }

    /// Localized string with `String(format:)` arguments.
    static func t(_ key: String, _ args: CVarArg...) -> String {
        return String(format: t(key), arguments: args)
    }

    // MARK: - English (default, source of truth for keys)

    private static let english: [String: String] = [
        // Menu bar
        "menu.toggle": "Start/Stop Auto-Scroll",
        "menu.scrollSpeed": "Scroll Speed: %.1fx",
        "menu.activationMethod": "Activation Method",
        "menu.invertDirection": "Invert Scrolling Direction",
        "menu.launchAtLogin": "Launch at Login",
        "menu.leftClickNoInterrupt": "Left Click Does Not Interrupt Scrolling",
        "menu.rightClickNoInterrupt": "Right Click Does Not Interrupt Scrolling",
        "menu.settings": "Settings...",
        "menu.about": "About Scrollapp",
        "menu.activationMethods": "Activation Methods",
        "menu.help.mouse": "Mouse - Configurable button/modifier (see Activation Method)",
        "menu.help.trackpad": "Option + Scroll - Start auto-scroll (trackpad)",
        "menu.help.menuBar": "Menu Bar - Use the menu option above",
        "menu.help.click": "Click - Stop auto-scroll",
        "menu.quit": "Quit",

        // Activation methods
        "activation.middleClick": "Middle Click",
        "activation.shiftMiddleClick": "Shift + Middle Click",
        "activation.cmdMiddleClick": "Cmd + Middle Click",
        "activation.optionMiddleClick": "Option + Middle Click",
        "activation.button4": "Mouse Button 4",
        "activation.button5": "Mouse Button 5",
        "activation.doubleMiddleClick": "Double Middle Click",

        // HUD / notification
        "hud.active": "Auto-Scroll Active",
        "notification.body": "Move cursor to control scrolling. Click anywhere to exit.",

        // Settings window
        "settings.windowTitle": "Scrollapp",
        "settings.appName": "Scrollapp",
        "settings.scrollSpeed": "Scroll Speed",
        "settings.cursorSize": "Cursor Size",
        "settings.activationMethod": "Activation Method",
        "settings.invertDirection": "Invert Scrolling Direction",
        "settings.leftClickNoInterrupt": "Left Click Does Not Interrupt Scrolling",
        "settings.rightClickNoInterrupt": "Right Click Does Not Interrupt Scrolling",
        "settings.launchAtLogin": "Launch at Login",
        "settings.about": "About",
        "settings.quit": "Quit",
        "settings.general": "General",
        "settings.skins": "Cursor Skins",
        "skins.intro": "A little personality, wherever your cursor goes.",
        "skins.system.name": "System Default",
        "skins.system.description": "The familiar macOS cursors",
        "skins.frog.name": "Nai Wa",
        "skins.frog.description": "A small frog, a softer workday",
        "skins.xiaoqi.name": "Xiao Qi",
        "skins.xiaoqi.description": "Curly-haired Xiao Qi and his yellow pal",
        "skins.ink.name": "Graphite",
        "skins.ink.description": "Clean silhouettes with a bright outline",
        "skins.mint.name": "Mint Pixels",
        "skins.mint.description": "Crisp pixels, fresh mint",
        "skins.filter.all": "All",
        "skins.filter.minimal": "Minimal",
        "skins.filter.colorful": "Colorful",
        "skins.filter.favorites": "Favorites",
        "skins.count": "%d skins",
        "skins.native": "macOS",
        "skins.selected": "Selected",
        "skins.favorite": "Favorite %@",
        "skins.unfavorite": "Unfavorite %@",
        "skins.emptyFavorites": "Tap a heart to keep your favorites here.",
        "skins.preview": "Try every state",
        "skins.hoverHint": "Hover to try locally. Apply to use across apps.",
        "skins.applying": "Updating cursors…",
        "skins.current": "Active: %@",
        "skins.scope": "Across apps · Restored when Scrollapp quits",
        "skins.reset": "Reset",
        "skins.retry": "Retry",
        "skins.applied": "Applied",
        "skins.apply": "Apply Skin",
        "skins.role.arrow": "Pointer",
        "skins.role.text": "Text",
        "skins.role.link": "Link",
        "skins.role.grab": "Grab",
        "skins.role.crosshair": "Crosshair",
        "skins.role.horizontal": "Resize",
        "skins.role.vertical": "Vertical",
        "skins.role.diagonalRight": "Diagonal",
        "skins.role.diagonalLeft": "Diagonal",
        "skins.role.unavailable": "Blocked",
        "skins.role.help": "Help",
        "skins.role.zoomIn": "Zoom In",
        "skins.role.zoomOut": "Zoom Out",
        "skins.error.unsupportedSystem": "Cursor skins are unavailable on this macOS version.",
        "skins.error.anotherInstance": "Another Scrollapp instance is managing cursor skins. Quit it, then retry.",
        "skins.error.guardUnavailable": "Cursor recovery could not start. Please retry.",
        "skins.error.invalidBackup": "The saved cursor backup could not be read. Your backup has been retained.",
        "skins.error.restoreFailed": "Some cursors could not be restored. The recovery backup has been retained; please retry.",
        "skins.error.backupUnsupported": "The current cursor configuration cannot be safely restored, so this skin was not applied.",
        "skins.error.backupFailed": "The cursor backup could not be saved. Please check available disk space.",
        "skins.error.applyFailed": "The skin could not be applied. The previous cursors have been restored.",
        "skins.error.serviceUnavailable": "The cursor service stopped. Retry to recover your cursors and reconnect.",
        "skins.error.invalidPayload": "The skin resource is incomplete or invalid.",
        "skins.error.invalidMetadata": "The skin has an invalid size, hotspot, or frame description.",
        "skins.error.invalidImages": "The skin images are invalid.",
        "skins.error.invalidName": "The skin contains an unsupported cursor identifier.",
        "skins.error.reservedCursor": "The skin attempts to replace a reserved system cursor.",
        "skins.error.mappingChanged": "The skin requires a different cursor mapping. Reset before applying.",

        // Alerts
        "alert.ok": "OK",
        "about.title": "About Scrollapp",
        "about.bodyMenu": """
Scrollapp enables auto-scrolling on macOS.

How to activate:
• Mouse: Configurable button/modifier (see Activation Method in menu)
• Trackpad: Hold Option key and scroll with two fingers
• Menu: Use the menu bar icon and select 'Start/Stop Auto-Scroll'

How to stop:
• Click anywhere to exit auto-scroll mode
• Use your configured activation method again

While active, move your cursor to control scroll speed and direction.

Adjust scroll speed using the slider in the menu bar (0.2x - 3.0x).
Speeds below 1.0x are exponentially slower for fine control.

Configure your preferred activation method in the 'Activation Method' submenu to avoid conflicts with browser link opening.
""",
        "about.bodySettings": """
Windows-style auto-scrolling for macOS.

Activate with your configured mouse button, then move the cursor to control scrolling speed and direction.

Right-click or middle-click to exit.
""",
        "permission.title": "Accessibility Permissions Required",
        "permission.body": """
Scrollapp needs Accessibility permissions to enable auto-scrolling.

Please:
1. Click 'Open System Preferences'
2. Unlock the settings if needed
3. Check the box next to Scrollapp
4. Restart the app
""",
        "permission.open": "Open System Preferences",
        "permission.skip": "Skip",
    ]

    // MARK: - Simplified Chinese

    private static let chinese: [String: String] = [
        // 菜单栏
        "menu.toggle": "开始 / 停止自动滚动",
        "menu.scrollSpeed": "滚动速度：%.1f 倍",
        "menu.activationMethod": "触发方式",
        "menu.invertDirection": "反转滚动方向",
        "menu.launchAtLogin": "开机自动启动",
        "menu.leftClickNoInterrupt": "左键点击不中断滚动",
        "menu.rightClickNoInterrupt": "右键点击不中断滚动",
        "menu.settings": "偏好设置…",
        "menu.about": "关于 Scrollapp",
        "menu.activationMethods": "触发方式说明",
        "menu.help.mouse": "鼠标 — 可自定义按键 / 组合键（见「触发方式」）",
        "menu.help.trackpad": "Option + 滚动 — 启动自动滚动（触控板）",
        "menu.help.menuBar": "菜单栏 — 使用上方的菜单项",
        "menu.help.click": "点击 — 停止自动滚动",
        "menu.quit": "退出",

        // 触发方式
        "activation.middleClick": "中键点击",
        "activation.shiftMiddleClick": "Shift + 中键点击",
        "activation.cmdMiddleClick": "Cmd + 中键点击",
        "activation.optionMiddleClick": "Option + 中键点击",
        "activation.button4": "鼠标第 4 键",
        "activation.button5": "鼠标第 5 键",
        "activation.doubleMiddleClick": "双击中键",

        // HUD / 通知
        "hud.active": "自动滚动已启动",
        "notification.body": "移动光标控制滚动，点击任意位置退出。",

        // 设置窗口
        "settings.scrollSpeed": "滚动速度",
        "settings.cursorSize": "鼠标大小",
        "settings.activationMethod": "触发方式",
        "settings.invertDirection": "反转滚动方向",
        "settings.leftClickNoInterrupt": "左键点击不中断滚动",
        "settings.rightClickNoInterrupt": "右键点击不中断滚动",
        "settings.launchAtLogin": "开机自动启动",
        "settings.about": "关于",
        "settings.quit": "退出",
        "settings.general": "通用",
        "settings.skins": "光标皮肤",
        "skins.intro": "让每一次指向，都多一点自己的风格。",
        "skins.system.name": "系统默认",
        "skins.system.description": "熟悉的 macOS 原生光标",
        "skins.frog.name": "奶蛙",
        "skins.frog.description": "小小奶蛙，陪你轻松工作",
        "skins.xiaoqi.name": "小七",
        "skins.xiaoqi.description": "卷发小七和他的黄色搭档",
        "skins.ink.name": "墨黑",
        "skins.ink.description": "利落轮廓，黑白之间",
        "skins.mint.name": "薄荷像素",
        "skins.mint.description": "像素颗粒，一点清新",
        "skins.filter.all": "全部",
        "skins.filter.minimal": "简洁",
        "skins.filter.colorful": "多彩",
        "skins.filter.favorites": "收藏",
        "skins.count": "%d 款皮肤",
        "skins.native": "macOS",
        "skins.selected": "已选中",
        "skins.favorite": "收藏%@",
        "skins.unfavorite": "取消收藏%@",
        "skins.emptyFavorites": "点击皮肤上的爱心，把喜欢的留在这里。",
        "skins.preview": "试试不同光标状态",
        "skins.hoverHint": "悬停可在这里体验；应用后，在其他应用中也能使用。",
        "skins.applying": "正在更新光标…",
        "skins.current": "当前使用：%@",
        "skins.scope": "跨应用生效 · 退出 Scrollapp 时自动恢复",
        "skins.reset": "恢复默认",
        "skins.retry": "重试",
        "skins.applied": "已应用",
        "skins.apply": "应用皮肤",
        "skins.role.arrow": "指针",
        "skins.role.text": "文本",
        "skins.role.link": "链接",
        "skins.role.grab": "抓取",
        "skins.role.crosshair": "十字",
        "skins.role.horizontal": "缩放",
        "skins.role.vertical": "纵向",
        "skins.role.diagonalRight": "斜向",
        "skins.role.diagonalLeft": "斜向",
        "skins.role.unavailable": "禁用",
        "skins.role.help": "帮助",
        "skins.role.zoomIn": "放大",
        "skins.role.zoomOut": "缩小",
        "skins.error.unsupportedSystem": "当前 macOS 版本暂不支持全局光标皮肤。",
        "skins.error.anotherInstance": "另一个 Scrollapp 正在管理光标皮肤，请退出它后重试。",
        "skins.error.guardUnavailable": "光标恢复保护未能启动，请重试。",
        "skins.error.invalidBackup": "无法读取原始光标备份，备份文件已保留。",
        "skins.error.restoreFailed": "部分光标未能恢复，原始备份已保留，请重试。",
        "skins.error.backupUnsupported": "当前光标配置无法保证完整恢复，因此没有应用皮肤。",
        "skins.error.backupFailed": "无法保存原始光标备份，请检查磁盘空间。",
        "skins.error.applyFailed": "皮肤应用失败，已恢复之前的光标。",
        "skins.error.serviceUnavailable": "光标服务已停止，点击重试以恢复光标并重新连接。",
        "skins.error.invalidPayload": "皮肤资源不完整或格式有误。",
        "skins.error.invalidMetadata": "皮肤尺寸、点击热点或帧信息有误。",
        "skins.error.invalidImages": "皮肤图片格式有误。",
        "skins.error.invalidName": "皮肤包含不支持的光标标识。",
        "skins.error.reservedCursor": "皮肤不能替换保留的系统光标。",
        "skins.error.mappingChanged": "这套皮肤使用不同的光标映射，请先恢复默认。",

        // 弹窗
        "alert.ok": "好",
        "about.title": "关于 Scrollapp",
        "about.bodyMenu": """
Scrollapp 为 macOS 提供自动滚动功能。

如何启动：
• 鼠标：可自定义按键 / 组合键（见菜单中的「触发方式」）
• 触控板：按住 Option 键并用两指滚动
• 菜单：点击菜单栏图标，选择「开始 / 停止自动滚动」

如何停止：
• 点击任意位置退出自动滚动
• 再次使用你设置的触发方式

启动后，移动光标即可控制滚动速度与方向。

可在菜单栏的滑块中调整滚动速度（0.2 倍 – 3.0 倍）。
低于 1.0 倍时速度呈指数级放缓，便于精细控制。

如与浏览器「中键打开链接」冲突，可在「触发方式」子菜单中改用其他触发方式。
""",
        "about.bodySettings": """
为 macOS 带来 Windows 风格的自动滚动。

用你设置的鼠标按键启动，然后移动光标控制滚动速度与方向。

右键或中键点击即可退出。
""",
        "permission.title": "需要「辅助功能」权限",
        "permission.body": """
Scrollapp 需要「辅助功能」权限才能实现自动滚动。

请按以下步骤操作：
1. 点击「打开系统设置」
2. 如有需要，先解锁设置
3. 勾选 Scrollapp
4. 重新启动本应用
""",
        "permission.open": "打开系统设置",
        "permission.skip": "跳过",
    ]
}
