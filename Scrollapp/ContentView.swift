import SwiftUI

struct ContentView: View {
    @AppStorage("scrollSensitivity") private var sensitivity: Double = 1.0
    @AppStorage("invertScrollDirection") private var invertScroll = false
    @AppStorage("leftClickDoesNotInterrupt") private var leftClickNoInterrupt = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("activationMethod") private var activationMethod = "Middle Click"

    private let activationMethods = [
        "Middle Click",
        "Shift + Middle Click",
        "Cmd + Middle Click",
        "Option + Middle Click",
        "Mouse Button 4",
        "Mouse Button 5",
        "Double Middle Click"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.and.down.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Scrollapp")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Scroll Speed
            VStack(alignment: .leading, spacing: 6) {
                Text("Scroll Speed")
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack {
                    Slider(value: $sensitivity, in: 0.2...3.0, step: 0.1)
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
                Text("Activation Method")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Picker("", selection: $activationMethod) {
                    ForEach(activationMethods, id: \.self) { method in
                        Text(method).tag(method)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider().padding(.horizontal)

            // Toggles
            VStack(spacing: 2) {
                Toggle("Invert Scrolling Direction", isOn: $invertScroll)
                Toggle("Left Click Does Not Interrupt Scrolling", isOn: $leftClickNoInterrupt)
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // Bottom buttons
            HStack {
                Button("About") {
                    let alert = NSAlert()
                    alert.messageText = "About Scrollapp"
                    alert.informativeText = "Windows-style auto-scrolling for macOS.\n\nActivate with your configured mouse button, then move the cursor to control scrolling speed and direction.\n\nRight-click or middle-click to exit."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .frame(width: 340, height: 440)
    }
}
