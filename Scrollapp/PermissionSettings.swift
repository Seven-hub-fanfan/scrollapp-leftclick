import AppKit
import SwiftUI
import ApplicationServices
import UserNotifications
import ServiceManagement

enum GuidedPermission: String, CaseIterable {
    case accessibility, input
    var service: String { self == .accessibility ? "Accessibility" : "ListenEvent" }
    var pane: String {
        "com.apple.preference.security?Privacy_" + (self == .accessibility ? "Accessibility" : "ListenEvent")
    }
    var title: String { L10n.t("permissions.guide.\(rawValue).title") }
    var granted: Bool {
        self == .accessibility ? PermissionStore.shared.accessibility : PermissionStore.shared.inputMonitoring
    }
}

final class PermissionStore: ObservableObject {
    static let shared = PermissionStore()
    @Published private(set) var accessibility = AXIsProcessTrusted()
    @Published private(set) var inputMonitoring = CGPreflightListenEventAccess()
    @Published private(set) var notifications = false
    @Published private(set) var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var loginError = false
    @Published private(set) var resetting = false
    @Published private(set) var resetError = false
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }
    func refresh() {
        let ax = AXIsProcessTrusted(), input = CGPreflightListenEventAccess()
        let changed = ax != accessibility || input != inputMonitoring
        if accessibility != ax { accessibility = ax }
        if inputMonitoring != input { inputMonitoring = input }
        let login = SMAppService.mainApp.status == .enabled
        if loginEnabled != login { loginEnabled = login }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let granted = settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional
                if self.notifications != granted { self.notifications = granted }
            }
        }
        if changed {
            NotificationCenter.default.post(name: .init("ScrollappPermissionsChanged"), object: nil)
        }
    }
    func open(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        PermissionGuideWindow.shared.present(.accessibility)
        open(GuidedPermission.accessibility.pane)
    }
    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        PermissionGuideWindow.shared.present(.input)
        open(GuidedPermission.input.pane)
    }
    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async { self.refresh(); self.open("com.apple.Notifications-Settings.extension") }
        }
    }
    func reset(_ permission: GuidedPermission) {
        guard !resetting, let identifier = Bundle.main.bundleIdentifier else { return }
        resetting = true; resetError = false
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            // Reset only this application's selected service, never all TCC entries.
            process.arguments = ["reset", permission.service, identifier]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            var succeeded = false
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                    if process.isRunning { process.terminate() }
                }
                process.waitUntilExit()
                succeeded = process.terminationStatus == 0
            } catch {}
            let success = succeeded
            DispatchQueue.main.async {
                self.resetting = false; self.resetError = !success
                self.refresh()
                if success {
                    if permission == .accessibility { self.requestAccessibility() }
                    else { self.requestInputMonitoring() }
                }
            }
        }
    }
    func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

struct PermissionSettingsView: View {
    @ObservedObject private var permissions = PermissionStore.shared
    @ObservedObject private var skins = CursorSkinStore.shared
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 0) {
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeading(title: L10n.t("settings.permissions"), subtitle: L10n.t("permissions.intro"))
                    .padding(.bottom, 12)
                permissionCard("accessibility", icon: "hand.raised", granted: permissions.accessibility,
                    action: permissions.requestAccessibility)
                permissionCard("input", icon: "keyboard", granted: permissions.inputMonitoring,
                    action: permissions.requestInputMonitoring)
                permissionCard("notifications", icon: "bell", granted: permissions.notifications,
                    action: permissions.requestNotifications)
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle").font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.t("permissions.replacedApp")).font(.system(size: 10)).lineSpacing(3)
                        Text(L10n.t("permissions.currentApp", Bundle.main.bundleURL.path))
                            .font(.system(size: 9)).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Button(L10n.t("permissions.reveal"), action: permissions.revealApplication)
                        .buttonStyle(GlassButtonStyle(kind: .quiet))
                }
                .foregroundStyle(Style.secondaryText).padding(.horizontal, 2).padding(.vertical, 6)
                if permissions.loginError {
                    Text(L10n.t("permissions.loginError")).font(.system(size: 11)).foregroundStyle(Style.error)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label(L10n.t("permissions.recovery"), systemImage: "cursorarrow.rays")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("permissions.recoveryIntro")).font(.system(size: 10))
                        .foregroundStyle(Style.secondaryText).lineSpacing(3)
                    HStack {
                        Button(L10n.t("skins.nativeReset")) {
                            StyledDialog.present(title: L10n.t("skins.nativeReset"),
                                message: L10n.t("permissions.recoveryConfirm"),
                                primaryTitle: L10n.t("skins.nativeReset"), secondaryTitle: L10n.t("action.cancel")) { confirmed in
                                    if confirmed { skins.useSystemCursor() }
                                }
                        }
                        .disabled(skins.isBusy || (!skins.isReady && !skins.needsRecovery))
                        Button(L10n.t("skins.exportDiagnostics"), action: skins.exportDiagnostics)
                    }
                    .buttonStyle(GlassButtonStyle())
                    if let error = skins.errorKey {
                        Text(L10n.t("skins.error.\(error)")).font(.system(size: 10)).foregroundStyle(Style.error)
                    } else if skins.didRestoreNative && skins.isReady && !skins.hasCustomCursor {
                        Label(L10n.t("permissions.recoverySuccess"), systemImage: "checkmark.circle")
                            .font(.system(size: 10)).foregroundStyle(Style.success)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface().padding(.top, 6)
            }
            .padding(.horizontal, Style.outerPadH).padding(.top, 48).padding(.bottom, 20)
          }
          VStack(spacing: 0) {
            Rectangle().fill(Style.line).frame(height: 1)
            HStack {
                Button(L10n.t("permissions.loginSettings")) {
                    permissions.open("com.apple.LoginItems-Settings.extension")
                }.buttonStyle(GlassButtonStyle(kind: .quiet))
                Spacer()
                Button(action: permissions.refresh) {
                    Label(L10n.t("permissions.refresh"), systemImage: "arrow.clockwise")
                }.buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, Style.outerPadH).padding(.vertical, 16)
          }
        }
        .onAppear { permissions.refresh() }
        .onReceive(refreshTimer) { _ in permissions.refresh() }
    }

    private func permissionCard(_ id: String, icon: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 15) {
            Image(systemName: icon).font(.system(size: 17, weight: .regular))
                .foregroundStyle(Style.secondaryText)
                .frame(width: 36, height: 36)
                .background(Style.control, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.t("permissions.\(id).title"))
                    .font(.system(size: 12, weight: .medium))
                Text(L10n.t("permissions.\(id).body")).font(.system(size: 10))
                    .foregroundStyle(Style.secondaryText).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 8) {
                Label(L10n.t(granted ? "permissions.granted" : "permissions.notGranted"),
                      systemImage: granted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(granted ? Style.success : Style.secondaryText)
                Button(L10n.t("permission.open"), action: action)
                    .buttonStyle(GlassButtonStyle()).accessibilityIdentifier("permissions.\(id)")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }
}

/// Remains beside System Settings so its real app file can be dragged into TCC.
final class PermissionGuideWindow {
    static let shared = PermissionGuideWindow()
    private var panel: NSPanel?
    func present(_ permission: GuidedPermission) {
        let window: NSPanel
        if let panel { window = panel }
        else {
            window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 290),
                styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
            window.collectionBehavior = [.fullScreenAuxiliary]
            panel = window
        }
        window.title = permission.title
        AppAppearance.configure(window)
        let host = NSHostingView(rootView: PermissionGuideView(permission: permission) { [weak self] in
            self?.panel?.orderOut(nil)
        })
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.setContentSize(host.fittingSize)
        if let parent = NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.styleMask.contains(.titled) }) {
            window.setFrameOrigin(NSPoint(x: parent.frame.minX + 24, y: parent.frame.minY + 95))
        } else { window.center() }
        window.orderFrontRegardless()
    }
}

struct PermissionGuideView: View {
    let permission: GuidedPermission
    let onClose: () -> Void
    @ObservedObject private var store = PermissionStore.shared
    @AppStorage("interfaceAppearance") private var appearance = AppAppearance.dark.rawValue
    @State private var confirmReset = false
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.motionlines").font(.system(size: 19))
                Text(permission.title).font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(L10n.t("action.close"))
            }
            HStack(spacing: 11) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable().scaledToFit().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scrollapp").font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("permissions.dragApp")).font(.system(size: 10))
                        .foregroundStyle(Style.secondaryText)
                }
                Spacer()
                Image(systemName: "arrow.up.forward").font(.system(size: 13))
                    .foregroundStyle(Style.secondaryText)
            }
            .padding(12).background(Style.control, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Style.line, lineWidth: 1))
            .overlay(ApplicationDragSurface(url: Bundle.main.bundleURL))
            Text(L10n.t("permissions.dragInstructions")).font(.system(size: 11))
                .foregroundStyle(Style.secondaryText).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(Bundle.main.bundleURL.path).font(.system(size: 9))
                .foregroundStyle(Style.secondaryText).lineLimit(1).truncationMode(.middle)
                .help(Bundle.main.bundleURL.path)
            HStack {
                Button(L10n.t("permissions.resetGrant")) { confirmReset = true }
                    .disabled(store.resetting).accessibilityIdentifier("permissions.guide.reset")
                Spacer()
                Button(L10n.t("permissions.reveal"), action: store.revealApplication)
                    .accessibilityIdentifier("permissions.guide.reveal")
            }
            .font(.system(size: 10, weight: .medium)).buttonStyle(.plain)
            Rectangle().fill(Style.line).frame(height: 1)
            Label(L10n.t(permission.granted ? "permissions.guide.granted" : "permissions.guide.waiting"),
                  systemImage: permission.granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10)).foregroundStyle(permission.granted ? Style.success : Style.secondaryText)
            if store.resetError {
                Text(L10n.t("permissions.resetFailed")).font(.system(size: 10)).foregroundStyle(Style.error)
            }
        }
        .padding(18).frame(width: 420)
        .foregroundStyle(Style.primaryText).background(GlassBackground())
        .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .dark).colorScheme)
        .onReceive(refreshTimer) { _ in store.refresh() }
        .alert(L10n.t("permissions.resetTitle"), isPresented: $confirmReset) {
            Button(L10n.t("action.cancel"), role: .cancel) {}
            Button(L10n.t("permissions.resetGrant"), role: .destructive) { store.reset(permission) }
        } message: { Text(L10n.t("permissions.resetBody")) }
    }
}

struct ApplicationDragSurface: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> ApplicationDragView { ApplicationDragView() }
    func updateNSView(_ view: ApplicationDragView, context: Context) {
        view.applicationURL = url
        view.setAccessibilityLabel(L10n.t("permissions.dragApp"))
        view.setAccessibilityHelp(L10n.t("permissions.dragInstructions"))
        view.setAccessibilityValue(url.path)
        view.setAccessibilityIdentifier("permissions.guide.application")
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
    }
}

final class ApplicationDragView: NSView, NSDraggingSource {
    var applicationURL = Bundle.main.bundleURL
    // NSPanel.isMovableByWindowBackground must not steal this row's drag.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        let origin = event.locationInWindow
        // Track the press on this view until a real drag starts. In an inactive
        // floating panel, returning immediately can lose subsequent events.
        while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                         until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { return }
            let dx = next.locationInWindow.x - origin.x
            let dy = next.locationInWindow.y - origin.y
            if dx * dx + dy * dy >= 16 {
                beginApplicationDrag(with: next)
                return
            }
        }
    }
    override func accessibilityPerformPress() -> Bool {
        NSWorkspace.shared.activateFileViewerSelecting([applicationURL])
        return true
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    func draggingItem() -> NSDraggingItem {
        // NSURL writes public.file-url, which System Settings accepts as an app
        // package. A text string or an icon image cannot add an application.
        NSDraggingItem(pasteboardWriter: applicationURL as NSURL)
    }
    private func beginApplicationDrag(with event: NSEvent) {
        let item = draggingItem()
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44),
            contents: NSWorkspace.shared.icon(forFile: applicationURL.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
