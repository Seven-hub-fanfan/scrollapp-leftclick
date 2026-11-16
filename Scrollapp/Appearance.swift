import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable {
    case dark, light, system

    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: "interfaceAppearance") ?? "") ?? .dark
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    var icon: String {
        switch self {
        case .dark: return "moon"
        case .light: return "sun.max"
        case .system: return "circle.lefthalf.filled"
        }
    }

    static func configure(_ window: NSWindow) {
        switch current {
        case .dark: window.appearance = NSAppearance(named: .darkAqua)
        case .light: window.appearance = NSAppearance(named: .aqua)
        case .system: window.appearance = nil
        }
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    static func updateWindows() {
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            configure(window)
        }
    }
}

// All colors resolve against the window appearance, including native previews
// and dialog titles. Color is reserved for focus, permission status and artwork.
enum Style {
    static let windowWidth: CGFloat = 880
    static let windowHeight: CGFloat = 680
    static let sidebarWidth: CGFloat = 76
    static let outerPadH: CGFloat = 30
    static let cardPadH: CGFloat = 18
    static let cardRadius: CGFloat = 12
    static let cardGap: CGFloat = 14
    static var scrollerGutter: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
    }

    static func native(_ dark: NSColor, _ light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
    static func adaptive(_ dark: NSColor, _ light: NSColor) -> Color {
        Color(nsColor: native(dark, light))
    }
    static let background = adaptive(.black.withAlphaComponent(0.20), .white.withAlphaComponent(0.38))
    static let card = adaptive(.black.withAlphaComponent(0.25), .white.withAlphaComponent(0.56))
    static let control = adaptive(.white.withAlphaComponent(0.065), .black.withAlphaComponent(0.045))
    static let recess = adaptive(.black.withAlphaComponent(0.22), .black.withAlphaComponent(0.055))
    static let rail = adaptive(.black.withAlphaComponent(0.17), .white.withAlphaComponent(0.20))
    static let line = adaptive(.white.withAlphaComponent(0.095), .black.withAlphaComponent(0.085))
    static let primaryNS = native(NSColor(white: 0.94, alpha: 1), NSColor(white: 0.12, alpha: 1))
    static let actionTextNS = native(NSColor(white: 0.12, alpha: 1), NSColor(white: 0.97, alpha: 1))
    static let primaryText = Color(nsColor: primaryNS)
    static let secondaryText = adaptive(NSColor(white: 0.68, alpha: 1), NSColor(white: 0.36, alpha: 1))
    static let accent = adaptive(NSColor(white: 0.94, alpha: 1), NSColor(white: 0.15, alpha: 1))
    static let actionText = Color(nsColor: actionTextNS)
    static let tick = adaptive(.white.withAlphaComponent(0.24), .black.withAlphaComponent(0.20))
    static let focus = adaptive(NSColor(red: 0.53, green: 0.70, blue: 0.93, alpha: 1),
                                NSColor(red: 0.20, green: 0.40, blue: 0.72, alpha: 1))
    static let success = adaptive(NSColor(red: 0.62, green: 0.79, blue: 0.67, alpha: 1),
                                  NSColor(red: 0.22, green: 0.45, blue: 0.30, alpha: 1))
    static let error = adaptive(NSColor(red: 0.96, green: 0.59, blue: 0.53, alpha: 1),
                                NSColor(red: 0.65, green: 0.23, blue: 0.19, alpha: 1))
    static let danger = adaptive(NSColor(red: 0.85, green: 0.16, blue: 0.20, alpha: 1),
                                 NSColor(red: 0.79, green: 0.12, blue: 0.16, alpha: 1))
    static let glossyBlack = LinearGradient(colors: [accent, accent],
                                             startPoint: .top, endPoint: .bottom)
}

private struct WindowMaterial: NSViewRepresentable {
    var reduceTransparency: Bool
    var appearance: AppAppearance

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        switch appearance {
        case .dark: view.appearance = NSAppearance(named: .darkAqua)
        case .light: view.appearance = NSAppearance(named: .aqua)
        case .system: view.appearance = nil
        }
        view.state = reduceTransparency ? .inactive : .active
        view.wantsLayer = true
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = reduceTransparency
                ? Style.native(NSColor(white: 0.13, alpha: 1), NSColor(white: 0.93, alpha: 1)).cgColor
                : nil
        }
        // The representable is first updated before it acquires a window.
        DispatchQueue.main.async {
            if let window = view.window { AppAppearance.configure(window) }
        }
    }
}

struct GlassBackground: View {
    @AppStorage("interfaceAppearance") private var appearance = AppAppearance.dark.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        WindowMaterial(reduceTransparency: reduceTransparency,
                       appearance: AppAppearance(rawValue: appearance) ?? .dark)
            .overlay(Style.background)
            .overlay(
                LinearGradient(colors: [.black.opacity(reduceTransparency ? 0 : 0.12), .clear],
                               startPoint: .bottomLeading, endPoint: .topTrailing)
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct GlassSurface: ViewModifier {
    var radius: CGFloat = Style.cardRadius
    func body(content: Content) -> some View {
        content
            .background(Style.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Style.line, lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func glassSurface(radius: CGFloat = Style.cardRadius) -> some View {
        modifier(GlassSurface(radius: radius))
    }
}

struct Card<Content: View>: View {
    var padV: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, Style.cardPadH)
            .padding(.vertical, padV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
    }
}

struct CardLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Style.primaryText)
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 25, weight: .semibold)).tracking(-0.5)
                .foregroundStyle(Style.primaryText)
            Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Style.secondaryText)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GlassButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, destructive }
    var kind: Kind = .secondary
    var height: CGFloat = 34
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 13).frame(height: height)
            .foregroundStyle(kind == .destructive ? .white : kind == .primary ? Style.actionText : Style.primaryText)
            .background(kind == .destructive ? Style.danger : kind == .primary ? Style.accent : kind == .quiet ? .clear : Style.control,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(kind == .quiet ? .clear : Style.line, lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 8).fill(Style.primaryText.opacity(hovered && kind != .primary ? 0.045 : 0)))
            .opacity(!isEnabled ? 0.42 : configuration.isPressed ? 0.70 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: hovered)
    }
}

struct AppIconTile: View {
    var body: some View {
        Image(systemName: "arrow.up.and.down")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Style.primaryText)
            .frame(width: 40, height: 40)
            .background(Style.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Style.line, lineWidth: 1))
            .accessibilityLabel("Scrollapp")
    }
}

struct ScrollStatusHUD: View {
    @AppStorage("interfaceAppearance") private var appearance = AppAppearance.dark.rawValue
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.and.down").font(.system(size: 13, weight: .medium))
            Text(L10n.t("hud.active")).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Style.primaryText)
        .frame(width: 240, height: 48)
        .background(GlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Style.line, lineWidth: 1))
        .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .dark).colorScheme)
    }
}
