//
//  ScrollappApp.swift
//  Scrollapp
//

import SwiftUI
import Cocoa
import UserNotifications
import ServiceManagement
import ApplicationServices

@main
struct ScrollappApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView() // No window needed
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var isAutoScrolling = false
    var scrollTimer: Timer?
    var originalPoint: CGPoint?
    var globalMonitor: Any?
    var localMonitor: Any?
    var mouseMoveMonitor: Any?
    var optionKeyMonitor: Any?
    var scrollMonitor: Any?
    var clickMonitor: Any?
    var localClickMonitor: Any?
    private var scrollIntegrator = ScrollIntegrator()
    private var doubleClickActivation = DoubleClickActivation()
    private static let syntheticScrollTag: Int64 = 0x5343524F4C4C
    private var sessionObservers: [NSObjectProtocol] = []
    var scrollCursor: NSCursor?
    var isTrackpadMode = false
    var lastScrollTime: Date?
    var scrollDetectionWindow = [CGFloat]()
    var isDirectionInverted = false  // Default is now "up scrolls up"
    var launchAtLogin = false        // Track launch at login state
    var scrollSensitivity: Double = 1.0  // Default sensitivity multiplier
    var activationMethod: ActivationMethod = .doubleMiddleClick
    var leftClickDoesNotInterrupt = false  // Allow left-click without exiting auto-scroll
    var rightClickDoesNotInterrupt = false // Allow right-click without exiting auto-scroll
    /// Tracks whether *we* hid the cursor. NSCursor.hide()/unhide() are a counted
    /// pair scoped to the active app, so an unbalanced hide leaks and makes the
    /// cursor vanish later (e.g. the moment the settings window activates the app).
    private var didHideCursor = false
    // Tags used to locate dynamic menu items without relying on (localized) titles.
    static let sensitivityMenuItemTag = 900
    static let activationMenuItemTag = 901
    static let shortcutProgressMenuTag = 902
    static let shortcutLoopMenuTag = 903

    var settingsWindow: NSWindow?
    var hudWindow: NSWindow?

    enum ActivationMethod: String, CaseIterable {
        case middleClick = "Middle Click"
        case shiftMiddleClick = "Shift + Middle Click"
        case cmdMiddleClick = "Cmd + Middle Click"
        case optionMiddleClick = "Option + Middle Click"
        case button4 = "Mouse Button 4"
        case button5 = "Mouse Button 5"
        case doubleMiddleClick = "Double Middle Click"
        
        /// Localized label for menus / pickers. `rawValue` stays English and is
        /// the persisted value in UserDefaults — never localize it.
        var displayName: String {
            switch self {
            case .middleClick: return L10n.t("activation.middleClick")
            case .shiftMiddleClick: return L10n.t("activation.shiftMiddleClick")
            case .cmdMiddleClick: return L10n.t("activation.cmdMiddleClick")
            case .optionMiddleClick: return L10n.t("activation.optionMiddleClick")
            case .button4: return L10n.t("activation.button4")
            case .button5: return L10n.t("activation.button5")
            case .doubleMiddleClick: return L10n.t("activation.doubleMiddleClick")
            }
        }

        var buttonNumber: Int? {
            switch self {
            case .middleClick, .shiftMiddleClick, .cmdMiddleClick, .optionMiddleClick, .doubleMiddleClick:
                return 2
            case .button4:
                return 3
            case .button5:
                return 4
            }
        }
        
        var requiresModifier: Bool {
            switch self {
            case .shiftMiddleClick, .cmdMiddleClick, .optionMiddleClick:
                return true
            default:
                return false
            }
        }
        
        var modifierFlags: NSEvent.ModifierFlags? {
            switch self {
            case .shiftMiddleClick:
                return .shift
            case .cmdMiddleClick:
                return .command
            case .optionMiddleClick:
                return .option
            default:
                return nil
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Safety: always unhide cursor on launch in case of unclean exit
        NSCursor.setHiddenUntilMouseMoves(false)

        // Load user preferences
        isDirectionInverted = UserDefaults.standard.bool(forKey: "invertScrollDirection")
        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        scrollSensitivity = UserDefaults.standard.double(forKey: "scrollSensitivity")
        if !scrollSensitivity.isFinite || !(0.2...3).contains(scrollSensitivity) {
            scrollSensitivity = 1
            UserDefaults.standard.set(1.0, forKey: "scrollSensitivity")
        }
        
        leftClickDoesNotInterrupt = UserDefaults.standard.bool(forKey: "leftClickDoesNotInterrupt")
        rightClickDoesNotInterrupt = UserDefaults.standard.bool(forKey: "rightClickDoesNotInterrupt")

        // Load activation method
        if let savedMethod = UserDefaults.standard.string(forKey: "activationMethod"),
           let method = ActivationMethod(rawValue: savedMethod) {
            activationMethod = method
        }
        
        // Set initial launch at login state based on saved preference
        let isSkinPreview = CommandLine.arguments.contains("--skin-preview") || CommandLine.arguments.contains("--prompt-preview")
        if !isSkinPreview { updateLoginItemState() }
        
        // Check and request Accessibility permissions
        PermissionStore.shared.start()
        
        setupMenuBar()
        createScrollCursor()
        if !CommandLine.arguments.contains("--prompt-preview") { CursorSkinStore.shared.start() }
        NotificationCenter.default.addObserver(self, selector: #selector(cursorSkinDidChange),
            name: NSNotification.Name("ScrollappCursorSkinChanged"), object: nil)
        if !isSkinPreview {
            ShortcutEngine.shared.middleDoubleClickInterval = { [weak self] in
                self?.activationMethod == .doubleMiddleClick ? NSEvent.doubleClickInterval : 0
            }
            ShortcutEngine.shared.middleClickAllowed = { [weak self] in
                guard let self else { return false }
                return !self.isAutoScrolling && self.activationMethod != .middleClick
            }
            setupMiddleClickListeners()
            setupTrackpadActivation()
            ShortcutEngine.shared.start()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutSequenceChanged),
            name: .init("ScrollappShortcutSequenceChanged"), object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(permissionsChanged),
            name: .init("ScrollappPermissionsChanged"), object: nil)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            sessionObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name,
                object: nil, queue: .main) { [weak self] _ in self?.stopAutoScroll() })
        }
        if !isSkinPreview && !UserDefaults.standard.bool(forKey: "hasSeenPermissionIntro") {
            UserDefaults.standard.set(true, forKey: "hasSeenPermissionIntro")
            checkAccessibilityPermissions()
        }

        // Listen for changes from the settings window
        for name in ["ScrollappSensitivityChanged", "ScrollappInvertChanged", "ScrollappLeftClickChanged", "ScrollappRightClickChanged", "ScrollappLaunchChanged", "ScrollappActivationChanged"] {
            NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange), name: NSNotification.Name(name), object: nil)
        }
        if CommandLine.arguments.contains("--show-prompt") {
            showPromptStudio()
        } else if CommandLine.arguments.contains("--show-shortcuts") {
            showShortcutSettings()
        } else if CommandLine.arguments.contains("--show-skins") {
            CursorSkinStore.shared.section = "skins"
            showSettingsWindow()
        } else if CommandLine.arguments.contains("--show-settings") {
            showSettingsWindow()
        } else if CommandLine.arguments.contains("--show-permissions") {
            showPermissionSettings()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopAutoScroll()
        ShortcutEngine.shared.stop()
        CursorSkinStore.shared.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopAutoScroll()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.up.and.down.circle", accessibilityDescription: "Scrollapp")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.t("menu.toggle"), action: #selector(toggleTrackpadMode), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Add sensitivity slider
        let sensitivityItem = NSMenuItem(title: L10n.t("menu.scrollSpeed", scrollSensitivity), action: nil, keyEquivalent: "")
        sensitivityItem.tag = Self.sensitivityMenuItemTag
        let sensitivityView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 30))
        
        let slider = NSSlider(frame: NSRect(x: 20, y: 5, width: 150, height: 20))
        slider.minValue = 0.2
        slider.maxValue = 3.0
        slider.doubleValue = scrollSensitivity
        slider.target = self
        slider.action = #selector(sensitivityChanged(_:))
        slider.isContinuous = true
        
        let label = NSTextField(labelWithString: String(format: "%.1fx", scrollSensitivity))
        label.frame = NSRect(x: 180, y: 5, width: 50, height: 20)
        label.alignment = .center
        label.tag = 100 // Tag to find it later
        
        sensitivityView.addSubview(slider)
        sensitivityView.addSubview(label)
        sensitivityItem.view = sensitivityView
        menu.addItem(sensitivityItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add activation method submenu
        let activationMenu = NSMenu()
        let activationItem = NSMenuItem(title: L10n.t("menu.activationMethod"), action: nil, keyEquivalent: "")
        activationItem.tag = Self.activationMenuItemTag
        activationItem.submenu = activationMenu
        
        for method in ActivationMethod.allCases {
            let methodItem = NSMenuItem(title: method.displayName, action: #selector(selectActivationMethod(_:)), keyEquivalent: "")
            methodItem.representedObject = method
            methodItem.state = (method == activationMethod) ? .on : .off
            activationMenu.addItem(methodItem)
        }
        
        menu.addItem(activationItem)
        
        // Add inverted direction toggle option - reworded to match new default
        let invertItem = NSMenuItem(title: L10n.t("menu.invertDirection"), action: #selector(toggleDirectionInversion), keyEquivalent: "")
        invertItem.state = isDirectionInverted ? .on : .off
        menu.addItem(invertItem)
        
        // Add launch at login toggle
        let launchItem = NSMenuItem(title: L10n.t("menu.launchAtLogin"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        // Add left-click does not interrupt toggle
        let leftClickItem = NSMenuItem(title: L10n.t("menu.leftClickNoInterrupt"), action: #selector(toggleLeftClickInterrupt), keyEquivalent: "")
        leftClickItem.state = leftClickDoesNotInterrupt ? .on : .off
        menu.addItem(leftClickItem)

        // Add right-click does not interrupt toggle
        let rightClickItem = NSMenuItem(title: L10n.t("menu.rightClickNoInterrupt"), action: #selector(toggleRightClickInterrupt), keyEquivalent: "")
        rightClickItem.state = rightClickDoesNotInterrupt ? .on : .off
        menu.addItem(rightClickItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.t("menu.settings"), action: #selector(showSettingsWindow), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L10n.t("settings.skins"), action: #selector(showSkinSettings), keyEquivalent: ""))
        let shortcutItem = NSMenuItem(title: L10n.t("settings.shortcuts"),
            action: #selector(showShortcutSettings), keyEquivalent: "")
        shortcutItem.tag = Self.shortcutProgressMenuTag
        let shortcutMenu = NSMenu()
        shortcutMenu.addItem(NSMenuItem(title: L10n.t("shortcuts.open"),
            action: #selector(showShortcutSettings), keyEquivalent: ""))
        let loopItem = NSMenuItem(title: L10n.t("shortcuts.loop"),
            action: #selector(shortcutLoop), keyEquivalent: "")
        loopItem.tag = Self.shortcutLoopMenuTag
        shortcutMenu.addItem(loopItem)
        shortcutMenu.addItem(NSMenuItem(title: L10n.t("shortcuts.back"),
            action: #selector(shortcutBack), keyEquivalent: ""))
        shortcutMenu.addItem(NSMenuItem(title: L10n.t("shortcuts.reset"),
            action: #selector(shortcutReset), keyEquivalent: ""))
        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)
        menu.addItem(NSMenuItem(title: L10n.t("settings.prompt"), action: #selector(showPromptStudio), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.t("prompt.pasteMenu"), action: #selector(promptFromClipboard), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.t("settings.permissions"), action: #selector(showPermissionSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.t("menu.about"), action: #selector(showAbout), keyEquivalent: ""))
        
        let methodsMenu = NSMenu()
        let methodsItem = NSMenuItem(title: L10n.t("menu.activationMethods"), action: nil, keyEquivalent: "")
        methodsItem.submenu = methodsMenu
        
        methodsMenu.addItem(NSMenuItem(title: L10n.t("menu.help.mouse"), action: nil, keyEquivalent: ""))
        methodsMenu.addItem(NSMenuItem(title: L10n.t("menu.help.trackpad"), action: nil, keyEquivalent: ""))
        methodsMenu.addItem(NSMenuItem(title: L10n.t("menu.help.menuBar"), action: nil, keyEquivalent: ""))
        methodsMenu.addItem(NSMenuItem(title: L10n.t("menu.help.click"), action: nil, keyEquivalent: ""))
        
        menu.addItem(methodsItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.t("menu.quit"), action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        shortcutSequenceChanged()
    }

    func createScrollCursor() {
        if CursorSkinStore.shared.hasCustomCursor {
            scrollCursor = nil
            return
        }
        let size = CGSize(width: 20, height: 20)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()

        NSColor.systemBlue.withAlphaComponent(0.6).setFill()
        NSBezierPath(ovalIn: NSRect(x: 4, y: 4, width: 12, height: 12)).fill()

        NSColor.white.setStroke()
        let upArrow = NSBezierPath()
        upArrow.move(to: NSPoint(x: 10, y: 2))
        upArrow.line(to: NSPoint(x: 10, y: 0))
        upArrow.line(to: NSPoint(x: 8, y: 2))
        upArrow.move(to: NSPoint(x: 10, y: 0))
        upArrow.line(to: NSPoint(x: 12, y: 2))
        upArrow.lineWidth = 1
        upArrow.stroke()

        let downArrow = NSBezierPath()
        downArrow.move(to: NSPoint(x: 10, y: 18))
        downArrow.line(to: NSPoint(x: 10, y: 20))
        downArrow.line(to: NSPoint(x: 8, y: 18))
        downArrow.move(to: NSPoint(x: 10, y: 20))
        downArrow.line(to: NSPoint(x: 12, y: 18))
        downArrow.lineWidth = 1
        downArrow.stroke()
        image.unlockFocus()

        scrollCursor = NSCursor(image: image, hotSpot: NSPoint(x: 10, y: 10))
    }

    // MARK: - Cursor handling

    /// The custom scroll cursor hides the pointer, which is unacceptable when the
    /// user still needs to aim and click during auto-scroll. So whenever a
    /// "click does not interrupt" option is on, keep the normal arrow visible.
    var shouldUseScrollCursor: Bool {
        return !leftClickDoesNotInterrupt && !rightClickDoesNotInterrupt
    }

    /// Apply the custom cursor (idempotent, safe to call from the scroll timer).
    func applyScrollCursor() {
        // A global theme supplies the arrow. Keep it visible during scrolling;
        // resetting a custom cursor every 10 ms would overwrite text/link states.
        if CursorSkinStore.shared.hasCustomCursor {
            if didHideCursor { NSCursor.unhide(); didHideCursor = false }
            return
        }
        guard shouldUseScrollCursor else {
            restoreCursor()
            return
        }
        if !didHideCursor {
            NSCursor.hide()
            didHideCursor = true
        }
        scrollCursor?.set()
    }

    /// Undo everything applyScrollCursor() did. Balanced exactly once.
    func restoreCursor() {
        if didHideCursor {
            NSCursor.unhide()
            didHideCursor = false
        }
        CursorSkinStore.shared.activeCursor().set()
    }

    func setupMiddleClickListeners() {
        doubleClickActivation.reset()
        // Remove existing monitors
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
        
        guard let buttonNumber = activationMethod.buttonNumber else { return }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self = self, event.buttonNumber == buttonNumber else { return }
            self.handleMouseClick(event, at: NSEvent.mouseLocation)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self = self, event.buttonNumber == buttonNumber else { return event }
            self.handleMouseClick(event, at: NSEvent.mouseLocation)
            return event
        }
    }
    
    func handleMouseClick(_ event: NSEvent, at location: NSPoint) {
        // Check if this activation method requires modifier keys
        if activationMethod.requiresModifier {
            guard let requiredModifier = activationMethod.modifierFlags,
                  event.modifierFlags.contains(requiredModifier) else { return }
        }
        
        // Handle double-click detection for double middle click
        if activationMethod == .doubleMiddleClick {
            if doubleClickActivation.click(at: ProcessInfo.processInfo.systemUptime, interval: NSEvent.doubleClickInterval) {
                ShortcutEngine.shared.cancelPendingMiddleClick()
                isAutoScrolling ? stopAutoScroll() : startAutoScroll(at: location)
            }
        } else {
            // Single click activation
            ShortcutEngine.shared.cancelPendingMiddleClick()
            isAutoScrolling ? stopAutoScroll() : startAutoScroll(at: location)
        }
    }

    func startAutoScroll(at point: NSPoint) {
        ShortcutEngine.shared.cancelPendingMiddleClick()
        guard AXIsProcessTrusted() else { showPermissionSettings(); return }
        stopAutoScroll()
        originalPoint = point
        isAutoScrolling = true
        applyScrollCursor()
        showScrollHUD()

        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            self?.performScroll()
            self?.applyScrollCursor() // keep forcing cursor (no-op when disabled)
        }
        RunLoop.current.add(scrollTimer!, forMode: .common)
    }

    func performScroll() {
        guard let start = originalPoint else { return }
        let current = NSEvent.mouseLocation
        let deltaY = current.y - start.y

        let deadZone: CGFloat = 5.0
        
        // Flipped the default direction - now moving up scrolls up by default
        let directionMultiplier = isDirectionInverted ? 1.0 : -1.0  // Inverted the multiplier
        let direction = (deltaY > 0 ? -1.0 : 1.0) * directionMultiplier
        
        let distance = max(0, abs(deltaY) - deadZone)

        // Quadratic acceleration: scrollSpeed grows faster as distance increases
        let acceleration = pow(distance / 50, 2.0) // scale distance into a nice curve
        let maxScrollSpeed: CGFloat = 30.00
        let scrollSpeed = min(acceleration * 2.5, maxScrollSpeed) // scaled + capped

        // Apply sensitivity multiplier with exponential scaling for values < 1.0
        // This makes slower speeds MUCH slower but still usable
        let adjustedSensitivity: CGFloat
        if scrollSensitivity < 1.0 {
            // Exponential scaling for slow speeds, but not too extreme
            // 0.1 becomes ~0.03, 0.2 becomes ~0.08, 0.5 becomes ~0.35
            adjustedSensitivity = CGFloat(pow(scrollSensitivity, 1.5))
        } else {
            // Linear scaling for faster speeds
            adjustedSensitivity = CGFloat(scrollSensitivity)
        }
        
        let finalAmount = direction * scrollSpeed * adjustedSensitivity

        // Dynamic threshold based on sensitivity - allow very slow scrolling at low sensitivities
        let threshold = min(0.1, adjustedSensitivity * 0.5)
        if abs(finalAmount) < threshold {
            scrollIntegrator.reset()
            return // don't scroll unless meaningful
        }
        let pixels = scrollIntegrator.pixels(for: finalAmount)
        guard pixels != 0 else { return }

        if let scrollEvent = CGEvent(scrollWheelEvent2Source: nil,
                                    units: .pixel,
                                    wheelCount: 1,
                                    wheel1: pixels,
                                    wheel2: 0,
                                    wheel3: 0) {
            scrollEvent.flags = .maskNonCoalesced
            scrollEvent.setIntegerValueField(.eventSourceUserData, value: Self.syntheticScrollTag)
            scrollEvent.post(tap: .cgSessionEventTap)
        }
    }

    @objc func toggleTrackpadMode() {
        if isAutoScrolling {
            stopAutoScroll()
        } else {
            startTrackpadAutoScroll()
        }
    }

    func startTrackpadAutoScroll() {
        guard AXIsProcessTrusted() else { showPermissionSettings(); return }
        stopAutoScroll() // Clear any existing state
        
        isTrackpadMode = true
        originalPoint = NSEvent.mouseLocation
        isAutoScrolling = true
        
        // Show custom cursor (unless a "click does not interrupt" option is on)
        applyScrollCursor()
        
        // Start timer for scrolling
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            self?.performScroll()
            self?.applyScrollCursor() // keep forcing cursor (no-op when disabled)
        }
        RunLoop.current.add(scrollTimer!, forMode: .common)
        
        showScrollHUD()
        // Show feedback to user
        showTrackpadModeNotification()
    }

    func showScrollHUD() {
        // Dismiss any existing HUD
        hudWindow?.close()
        hudWindow = nil

        let hud = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 48),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hud.isReleasedWhenClosed = false
        AppAppearance.configure(hud)
        hud.level = .floating
        hud.ignoresMouseEvents = true
        hud.hasShadow = true
        hud.center()

        hud.contentView = NSHostingView(rootView: ScrollStatusHUD())

        hud.orderFrontRegardless()
        hudWindow = hud

        // Close after 1.5 seconds without intercepting any pointer input.
        let thisHud = hud
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.hudWindow === thisHud {
                thisHud.close()
                self?.hudWindow = nil
            }
        }
    }

    func showTrackpadModeNotification() {
        guard PermissionStore.shared.notifications else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.t("hud.active")
        content.body = L10n.t("notification.body")
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(
            identifier: "com.scrollapp.trackpadmode",
            content: content,
            trigger: nil  // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error.localizedDescription)")
            }
        }
    }

    @objc func sensitivityChanged(_ sender: NSSlider) {
        scrollSensitivity = sender.doubleValue
        UserDefaults.standard.set(scrollSensitivity, forKey: "scrollSensitivity")
        
        // Update the label and menu item title
        if let sensitivityItem = statusItem.menu?.item(withTag: Self.sensitivityMenuItemTag) {
            sensitivityItem.title = L10n.t("menu.scrollSpeed", scrollSensitivity)
            
            if let view = sensitivityItem.view,
               let label = view.viewWithTag(100) as? NSTextField {
                label.stringValue = String(format: "%.1fx", scrollSensitivity)
            }
        }
    }
    
    @objc func selectActivationMethod(_ sender: NSMenuItem) {
        guard let method = sender.representedObject as? ActivationMethod else { return }
        
        activationMethod = method
        UserDefaults.standard.set(method.rawValue, forKey: "activationMethod")
        
        // Update menu item states
        if let activationItem = statusItem.menu?.item(withTag: Self.activationMenuItemTag),
           let submenu = activationItem.submenu {
            for item in submenu.items {
                item.state = (item.representedObject as? ActivationMethod == method) ? .on : .off
            }
        }
        
        // Restart mouse listeners with new configuration
        setupMiddleClickListeners()
    }

    @objc func showAbout() {
        AboutPanelController.shared.show(body: L10n.t("about.bodyMenu"))
    }

    @objc func showSettingsWindow() {
        if settingsWindow == nil {
            let contentView = SettingsRootView()
            let hostingController = NSHostingController(rootView: contentView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = L10n.t("settings.windowTitle")
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: Style.windowWidth, height: Style.windowHeight))
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            AppAppearance.configure(window)
            // Must stay false: with background dragging enabled, AppKit steals the
            // drag before SwiftUI's slider gesture sees it, so dragging the speed
            // slider used to drag / flicker the whole window. The title bar still drags.
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            settingsWindow = window
        }
        // The settings window activates the app, which is exactly when a leaked
        // NSCursor.hide() would surface. Make sure the pointer is normal here.
        if isAutoScrolling { stopAutoScroll() }
        restoreCursor()
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSkinSettings() {
        CursorSkinStore.shared.section = "skins"
        showSettingsWindow()
    }

    @objc func showPromptStudio() {
        CursorSkinStore.shared.section = "prompt"
        showSettingsWindow()
    }

    @MainActor @objc func promptFromClipboard() {
        showPromptStudio()
        PromptStudioStore.shared.paste()
    }

    @objc func cursorSkinDidChange() {
        createScrollCursor()
        if isAutoScrolling { applyScrollCursor() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Belt and braces: never leave the app active with a hidden/custom cursor.
        if !isAutoScrolling {
            restoreCursor()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    @objc func settingsDidChange(_ notification: Notification) {
        let ud = UserDefaults.standard

        switch notification.name.rawValue {
        case "ScrollappSensitivityChanged":
            let newVal = ud.double(forKey: "scrollSensitivity")
            scrollSensitivity = newVal.isFinite && (0.2...3).contains(newVal) ? newVal : 1.0
            updateMenuSensitivity()

        case "ScrollappInvertChanged":
            isDirectionInverted = ud.bool(forKey: "invertScrollDirection")
            syncMenuItemState(#selector(toggleDirectionInversion), on: isDirectionInverted)

        case "ScrollappLeftClickChanged":
            leftClickDoesNotInterrupt = ud.bool(forKey: "leftClickDoesNotInterrupt")
            syncMenuItemState(#selector(toggleLeftClickInterrupt), on: leftClickDoesNotInterrupt)
            refreshCursorForCurrentState()

        case "ScrollappRightClickChanged":
            rightClickDoesNotInterrupt = ud.bool(forKey: "rightClickDoesNotInterrupt")
            syncMenuItemState(#selector(toggleRightClickInterrupt), on: rightClickDoesNotInterrupt)
            refreshCursorForCurrentState()

        case "ScrollappLaunchChanged":
            launchAtLogin = ud.bool(forKey: "launchAtLogin")
            updateLoginItemState()
            syncMenuItemState(#selector(toggleLaunchAtLogin), on: launchAtLogin)

        case "ScrollappActivationChanged":
            if let raw = ud.string(forKey: "activationMethod"),
               let method = ActivationMethod(rawValue: raw) {
                activationMethod = method
                setupMiddleClickListeners()
                syncActivationMenu(method)
            }

        default:
            break
        }
    }

    func syncMenuItemState(_ action: Selector, on state: Bool) {
        if let item = statusItem.menu?.items.first(where: { $0.action == action }) {
            item.state = state ? .on : .off
        }
    }

    func syncActivationMenu(_ method: ActivationMethod) {
        if let activationItem = statusItem.menu?.item(withTag: Self.activationMenuItemTag),
           let submenu = activationItem.submenu {
            for item in submenu.items {
                item.state = (item.representedObject as? ActivationMethod == method) ? .on : .off
            }
        }
    }

    func updateMenuSensitivity() {
        guard let item = statusItem.menu?.item(withTag: Self.sensitivityMenuItemTag) else { return }
        item.title = L10n.t("menu.scrollSpeed", scrollSensitivity)
        if let view = item.view {
            if let label = view.viewWithTag(100) as? NSTextField {
                label.stringValue = String(format: "%.1fx", scrollSensitivity)
            }
            for sub in view.subviews {
                if let slider = sub as? NSSlider {
                    slider.doubleValue = scrollSensitivity
                }
            }
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func stopAutoScroll() {
        scrollTimer?.invalidate()
        scrollTimer = nil
        restoreCursor()
        isAutoScrolling = false
        isTrackpadMode = false
        originalPoint = nil
        scrollIntegrator.reset()
        lastScrollTime = nil
    }

    func setupTrackpadActivation() {
        for monitor in [optionKeyMonitor, scrollMonitor, clickMonitor, localClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        optionKeyMonitor = nil; scrollMonitor = nil; clickMonitor = nil; localClickMonitor = nil
        // Detect Option key via flagsChanged
        optionKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self,
                  event.cgEvent?.getIntegerValueField(.eventSourceUserData) !=
                    SystemShortcutDelivery.syntheticTag else { return }
            
            // Detect Option key
            let optionKeyFlag = NSEvent.ModifierFlags.option
            
            // If Option key is pressed and we're not already scrolling
            if event.modifierFlags.contains(optionKeyFlag) && !self.isAutoScrolling {
                // Start a timer to detect if two-finger scroll happens while Option is pressed
                self.lastScrollTime = Date()
                
                // If we detect a scroll within 1 second of Option press, activate auto-scroll
            } else { self.lastScrollTime = nil }
        }
        
        // Detect two-finger scroll while Option is pressed
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self,
                  let lastScrollTime = self.lastScrollTime,
                  Date().timeIntervalSince(lastScrollTime) < 1.0,
                  !self.isAutoScrolling,
                  event.modifierFlags.contains(.option),
                  event.cgEvent?.getIntegerValueField(.eventSourceUserData) != Self.syntheticScrollTag,
                  abs(event.deltaY) > 0.1 else { return }
            
            // Option + scroll detected, activate auto-scroll
            self.startTrackpadAutoScroll()
        }
        
        // Monitor for clicks to exit auto-scroll mode
        let handleStop: (NSEvent) -> Void = { [weak self] event in
            guard let self = self, self.isAutoScrolling else { return }

            // Don't stop auto-scroll for the configured activation button
            if event.type == .otherMouseDown,
               let activationButtonNumber = self.activationMethod.buttonNumber,
               event.buttonNumber == activationButtonNumber {
                return // Skip - let the activation method handler deal with it
            }

            // If left-click interruption is disabled, allow left-click to pass through
            if self.leftClickDoesNotInterrupt && event.type == .leftMouseDown {
                return
            }

            // Same for right-click (both options can be enabled at the same time)
            if self.rightClickDoesNotInterrupt && event.type == .rightMouseDown {
                return
            }

            // For all other clicks, stop auto-scroll
            self.stopAutoScroll()
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: handleStop)
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            handleStop(event); return event
        }
    }

    @objc func toggleDirectionInversion() {
        // Toggle the inversion state
        isDirectionInverted = !isDirectionInverted
        
        // Save preference
        UserDefaults.standard.set(isDirectionInverted, forKey: "invertScrollDirection")
        
        // Update menu item state
        if let menu = statusItem.menu,
           let invertItem = menu.items.first(where: { $0.action == #selector(toggleDirectionInversion) }) {
            invertItem.state = isDirectionInverted ? .on : .off
        }
        
        // No notification - removed
    }

    @objc func toggleLaunchAtLogin() {
        launchAtLogin = !launchAtLogin
        UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
        updateLoginItemState()

        // Update menu item state
        syncMenuItemState(#selector(toggleLaunchAtLogin), on: launchAtLogin)
    }

    @objc func toggleLeftClickInterrupt() {
        leftClickDoesNotInterrupt = !leftClickDoesNotInterrupt
        UserDefaults.standard.set(leftClickDoesNotInterrupt, forKey: "leftClickDoesNotInterrupt")

        // Update menu item state
        syncMenuItemState(#selector(toggleLeftClickInterrupt), on: leftClickDoesNotInterrupt)
        refreshCursorForCurrentState()
    }

    @objc func toggleRightClickInterrupt() {
        rightClickDoesNotInterrupt = !rightClickDoesNotInterrupt
        UserDefaults.standard.set(rightClickDoesNotInterrupt, forKey: "rightClickDoesNotInterrupt")

        syncMenuItemState(#selector(toggleRightClickInterrupt), on: rightClickDoesNotInterrupt)
        refreshCursorForCurrentState()
    }

    /// Re-evaluate the cursor when the options change mid-scroll.
    func refreshCursorForCurrentState() {
        guard isAutoScrolling else { return }
        applyScrollCursor()
    }

    func updateLoginItemState() {
        if #available(macOS 13.0, *) {
            // Use the newer ServiceManagement API for macOS 13+
            let service = SMAppService.mainApp
            do {
                if launchAtLogin {
                    if service.status != .enabled {
                        try service.register()
                    }
                } else {
                    if service.status == .enabled {
                        try service.unregister()
                    }
                }
            } catch {
                PermissionStore.shared.loginError = true
            }
            launchAtLogin = service.status == .enabled
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            PermissionStore.shared.refresh()
        } else {
            // Use the older SMLoginItemSetEnabled API for macOS 11.0-12.x
            if let bundleIdentifier = Bundle.main.bundleIdentifier {
                let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, launchAtLogin)
                if !success {
                    print("Failed to update login item using legacy API")
                }
            }
        }
    }
    
    func checkAccessibilityPermissions() {
        // Check if we have Accessibility permissions
        let trusted = AXIsProcessTrusted()
        
        if !trusted {
            // Show alert asking user to grant permissions
            StyledDialog.present(title: L10n.t("permission.title"),
                                 message: L10n.t("permission.body"),
                                 primaryTitle: L10n.t("permission.open"),
                                 secondaryTitle: L10n.t("permission.skip"),
                                 isWarning: true) { openSettings in
                guard openSettings else { return }
                // Open Accessibility preferences
                self.showPermissionSettings()
                PermissionStore.shared.requestAccessibility()
            }
        }
    }
    @objc func showPermissionSettings() {
        CursorSkinStore.shared.section = "permissions"
        showSettingsWindow()
    }
    @objc func permissionsChanged() {
        guard !CommandLine.arguments.contains("--skin-preview"),
              !CommandLine.arguments.contains("--prompt-preview") else { return }
        if !AXIsProcessTrusted() { stopAutoScroll() }
        setupMiddleClickListeners()
        setupTrackpadActivation()
        ShortcutEngine.shared.refreshListener()
    }

    @objc func showShortcutSettings() {
        CursorSkinStore.shared.section = "shortcuts"
        showSettingsWindow()
    }
    @objc func shortcutBack() {
        NotificationCenter.default.post(name: .init("ScrollappShortcutRecordingCancelled"), object: nil)
        ShortcutEngine.shared.back()
    }
    @objc func shortcutReset() {
        NotificationCenter.default.post(name: .init("ScrollappShortcutRecordingCancelled"), object: nil)
        ShortcutEngine.shared.reset()
    }
    @objc func shortcutLoop() {
        NotificationCenter.default.post(name: .init("ScrollappShortcutRecordingCancelled"), object: nil)
        ShortcutEngine.shared.setLooping(!ShortcutEngine.shared.sequence.isLooping)
    }
    @objc func shortcutSequenceChanged() {
        let sequence = ShortcutEngine.shared.sequence
        guard let item = statusItem?.menu?.item(withTag: Self.shortcutProgressMenuTag) else { return }
        item.title = sequence.steps.isEmpty ? L10n.t("settings.shortcuts") :
            L10n.t(sequence.isLooping ? "shortcuts.menuLoopProgress" : "shortcuts.menuProgress",
                sequence.isLooping ? sequence.position + 1 : sequence.position, sequence.steps.count)
        item.state = sequence.isEnabled ? .on : .off
        item.submenu?.item(withTag: Self.shortcutLoopMenuTag)?.state = sequence.isLooping ? .on : .off
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NotificationCenter.default.post(name: .init("ScrollappShortcutRecordingCancelled"), object: nil)
        sender.orderOut(nil)
        ShortcutInputShield.shared.refresh()
        NSApp.setActivationPolicy(.accessory)
        return false // don't close, just hide
    }
}
