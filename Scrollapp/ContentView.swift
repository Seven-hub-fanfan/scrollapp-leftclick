import SwiftUI

// MARK: - Design tokens

/// Palette / metrics for the neumorphic light UI (matches the design spec).
private enum Style {
    static let windowWidth: CGFloat = 360
    static let windowHeight: CGFloat = 624

    static let background = Color(red: 0.925, green: 0.925, blue: 0.929)
    static let card = Color(red: 0.965, green: 0.965, blue: 0.969)
    static let control = Color.white
    static let accent = Color(red: 0.086, green: 0.086, blue: 0.094)   // near-black
    static let primaryText = Color(red: 0.086, green: 0.086, blue: 0.094)
    static let secondaryText = Color(red: 0.45, green: 0.45, blue: 0.47)
    static let tick = Color(red: 0.78, green: 0.78, blue: 0.80)
    static let titleBar = Color(red: 0.957, green: 0.957, blue: 0.961)

    static let cardRadius: CGFloat = 20
    static let cardShadow = Color.black.opacity(0.06)
}

/// A white rounded card used as the section container.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Style.cardRadius, style: .continuous)
                    .fill(Style.card)
                    .shadow(color: Style.cardShadow, radius: 8, x: 0, y: 3)
            )
    }
}

// MARK: - Speed gauge

/// Circular progress ring showing the current scroll speed.
private struct SpeedGauge: View {
    let value: Double      // current sensitivity
    let range: ClosedRange<Double>

    private var progress: Double {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Style.control)
                .shadow(color: Style.cardShadow, radius: 6, x: 0, y: 3)

            // Track + progress: 3/4 ring with the gap centred at the bottom.
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Style.tick.opacity(0.35), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(6)

            Circle()
                .trim(from: 0, to: 0.75 * progress)
                .stroke(Style.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(6)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(String(format: "%.1f", value))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("x")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(Style.primaryText)

                Text(L10n.t("settings.scrollSpeed"))
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundColor(Style.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 11)
        }
        .frame(width: 78, height: 78)
    }
}

// MARK: - Ticked slider

/// Custom slider: rounded recessed track with tick marks and a pill knob.
private struct TickSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onChange: () -> Void

    private let knobWidth: CGFloat = 14
    private let knobHeight: CGFloat = 26
    private let tickCount = 29

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - knobWidth, 1)
            let fraction = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound)
                / (range.upperBound - range.lowerBound)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Style.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.04), lineWidth: 1)
                    )

                // Tick marks
                HStack(spacing: 0) {
                    ForEach(0..<tickCount, id: \.self) { index in
                        Rectangle()
                            .fill(Style.tick)
                            .frame(width: 1, height: index % 4 == 0 ? 11 : 7)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 6)

                // Knob
                Capsule()
                    .fill(Style.accent)
                    .frame(width: knobWidth, height: knobHeight)
                    .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
                    .offset(x: usable * fraction)
            }
            .frame(height: knobHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        update(x: drag.location.x - knobWidth / 2, usable: usable)
                    }
            )
        }
        .frame(height: 34)
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

/// Black rounded-square checkbox with a white check mark.
private struct CheckRow: View {
    let title: String
    @Binding var isOn: Bool
    let onChange: () -> Void

    var body: some View {
        Button {
            isOn.toggle()
            onChange()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isOn ? Style.accent : Style.control)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.black.opacity(isOn ? 0 : 0.06), lineWidth: 1)
                        )
                        .shadow(color: Style.cardShadow, radius: 3, x: 0, y: 2)

                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 28, height: 28)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
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
            HStack(spacing: 10) {
                if filledIcon {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Style.accent)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Style.primaryText)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Style.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Style.card)
                    .shadow(color: Style.cardShadow, radius: 6, x: 0, y: 3)
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
        VStack(spacing: 16) {
            header
            speedCard
            activationCard
            togglesCard
            Spacer(minLength: 0)
            bottomBar
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: Style.windowWidth, height: Style.windowHeight)
        .background(Style.background)
    }

    // App icon + title, with the speed gauge pinned to the trailing edge.
    private var header: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Style.accent)
                        .frame(width: 62, height: 62)
                        .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 4)
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }

                Text(L10n.t("settings.appName"))
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(Style.primaryText)
            }

            HStack {
                Spacer()
                SpeedGauge(value: sensitivity, range: speedRange)
            }
            .padding(.top, 4)
        }
    }

    private var speedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("settings.scrollSpeed"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Style.primaryText)

                HStack(spacing: 12) {
                    TickSlider(value: $sensitivity, range: speedRange, step: 0.1) {
                        NotificationCenter.default.post(name: NSNotification.Name("ScrollappSensitivityChanged"), object: nil)
                    }

                    Text(String(format: "%.1fx", sensitivity))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Style.primaryText)
                        .frame(width: 54, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Style.background)
                        )
                }
            }
        }
    }

    private var activationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("settings.activationMethod"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Style.primaryText)

                ZStack {
                    HStack {
                        Text(currentActivationLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Style.primaryText)
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Style.accent)
                                .frame(width: 30, height: 30)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Style.control)
                            .shadow(color: Style.cardShadow, radius: 4, x: 0, y: 2)
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
                }
            }
        }
    }

    private var togglesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
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
        HStack(spacing: 14) {
            PillButton(title: L10n.t("settings.about"), systemImage: "info.circle.fill", filledIcon: true) {
                let alert = NSAlert()
                alert.messageText = L10n.t("about.title")
                alert.informativeText = L10n.t("about.bodySettings")
                alert.alertStyle = .informational
                alert.addButton(withTitle: L10n.t("alert.ok"))
                alert.runModal()
            }
            PillButton(title: L10n.t("settings.quit"), systemImage: "rectangle.portrait.and.arrow.right", filledIcon: false) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
