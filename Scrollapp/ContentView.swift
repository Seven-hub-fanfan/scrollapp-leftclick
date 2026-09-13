import SwiftUI

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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.and.down.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text(L10n.t("settings.appName"))
                    .font(.title3)
                    .fontWeight(.bold)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Scroll Speed
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("settings.scrollSpeed"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack {
                    Slider(value: $sensitivity, in: 0.2...3.0, step: 0.1)
                        .onChange(of: sensitivity) { _ in
                            NotificationCenter.default.post(name: NSNotification.Name("ScrollappSensitivityChanged"), object: nil)
                        }
                    Text(String(format: "%.1fx", sensitivity))
                        .monospacedDigit()
                        .frame(width: 38)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider().padding(.horizontal)

            // Activation Method
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("settings.activationMethod"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Picker("", selection: $activationMethod) {
                    ForEach(activationMethods, id: \.raw) { method in
                        Text(L10n.t(method.key)).tag(method.raw)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: activationMethod) { _ in
                    NotificationCenter.default.post(name: NSNotification.Name("ScrollappActivationChanged"), object: nil)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider().padding(.horizontal)

            // Toggles
            VStack(spacing: 2) {
                Toggle(L10n.t("settings.invertDirection"), isOn: $invertScroll)
                    .onChange(of: invertScroll) { _ in
                        NotificationCenter.default.post(name: NSNotification.Name("ScrollappInvertChanged"), object: nil)
                    }
                Toggle(L10n.t("settings.leftClickNoInterrupt"), isOn: $leftClickNoInterrupt)
                    .onChange(of: leftClickNoInterrupt) { _ in
                        NotificationCenter.default.post(name: NSNotification.Name("ScrollappLeftClickChanged"), object: nil)
                    }
                Toggle(L10n.t("settings.rightClickNoInterrupt"), isOn: $rightClickNoInterrupt)
                    .onChange(of: rightClickNoInterrupt) { _ in
                        NotificationCenter.default.post(name: NSNotification.Name("ScrollappRightClickChanged"), object: nil)
                    }
                Toggle(L10n.t("settings.launchAtLogin"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _ in
                        NotificationCenter.default.post(name: NSNotification.Name("ScrollappLaunchChanged"), object: nil)
                    }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // Bottom buttons
            HStack {
                Button(L10n.t("settings.about")) {
                    let alert = NSAlert()
                    alert.messageText = L10n.t("about.title")
                    alert.informativeText = L10n.t("about.bodySettings")
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: L10n.t("alert.ok"))
                    alert.runModal()
                }
                Spacer()
                Button(L10n.t("settings.quit")) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .frame(width: 340, height: 470)
    }
}
