import SwiftUI

// MARK: - Design tokens
//
// All metrics below are measured off the design mock (769×1149 px @2.083x,
// i.e. a 369×552 pt window with a 30 pt title bar → 369×522 pt content area).

private enum Style {
    static let windowWidth: CGFloat = 370
    static let windowHeight: CGFloat = 522        // content area, title bar excluded

    static let outerPadH: CGFloat = 16
    static let cardPadH: CGFloat = 17
    static let cardRadius: CGFloat = 18
    static let cardGap: CGFloat = 18

    static let background = Color(red: 0.929, green: 0.929, blue: 0.933)
    static let card = Color(red: 0.965, green: 0.965, blue: 0.969)
    static let control = Color.white
    static let recess = Color(red: 0.914, green: 0.910, blue: 0.914)
    static let accent = Color(red: 0.075, green: 0.075, blue: 0.082)
    static let primaryText = Color(red: 0.086, green: 0.086, blue: 0.094)
    static let secondaryText = Color(red: 0.42, green: 0.42, blue: 0.45)
    static let tick = Color(red: 0.792, green: 0.792, blue: 0.808)

    // Neumorphic shadow pair: soft dark below-right + white highlight above-left.
    static let shadowDark = Color.black.opacity(0.085)
    static let shadowLight = Color.white.opacity(0.95)

    /// Glossy black used for the icon tile and checked checkboxes.
    static let glossyBlack = LinearGradient(
        colors: [Color(red: 0.19, green: 0.19, blue: 0.20), Color(red: 0.04, green: 0.04, blue: 0.05)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

/// Applies the soft-UI double shadow used by every raised surface.
private struct Raised: ViewModifier {
    var radius: CGFloat
    var darkBlur: CGFloat
    var lightBlur: CGFloat
    var offset: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: Style.shadowDark, radius: darkBlur, x: offset, y: offset)
            .shadow(color: Style.shadowLight, radius: lightBlur, x: -offset, y: -offset)
    }
}

private extension View {
    func raised(radius: CGFloat, darkBlur: CGFloat = 6, lightBlur: CGFloat = 5, offset: CGFloat = 3) -> some View {
        modifier(Raised(radius: radius, darkBlur: darkBlur, lightBlur: lightBlur, offset: offset))
    }
}

/// Section container card.
private struct Card<Content: View>: View {
    var padV: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, Style.cardPadH)
            .padding(.vertical, padV)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                    .fill(Style.card)
                    .raised(radius: Style.cardRadius, darkBlur: 7, lightBlur: 6, offset: 3)
            )
    }
}

private struct CardLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(Style.primaryText)
    }
}

// MARK: - App icon (white plinth + glossy black tile)

private struct AppIconTile: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Style.control)
                .frame(width: 46, height: 46)
                .raised(radius: 15, darkBlur: 7, lightBlur: 6, offset: 3)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Style.glossyBlack)
                .frame(width: 36, height: 36)
                .shadow(color: Color.black.opacity(0.28), radius: 4, x: 0, y: 2)
                .overlay(
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
                )
        }
        .frame(width: 46, height: 46)
    }
}

// MARK: - Speed gauge

private struct SpeedGauge: View {
    let value: Double
    let range: ClosedRange<Double>

    private var progress: Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Style.control)
                .raised(radius: 25, darkBlur: 6, lightBlur: 5, offset: 2.5)

            Circle()
                .trim(from: 0, to: 0.78)
                .stroke(Style.tick.opacity(0.55), style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                .rotationEffect(.degrees(131))
                .padding(4.5)

            Circle()
                .trim(from: 0, to: 0.78 * progress)
                .stroke(Style.accent, style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                .rotationEffect(.degrees(131))
                .padding(4.5)

            VStack(spacing: -1) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(String(format: "%.1f", value))
                        .font(.system(size: 14, weight: .bold))
                    Text("x")
                        .font(.system(size: 9.5, weight: .bold))
                }
                .foregroundColor(Style.primaryText)

                Text(L10n.t("settings.scrollSpeed"))
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundColor(Style.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 8)
        }
        .frame(width: 50, height: 50)
    }
}

// MARK: - Ruler slider

private struct TickSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onChange: () -> Void

    private let trackHeight: CGFloat = 24
    private let knobWidth: CGFloat = 13
    private let knobHeight: CGFloat = 22
    private let tickCount = 38

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - knobWidth, 1)
            let fraction = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound)
                / (range.upperBound - range.lowerBound)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: trackHeight / 2, style: .continuous)
                    .fill(Style.recess)

                // Ruler: hairline baseline with short ticks rising from it.
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<tickCount, id: \.self) { index in
                            Rectangle()
                                .fill(Style.tick.opacity(0.9))
                                .frame(width: 1, height: index % 5 == 0 ? 6.5 : 4.5)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Rectangle()
                        .fill(Style.tick.opacity(0.85))
                        .frame(height: 1)
                }
                .frame(height: 6.5)
                .padding(.horizontal, 11)

                Capsule()
                    .fill(Style.glossyBlack)
                    .frame(width: knobWidth, height: knobHeight)
                    .shadow(color: Color.black.opacity(0.28), radius: 3, x: 0, y: 2)
                    .offset(x: usable * fraction)
            }
            .frame(height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in update(x: drag.location.x - knobWidth / 2, usable: usable) }
            )
        }
        .frame(height: trackHeight)
    }

    private func update(x: CGFloat, usable: CGFloat) {
        let fraction = Double(min(max(x / usable, 0), 1))
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        let clamped = min(max(stepped, range.lowerBound), range.upperBound)
        if abs(clamped - value) > 0.0001 {
            value = clamped
            onChange()
        }
    }
}

// MARK: - Checkbox row

private struct CheckRow: View {
    let title: String
    @Binding var isOn: Bool
    let onChange: () -> Void

    var body: some View {
        Button {
            isOn.toggle()
            onChange()
        } label: {
            HStack(spacing: 15) {
                ZStack {
                    if isOn {
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .fill(Style.glossyBlack)
                            .raised(radius: 7.5, darkBlur: 5, lightBlur: 4, offset: 2.5)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10.5, weight: .heavy))
                            .foregroundColor(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .fill(Style.control)
                            .raised(radius: 7.5, darkBlur: 5, lightBlur: 4, offset: 2.5)
                    }
                }
                .frame(width: 23, height: 23)

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Style.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bottom pill button

private struct PillButton: View {
    let title: String
    let systemImage: String
    let filledIcon: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: filledIcon ? 13 : 12, weight: .bold))
                    .foregroundColor(Style.primaryText)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Style.primaryText)
            }
            .frame(width: 95, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Style.card)
                    .raised(radius: 15, darkBlur: 6, lightBlur: 5, offset: 3)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NSMenu-backed dropdown

/// Invisible click target that pops a native NSMenu, letting us keep a fully
/// custom-styled dropdown row (SwiftUI's Menu label styling is unreliable on macOS).
private struct MenuTrigger: NSViewRepresentable {
    let items: [(title: String, value: String)]
    let selected: String
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> TriggerView {
        let view = TriggerView()
        view.configure(items: items, selected: selected, onSelect: onSelect)
        return view
    }

    func updateNSView(_ view: TriggerView, context: Context) {
        view.configure(items: items, selected: selected, onSelect: onSelect)
    }

    final class TriggerView: NSView {
        private var items: [(title: String, value: String)] = []
        private var selected: String = ""
        private var onSelect: ((String) -> Void)?

        func configure(items: [(title: String, value: String)], selected: String, onSelect: @escaping (String) -> Void) {
            self.items = items
            self.selected = selected
            self.onSelect = onSelect
        }

        override func mouseDown(with event: NSEvent) {
            let menu = NSMenu()
            for (index, item) in items.enumerated() {
                let menuItem = NSMenuItem(title: item.title, action: #selector(pick(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.tag = index
                menuItem.state = (item.value == selected) ? .on : .off
                menu.addItem(menuItem)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
        }

        @objc private func pick(_ sender: NSMenuItem) {
            guard items.indices.contains(sender.tag) else { return }
            onSelect?(items[sender.tag].value)
        }
    }
}

// MARK: - Main view

struct ContentView: View {
    @AppStorage("scrollSensitivity") private var sensitivity: Double = 1.0
    @AppStorage("invertScrollDirection") private var invertScroll = false
    @AppStorage("leftClickDoesNotInterrupt") private var leftClickNoInterrupt = false
    @AppStorage("rightClickDoesNotInterrupt") private var rightClickNoInterrupt = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("activationMethod") private var activationMethod = "Middle Click"

    /// Raw (English) values are the persisted identifiers shared with
    /// AppDelegate.ActivationMethod; only the label shown to the user is localized.
    private let activationMethods: [(raw: String, key: String)] = [
        ("Middle Click", "activation.middleClick"),
        ("Shift + Middle Click", "activation.shiftMiddleClick"),
        ("Cmd + Middle Click", "activation.cmdMiddleClick"),
        ("Option + Middle Click", "activation.optionMiddleClick"),
        ("Mouse Button 4", "activation.button4"),
        ("Mouse Button 5", "activation.button5"),
        ("Double Middle Click", "activation.doubleMiddleClick")
    ]

    private let speedRange: ClosedRange<Double> = 0.2...3.0

    private var currentActivationLabel: String {
        let key = activationMethods.first { $0.raw == activationMethod }?.key ?? "activation.middleClick"
        return L10n.t(key)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer().frame(height: 21)
            speedCard
            Spacer().frame(height: Style.cardGap)
            activationCard
            Spacer().frame(height: Style.cardGap)
            togglesCard
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(.horizontal, Style.outerPadH)
        .padding(.top, 17)
        .padding(.bottom, 33)
        .frame(width: Style.windowWidth, height: Style.windowHeight)
        .background(Style.background)
    }

    // Centred icon + title, with the speed gauge pinned to the trailing edge.
    private var header: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 7) {
                AppIconTile()
                Text(L10n.t("settings.appName"))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(Style.primaryText)
            }
            .padding(.top, 4)

            HStack {
                Spacer()
                SpeedGauge(value: sensitivity, range: speedRange)
                    .padding(.trailing, 8)
            }
        }
    }

    private var speedCard: some View {
        Card(padV: 11) {
            VStack(alignment: .leading, spacing: 9) {
                CardLabel(text: L10n.t("settings.scrollSpeed"))

                HStack(spacing: 6) {
                    TickSlider(value: $sensitivity, range: speedRange, step: 0.1) {
                        NotificationCenter.default.post(name: NSNotification.Name("ScrollappSensitivityChanged"), object: nil)
                    }

                    Text(String(format: "%.1fx", sensitivity))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(Style.primaryText)
                        .frame(width: 40, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Style.recess)
                        )
                }
            }
        }
    }

    private var activationCard: some View {
        Card(padV: 8) {
            VStack(alignment: .leading, spacing: 9) {
                CardLabel(text: L10n.t("settings.activationMethod"))

                ZStack {
                    HStack(spacing: 0) {
                        Text(currentActivationLabel)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Style.primaryText)
                        Spacer(minLength: 4)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Style.glossyBlack)
                            .frame(width: 24, height: 24)
                            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
                            .overlay(
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    .padding(.leading, 13)
                    .padding(.trailing, 4)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Style.control)
                            .raised(radius: 16, darkBlur: 5, lightBlur: 4, offset: 2.5)
                    )

                    // Transparent AppKit overlay: SwiftUI's Menu styles discard the
                    // custom label on macOS, so drive a real NSMenu instead.
                    MenuTrigger(
                        items: activationMethods.map { (title: L10n.t($0.key), value: $0.raw) },
                        selected: activationMethod
                    ) { raw in
                        activationMethod = raw
                        NotificationCenter.default.post(name: NSNotification.Name("ScrollappActivationChanged"), object: nil)
                    }
                    .frame(height: 30)
                }
            }
        }
    }

    private var togglesCard: some View {
        Card(padV: 10) {
            VStack(alignment: .leading, spacing: 10) {
                CheckRow(title: L10n.t("settings.invertDirection"), isOn: $invertScroll) {
                    NotificationCenter.default.post(name: NSNotification.Name("ScrollappInvertChanged"), object: nil)
                }
                CheckRow(title: L10n.t("settings.leftClickNoInterrupt"), isOn: $leftClickNoInterrupt) {
                    NotificationCenter.default.post(name: NSNotification.Name("ScrollappLeftClickChanged"), object: nil)
                }
                CheckRow(title: L10n.t("settings.rightClickNoInterrupt"), isOn: $rightClickNoInterrupt) {
                    NotificationCenter.default.post(name: NSNotification.Name("ScrollappRightClickChanged"), object: nil)
                }
                CheckRow(title: L10n.t("settings.launchAtLogin"), isOn: $launchAtLogin) {
                    NotificationCenter.default.post(name: NSNotification.Name("ScrollappLaunchChanged"), object: nil)
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            PillButton(title: L10n.t("settings.about"), systemImage: "info.circle.fill", filledIcon: true) {
                let alert = NSAlert()
                alert.messageText = L10n.t("about.title")
                alert.informativeText = L10n.t("about.bodySettings")
                alert.alertStyle = .informational
                alert.addButton(withTitle: L10n.t("alert.ok"))
                alert.runModal()
            }
            Spacer(minLength: 0)
            PillButton(title: L10n.t("settings.quit"), systemImage: "rectangle.portrait.and.arrow.right", filledIcon: false) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 3)
    }
}
