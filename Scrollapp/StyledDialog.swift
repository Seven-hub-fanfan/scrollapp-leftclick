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
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(style == .primary ? .white : Style.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
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
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Presenter

/// Shows the styled dialog as an application-modal window and reports whether
/// the primary button was chosen (drop-in replacement for `NSAlert.runModal()`).
final class StyledDialog {

    @discardableResult
    static func run(title: String,
                    message: String,
                    primaryTitle: String,
                    secondaryTitle: String? = nil,
                    isWarning: Bool = false) -> Bool {

        var primaryChosen = false
        var window: NSWindow?

        let view = StyledDialogView(
            title: title,
            message: message,
            primaryTitle: primaryTitle,
            secondaryTitle: secondaryTitle,
            isWarning: isWarning,
            onPrimary: {
                primaryChosen = true
                if let window { NSApp.stopModal(); window.orderOut(nil) }
            },
            onSecondary: {
                primaryChosen = false
                if let window { NSApp.stopModal(); window.orderOut(nil) }
            }
        )

        let hosting = NSHostingController(rootView: view)
        let panel = NSWindow(contentViewController: hosting)
        panel.styleMask = [.titled, .closable, .fullSizeContentView]
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = NSColor(calibratedWhite: 0.929, alpha: 1.0)
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.level = .modalPanel
        panel.setContentSize(hosting.view.fittingSize)
        panel.center()
        window = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)

        return primaryChosen
    }
}

/// Convenience wrapper for the About dialog (single OK button).
final class AboutPanelController {
    static let shared = AboutPanelController()

    func show(body: String) {
        StyledDialog.run(title: L10n.t("about.title"),
                         message: body,
                         primaryTitle: L10n.t("alert.ok"))
    }
}
