//
//  StyledDialog.swift
//  Scrollapp
//
//  Neumorphic replacement for NSAlert so every dialog matches the redesigned
//  settings window instead of falling back to the stock blue system alert.
//

import SwiftUI
import Cocoa

// MARK: - View

struct StyledDialogView: View {
    let title: String
    let message: String
    let primaryTitle: String
    let secondaryTitle: String?
    let isWarning: Bool
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    private let contentWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 14) {
            AppIconTile()
                .padding(.top, 2)

            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(Style.primaryText)
                .multilineTextAlignment(.center)

            Card(padV: 12) {
                Text(message)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(Style.primaryText.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                if let secondaryTitle {
                    DialogButton(title: secondaryTitle, style: .secondary, action: onSecondary)
                }
                DialogButton(title: primaryTitle, style: .primary, action: onPrimary)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(width: contentWidth + 36)
        .background(Style.background)
    }
}

private struct DialogButton: View {
    enum Kind { case primary, secondary }

    let title: String
    let style: Kind
    let action: () -> Void

    var body: some View {
        ZStack {
            Group {
                if style == .primary {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Style.glossyBlack)
                        .shadow(color: Color.black.opacity(0.25), radius: 5, x: 0, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Style.card)
                        .raised(radius: 15, darkBlur: 6, lightBlur: 5, offset: 3)
                }
            }
            // The clickable layer is a real AppKit NSButton: SwiftUI `Button`
            // never received mouse-down inside this dialog (LSUIElement app +
            // modal panel), so the action is driven through AppKit's own
            // target/action path instead, which always fires.
            NativeButton(title: title,
                         isPrimary: style == .primary,
                         action: action)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
    }
}

/// A button that acts on the very first click even when the app / window was
/// not active. Without this the dialog swallowed every click as a mere
/// activation click, which is what made the "OK" button look dead.
private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Thin AppKit button used as the hit-testing / action layer on top of the
/// neumorphic background. Draws only its title, never a bezel.
private struct NativeButton: NSViewRepresentable {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire(_ sender: Any?) { action() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = FirstMouseButton(frame: .zero)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.setButtonType(.momentaryChange)
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.backgroundColor = .clear
        button.target = context.coordinator
        button.action = #selector(Coordinator.fire(_:))
        apply(to: button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        apply(to: button)
    }

    private func apply(to button: NSButton) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: isPrimary
                    ? NSColor.white
                    : NSColor(calibratedWhite: 0.18, alpha: 1.0),
                .paragraphStyle: paragraph
            ]
        )
    }
}

// MARK: - Presenter

/// Shows the styled dialog as an application-modal window and reports whether
/// the primary button was chosen (drop-in replacement for `NSAlert.runModal()`).
final class StyledDialog: NSObject, NSWindowDelegate {

    private static var live: StyledDialog?

    private var primaryChosen = false
    private var panel: NSWindow?
    private var keyMonitor: Any?

    @discardableResult
    static func run(title: String,
                    message: String,
                    primaryTitle: String,
                    secondaryTitle: String? = nil,
                    isWarning: Bool = false) -> Bool {
        let dialog = StyledDialog()
        live = dialog
        defer { live = nil }
        return dialog.present(title: title,
                              message: message,
                              primaryTitle: primaryTitle,
                              secondaryTitle: secondaryTitle,
                              isWarning: isWarning)
    }

    private func present(title: String,
                         message: String,
                         primaryTitle: String,
                         secondaryTitle: String?,
                         isWarning: Bool) -> Bool {

        let view = StyledDialogView(
            title: title,
            message: message,
            primaryTitle: primaryTitle,
            secondaryTitle: secondaryTitle,
            isWarning: isWarning,
            onPrimary: { [weak self] in self?.finish(primary: true) },
            onSecondary: { [weak self] in self?.finish(primary: false) }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.hidesOnDeactivate = false
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.929, alpha: 1.0)
        // Must stay false. With background dragging on, AppKit's window-drag
        // tracking grabs the mouse-down before it ever reaches the buttons —
        // that is exactly why the "OK" button looked dead. Same trap as the
        // speed slider in the main window.
        window.isMovableByWindowBackground = false
        // Keep a *real* close button and hide the two permanently-disabled dots
        // (those grey circles looked like fake decoration).
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.level = .modalPanel
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        window.delegate = self
        panel = window

        // Esc / Return work like a normal alert.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: self.finish(primary: false); return nil            // Esc
            case 36, 76: self.finish(primary: true); return nil         // Return / Enter
            default: return event
            }
        }

        // LSUIElement apps cannot truly activate while staying .accessory, and an
        // inactive window never hands clicks to SwiftUI buttons — which is why the
        // "OK" button appeared dead. Become a regular app for the dialog's lifetime.
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Activation is asynchronous; re-assert key status once the modal run loop
        // is spinning, otherwise the panel can come up unfocused.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.runModal(for: window)

        if previousPolicy != .regular, !isSettingsWindowVisible() {
            NSApp.setActivationPolicy(previousPolicy)
        }
        return primaryChosen
    }

    private func isSettingsWindowVisible() -> Bool {
        return NSApp.windows.contains { $0.isVisible && $0.level != .modalPanel && $0.styleMask.contains(.miniaturizable) }
    }

    private func finish(primary: Bool) {
        guard let panel else { return }
        primaryChosen = primary
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel.delegate = nil
        NSApp.stopModal()
        panel.orderOut(nil)
        self.panel = nil
    }

    // Red close button behaves like the secondary / dismiss action.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(primary: false)
        return false
    }
}

/// Convenience wrapper for the About dialog (single OK button).
final class AboutPanelController {
    static let shared = AboutPanelController()

    func show(body: String) {
        // Presented on the next main-queue turn: running a nested modal loop
        // directly inside an NSMenu action / SwiftUI button handler leaves the
        // previous tracking loop unwinding and the dialog ends up unable to
        // receive mouse events.
        DispatchQueue.main.async {
            StyledDialog.run(title: L10n.t("about.title"),
                             message: body,
                             primaryTitle: L10n.t("alert.ok"))
        }
    }
}
