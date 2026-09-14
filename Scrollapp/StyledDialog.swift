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

/// Shows the styled dialog as a plain, **non-modal** key window and reports the
/// chosen button through a completion handler.
///
/// Deliberately no `NSApp.runModal` here: inside this menu-bar app the nested
/// modal session ended up blocking event delivery entirely — the buttons still
/// highlighted (SwiftUI drew the pressed state) but neither the button action
/// nor the red close button ever ran. A normal window plus a callback keeps the
/// regular app run loop in charge, which always delivers events.
final class StyledDialog: NSObject, NSWindowDelegate {

    /// Keeps presented dialogs alive until they are dismissed.
    private static var live: Set<StyledDialog> = []

    private var window: NSWindow?
    private var keyMonitor: Any?
    private var completion: ((Bool) -> Void)?
    private var previousPolicy: NSApplication.ActivationPolicy = .accessory
    private var finished = false

    static func present(title: String,
                        message: String,
                        primaryTitle: String,
                        secondaryTitle: String? = nil,
                        isWarning: Bool = false,
                        completion: ((Bool) -> Void)? = nil) {
        let dialog = StyledDialog()
        live.insert(dialog)
        dialog.completion = completion
        // Next run loop turn: presenting straight out of an NSMenu action or a
        // SwiftUI button handler happens while a tracking loop is still
        // unwinding, and the fresh window can miss its first events.
        DispatchQueue.main.async {
            dialog.show(title: title,
                        message: message,
                        primaryTitle: primaryTitle,
                        secondaryTitle: secondaryTitle,
                        isWarning: isWarning)
        }
    }

    private func show(title: String,
                      message: String,
                      primaryTitle: String,
                      secondaryTitle: String?,
                      isWarning: Bool) {

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
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.929, alpha: 1.0)
        // Must stay false: window background dragging makes AppKit grab the
        // mouse-down before the buttons see it (same trap as the speed slider).
        window.isMovableByWindowBackground = false
        // A real, working close button; the two permanently disabled dots that
        // used to sit next to it only looked like decoration.
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.level = .floating
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        window.delegate = self
        self.window = window

        // Esc / Return behave like a stock alert.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            switch event.keyCode {
            case 53: self.finish(primary: false); return nil            // Esc
            case 36, 76: self.finish(primary: true); return nil         // Return / Enter
            default: return event
            }
        }

        // A menu-bar (.accessory) app cannot own a key window, so switch to
        // .regular while the dialog is up and switch back once it is gone.
        previousPolicy = NSApp.activationPolicy()
        if previousPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func otherAppWindowVisible() -> Bool {
        NSApp.windows.contains { $0.isVisible && $0 !== window && $0.styleMask.contains(.titled) }
    }

    private func finish(primary: Bool) {
        guard !finished else { return }
        finished = true

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let window {
            window.delegate = nil
            window.close()
            self.window = nil
        }
        if previousPolicy != .regular, !otherAppWindowVisible() {
            NSApp.setActivationPolicy(previousPolicy)
        }

        let done = completion
        completion = nil
        done?(primary)
        StyledDialog.live.remove(self)
    }

    // Red close button dismisses just like the secondary action.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(primary: false)
        return false
    }
}

/// Convenience wrapper for the About dialog (single OK button).
final class AboutPanelController {
    static let shared = AboutPanelController()

    func show(body: String) {
        StyledDialog.present(title: L10n.t("about.title"),
                             message: body,
                             primaryTitle: L10n.t("alert.ok"))
    }
}
