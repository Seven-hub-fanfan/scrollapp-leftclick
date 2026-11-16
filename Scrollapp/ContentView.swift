import SwiftUI
import AppKit

private struct CheckRow: View {
    let title: String
    @Binding var isOn: Bool
    var tint: Color = Style.accent
    var activeThumb: Color = Style.actionText
    let onChange: () -> Void
    var body: some View {
        Button {
            isOn.toggle()
            onChange()
        } label: {
            HStack(spacing: 12) {
                Text(title).font(.system(size: 11.5)).foregroundStyle(Style.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Capsule().fill(isOn ? tint : Style.control)
                    .overlay(Capsule().strokeBorder(Style.line, lineWidth: 1))
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(isOn ? activeThumb : Style.secondaryText)
                            .frame(width: 12, height: 12).padding(3)
                    }
                    .frame(width: 30, height: 18)
            }
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(title, isOn: Binding(get: { isOn }, set: { isOn = $0; onChange() }))
        }
    }
}

/// Native menus preserve keyboard navigation and the persisted English IDs.
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
        private var selected = ""
        private var onSelect: ((String) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        func configure(items: [(title: String, value: String)], selected: String,
                       onSelect: @escaping (String) -> Void) {
            self.items = items; self.selected = selected; self.onSelect = onSelect
            setAccessibilityElement(true)
            setAccessibilityRole(.popUpButton)
            setAccessibilityLabel(L10n.t("settings.activationMethod"))
            setAccessibilityValue(items.first { $0.value == selected }?.title ?? "")
        }
        override func mouseDown(with event: NSEvent) { showMenu() }
        override func accessibilityPerformPress() -> Bool { showMenu(); return true }
        private func showMenu() {
            let menu = NSMenu()
            for (index, item) in items.enumerated() {
                let menuItem = NSMenuItem(title: item.title, action: #selector(pick(_:)), keyEquivalent: "")
                menuItem.target = self; menuItem.tag = index
                menuItem.state = item.value == selected ? .on : .off
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

struct ContentView: View {
    @ObservedObject private var skins = CursorSkinStore.shared
    @AppStorage("scrollSensitivity") private var sensitivity: Double = 1.0
    @AppStorage("invertScrollDirection") private var invertScroll = false
    @AppStorage("leftClickDoesNotInterrupt") private var leftClickNoInterrupt = false
    @AppStorage("rightClickDoesNotInterrupt") private var rightClickNoInterrupt = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("activationMethod") private var activationMethod = "Double Middle Click"
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
        L10n.t(activationMethods.first { $0.raw == activationMethod }?.key ?? "activation.doubleMiddleClick")
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    PageHeading(title: L10n.t("settings.general"), subtitle: L10n.t("settings.generalIntro"))
                    gaugesCard
                    adjustmentCard
                    activationCard
                    togglesCard
                }
                .padding(.horizontal, Style.outerPadH).padding(.top, 38).padding(.bottom, 12)
            }
            .scrollIndicators(.visible)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gaugesCard: some View {
        Card(padV: 8) {
            HStack(spacing: 0) {
                gaugeColumn(title: L10n.t("settings.scrollSpeed"), value: sensitivity,
                            range: speedRange, step: 0.1, unit: "×")
                Rectangle().fill(Style.line).frame(width: 1, height: 64)
                gaugeColumn(title: L10n.t("settings.cursorSize"), value: skins.cursorScale,
                            range: CursorSizing.range, step: CursorSizing.step, unit: "×")
                    .opacity(skins.needsRecovery ? 0.38 : 1)
                Rectangle().fill(Style.line).frame(width: 1, height: 64)
                gaugeColumn(title: L10n.t("settings.clickMarkerSize"), value: skins.clickMarkerSize,
                            range: CursorMarkerSizing.range, step: 1, unit: "pt")
                    .opacity(skins.needsRecovery || !skins.clickMarkerEnabled ? 0.38 : 1)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func gaugeColumn(title: String, value: Double, range: ClosedRange<Double>,
                             step: Double, unit: String) -> some View {
        VStack(spacing: 6) {
            CircularSliderGauge(value: value, range: range, step: step, unit: unit)
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Style.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var adjustmentCard: some View {
        Card(padV: 12) {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 0) {
                    adjustmentColumn(title: L10n.t("settings.scrollSpeed"),
                                     value: $sensitivity, range: speedRange, step: 0.1,
                                     unit: "×", markers: [0.2, 1, 2, 3], identifier: "scroll.speed") {
                        notify("ScrollappSensitivityChanged")
                    }
                    columnDivider
                    adjustmentColumn(title: L10n.t("settings.cursorSize"),
                                     value: Binding(get: { skins.cursorScale },
                                                    set: { skins.setCursorScale($0) }),
                                     range: CursorSizing.range, step: CursorSizing.step,
                                     unit: "×", markers: [0.5, 2, 4, 6, 8], identifier: "cursor.size") {}
                        .disabled(skins.needsRecovery).opacity(skins.needsRecovery ? 0.38 : 1)
                    columnDivider
                    adjustmentColumn(title: L10n.t("settings.clickMarkerSize"),
                                     value: Binding(get: { skins.clickMarkerSize },
                                                    set: { skins.setClickMarkerSize($0) }),
                                     range: CursorMarkerSizing.range, step: 1,
                                     unit: "pt", markers: [3, 6, 9, 12, 16], identifier: "cursor.marker.size") {}
                        .disabled(skins.needsRecovery || !skins.clickMarkerEnabled)
                        .opacity(skins.needsRecovery || !skins.clickMarkerEnabled ? 0.38 : 1)
                }
                if let error = skins.errorKey {
                    Text(L10n.t("skins.error.\(error)")).font(.system(size: 10)).foregroundStyle(Style.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var columnDivider: some View {
        Rectangle().fill(Style.line).frame(width: 1, height: 144)
    }

    private func adjustmentColumn(title: String, value: Binding<Double>, range: ClosedRange<Double>,
                                  step: Double, unit: String, markers: [Double], identifier: String,
                                  onChange: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            ZStack {
                ChannelReadout(value: value.wrappedValue, range: range, step: step,
                               unit: unit, markers: markers)
                VerticalChannelSlider(value: value, range: range, step: step, label: title,
                                      unit: unit, onChange: onChange)
                    .accessibilityIdentifier(identifier)
            }
            .frame(width: ChannelReadout.width, height: VerticalChannelSlider.height)
            Text(String(format: step >= 1 ? "%.0f–%.0f %@" : "%.1f–%.1f%@", range.lowerBound, range.upperBound, unit))
                .font(.system(size: 9)).monospacedDigit().foregroundStyle(Style.secondaryText)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var activationCard: some View {
        Card(padV: 12) {
            HStack(spacing: 20) {
              HStack(spacing: 14) {
                CardLabel(text: L10n.t("settings.activationMethod"))
                ZStack {
                    HStack {
                        Text(currentActivationLabel).font(.system(size: 11.5, weight: .medium))
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Style.secondaryText)
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Style.recess, in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
                    MenuTrigger(items: activationMethods.map { (L10n.t($0.key), $0.raw) },
                                selected: activationMethod) { raw in
                        activationMethod = raw
                        notify("ScrollappActivationChanged")
                    }
                    .frame(height: 28)
                }
                .frame(maxWidth: .infinity)
                .help(L10n.t("settings.activationIntro"))
              }
              .frame(maxWidth: .infinity)
                Rectangle().fill(Style.line).frame(width: 1, height: 24)
                HStack(spacing: 9) {
                    Circle().fill(Color(red: 0.94, green: 0.08, blue: 0.12))
                        .frame(width: 6, height: 6).accessibilityHidden(true)
                    CheckRow(title: L10n.t("settings.clickMarker"),
                             isOn: Binding(get: { skins.clickMarkerEnabled },
                                           set: { skins.setClickMarkerEnabled($0) }),
                             tint: Style.danger, activeThumb: .white) {}
                        .accessibilityIdentifier("cursor.marker.enabled")
                }
                .frame(maxWidth: .infinity).disabled(skins.needsRecovery).opacity(skins.needsRecovery ? 0.38 : 1)
            }
        }
    }

    private var togglesCard: some View {
        Card(padV: 12) {
            VStack(alignment: .leading, spacing: 13) {
                CardLabel(text: L10n.t("settings.behavior"))
                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 13) {
                        CheckRow(title: L10n.t("settings.invertDirection"), isOn: $invertScroll) {
                            notify("ScrollappInvertChanged")
                        }
                        CheckRow(title: L10n.t("settings.launchAtLogin"), isOn: $launchAtLogin) {
                            notify("ScrollappLaunchChanged")
                        }
                    }
                    Rectangle().fill(Style.line).frame(width: 1, height: 61)
                    VStack(spacing: 13) {
                        CheckRow(title: L10n.t("settings.leftClickNoInterrupt"), isOn: $leftClickNoInterrupt) {
                            notify("ScrollappLeftClickChanged")
                        }
                        CheckRow(title: L10n.t("settings.rightClickNoInterrupt"), isOn: $rightClickNoInterrupt) {
                            notify("ScrollappRightClickChanged")
                        }
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Style.line).frame(height: 1)
            HStack(spacing: 12) {
                Text("Scrollapp").font(.system(size: 10, weight: .medium))
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    .font(.system(size: 10)).foregroundStyle(Style.secondaryText)
                Spacer()
                Button { AboutPanelController.shared.show(body: L10n.t("about.bodySettings")) } label: {
                    Label(L10n.t("settings.about"), systemImage: "info.circle")
                }
                .buttonStyle(GlassButtonStyle(kind: .quiet))
                Button { NSApplication.shared.terminate(nil) } label: {
                    Label(L10n.t("settings.quit"), systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(GlassButtonStyle())
            }
            .padding(.horizontal, Style.outerPadH).padding(.vertical, 16)
        }
    }
    private func notify(_ name: String) {
        NotificationCenter.default.post(name: NSNotification.Name(name), object: nil)
    }
}
