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
        "settings.activationMethod": "Activation Method",
        "settings.invertDirection": "Invert Scrolling Direction",
        "settings.leftClickNoInterrupt": "Left Click Does Not Interrupt Scrolling",
        "settings.launchAtLogin": "Launch at Login",
        "settings.about": "About",
        "settings.quit": "Quit",

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
        "settings.activationMethod": "触发方式",
        "settings.invertDirection": "反转滚动方向",
        "settings.leftClickNoInterrupt": "左键点击不中断滚动",
        "settings.launchAtLogin": "开机自动启动",
        "settings.about": "关于",
        "settings.quit": "退出",

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
