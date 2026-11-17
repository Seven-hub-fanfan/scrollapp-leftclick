import SwiftUI
import AppKit

struct ShortcutSettingsView: View {
    @ObservedObject private var engine = ShortcutEngine.shared
    @ObservedObject private var permissions = PermissionStore.shared
    @ObservedObject private var shield = ShortcutInputShield.shared
    @State private var recordingID: UUID?
    private var sequence: ShortcutSequence { engine.sequence }
    private var adding: Bool { recordingID != nil && !sequence.steps.contains { $0.id == recordingID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: L10n.t("settings.shortcuts"), subtitle: L10n.t("shortcuts.intro"))
            VStack(spacing: 12) {
              HStack(spacing: 12) {
                Image(systemName: "computermouse").font(.system(size: 19)).foregroundStyle(Style.focus)
                    .frame(width: 36, height: 36).background(Style.control, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("shortcuts.enable")).font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("shortcuts.trigger.\(sequence.trigger.rawValue)"))
                        .font(.system(size: 11)).foregroundStyle(Style.secondaryText)
                }
                Spacer()
                Toggle(L10n.t("shortcuts.enable"), isOn: Binding(
                    get: { sequence.isEnabled }, set: { engine.setEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).disabled(sequence.steps.isEmpty)
                    .accessibilityIdentifier("shortcuts.enabled")
              }
              Rectangle().fill(Style.line).frame(height: 1)
              HStack(spacing: 14) {
                  Text(L10n.t("shortcuts.triggerLabel")).font(.system(size: 11))
                      .foregroundStyle(Style.secondaryText)
                  Picker(L10n.t("shortcuts.triggerLabel"), selection: Binding(
                      get: { sequence.trigger }, set: { endRecording(); engine.setTrigger($0) })) {
                      ForEach(ShortcutTrigger.allCases, id: \.self) { trigger in
                          Text(L10n.t("shortcuts.button.\(trigger.rawValue)")).tag(trigger)
                      }
                  }
                  .pickerStyle(.segmented).labelsHidden().frame(width: 214)
                  .accessibilityIdentifier("shortcuts.trigger")
                  Spacer()
                  Image(systemName: "shield.lefthalf.filled")
                      .foregroundStyle(shield.isActive ? Style.success : Style.secondaryText)
                  Text(L10n.t(shield.isActive ? "shortcuts.isolated" : "shortcuts.isolationOnFocus"))
                      .font(.system(size: 10)).foregroundStyle(Style.secondaryText)
              }
            }
            .padding(16).background(Style.card, in: RoundedRectangle(cornerRadius: Style.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Style.cardRadius).strokeBorder(Style.line))

            progress

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.t("shortcuts.sequence")).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(sequence.steps.count) / \(ShortcutSequence.limit)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Style.secondaryText)
                }
                if sequence.steps.isEmpty && !adding {
                    VStack(spacing: 10) {
                        Image(systemName: "command").font(.system(size: 26, weight: .light))
                        Text(L10n.t("shortcuts.empty")).font(.system(size: 12))
                    }
                    .foregroundStyle(Style.secondaryText).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(sequence.steps.enumerated()), id: \.element.id) { index, step in
                                stepRow(index, step: step)
                            }
                        }
                        .padding(1)
                    }
                    .accessibilityIdentifier("shortcuts.sequence.scroll")
                }
                Button { beginRecording(UUID()) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: adding ? "keyboard" : "plus")
                        Text(L10n.t(adding ? "shortcuts.recording" : "shortcuts.add"))
                        Spacer()
                        if adding {
                            Text(L10n.t("shortcuts.escape")).font(.system(size: 10))
                        }
                    }
                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 14)
                    .frame(height: 42).contentShape(Rectangle())
                    .foregroundStyle(adding ? Style.focus : Style.primaryText)
                    .background(adding ? Style.focus.opacity(0.10) : Style.control,
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(adding ? Style.focus.opacity(0.5) : Style.line))
                }
                .buttonStyle(.plain)
                .disabled(sequence.steps.count >= ShortcutSequence.limit || !permissions.accessibility)
                .accessibilityIdentifier("shortcuts.add")
                if recordingID != nil {
                    Button(L10n.t("action.cancel")) { endRecording() }
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Style.secondaryText)
                        .accessibilityIdentifier("shortcuts.cancel")
                }
            }
            .padding(16).frame(maxHeight: .infinity)
            .background(Style.card, in: RoundedRectangle(cornerRadius: Style.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Style.cardRadius).strokeBorder(Style.line))

            HStack(spacing: 7) {
                if !permissions.accessibility {
                    Image(systemName: "lock.shield").foregroundStyle(Style.error)
                    Button(L10n.t("shortcuts.permission")) { PermissionStore.shared.requestAccessibility() }
                        .buttonStyle(.plain).foregroundStyle(Style.error)
                        .accessibilityIdentifier("shortcuts.permission")
                } else if let issue = shield.error ?? engine.issue {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Style.error)
                    Text(L10n.t(issue)).foregroundStyle(Style.error)
                } else {
                    Image(systemName: "info.circle").foregroundStyle(Style.secondaryText)
                    Text(L10n.t("shortcuts.footer")).foregroundStyle(Style.secondaryText)
                }
                Spacer()
            }
            .font(.system(size: 11)).frame(minHeight: 20)
        }
        .padding(.horizontal, Style.outerPadH).padding(.top, 48).padding(.bottom, 20)
        .background(ShortcutCapture(isRecording: recordingID != nil, captured: capture, cancelled: endRecording)
            .frame(width: 0, height: 0))
        .onDisappear { endRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            endRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ScrollappShortcutRecordingCancelled"))) { _ in
            endRecording()
        }
    }

    private var progress: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Style.line, lineWidth: 3)
                Circle().trim(from: 0, to: sequence.steps.isEmpty ? 0 :
                    CGFloat(sequence.position) / CGFloat(sequence.steps.count))
                    .stroke(Style.focus, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(sequence.steps.isEmpty ? "—" : sequence.next == nil ? "✓" : "\(sequence.position + 1)")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
            }
            .frame(width: 44, height: 44).foregroundStyle(Style.focus)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(sequence.steps.isEmpty ? "shortcuts.ready" :
                    sequence.next == nil ? "shortcuts.completed" :
                        sequence.isLooping ? "shortcuts.loopNext" : "shortcuts.next",
                    sequence.position + 1, sequence.steps.count))
                    .font(.system(size: 11)).foregroundStyle(Style.secondaryText)
                    .accessibilityIdentifier("shortcuts.progress")
                if let step = sequence.next {
                    keycaps(step.chord)
                } else {
                    Text(L10n.t(sequence.steps.isEmpty ? "shortcuts.addHint" : "shortcuts.completedHint"))
                        .font(.system(size: 12, weight: .medium))
                }
            }
            Spacer(minLength: 8)
            Button { endRecording(); engine.setLooping(!sequence.isLooping) } label: {
                Label(L10n.t("shortcuts.loop"), systemImage: "repeat")
            }
            .buttonStyle(GlassButtonStyle(kind: sequence.isLooping ? .primary : .quiet))
            .help(L10n.t("shortcuts.loopHelp"))
            .accessibilityIdentifier("shortcuts.loop")
            .accessibilityValue(L10n.t(sequence.isLooping ? "shortcuts.loopOn" : "shortcuts.loopOff"))
            Button { endRecording(); engine.back() } label: {
                Label(L10n.t("shortcuts.back"), systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(GlassButtonStyle(kind: .quiet))
            .disabled(sequence.steps.isEmpty || (sequence.position == 0 && !sequence.isLooping))
            .help(L10n.t("shortcuts.backHelp")).accessibilityIdentifier("shortcuts.back")
            Button { endRecording(); engine.reset() } label: {
                Label(L10n.t("shortcuts.reset"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(GlassButtonStyle(kind: .quiet)).disabled(sequence.position == 0)
            .accessibilityIdentifier("shortcuts.reset")
        }
        .padding(16).frame(height: 94)
        .background(Style.card, in: RoundedRectangle(cornerRadius: Style.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Style.cardRadius).strokeBorder(Style.line))
    }

    private func stepRow(_ index: Int, step: ShortcutStep) -> some View {
        let current = sequence.position == index
        let capturing = recordingID == step.id
        return HStack(spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(current ? Style.focus : Style.secondaryText).frame(width: 25)
            Button { beginRecording(step.id) } label: {
                HStack {
                    if capturing {
                        Text(L10n.t("shortcuts.recording")).font(.system(size: 12)).foregroundStyle(Style.focus)
                    } else {
                        keycaps(step.chord)
                    }
                    Spacer()
                    Image(systemName: "keyboard").font(.system(size: 11)).foregroundStyle(Style.secondaryText)
                }
                .frame(maxWidth: .infinity).frame(height: 46).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!permissions.accessibility)
            .accessibilityLabel(L10n.t("shortcuts.edit", index + 1, ShortcutKeyNames.display(step.chord)))
            .accessibilityIdentifier("shortcuts.edit.\(index)")
            Picker(L10n.t("shortcuts.scope"), selection: Binding(
                get: { step.scope }, set: { endRecording(); engine.setScope($0, for: step.id) })) {
                ForEach(ShortcutScope.allCases, id: \.self) { scope in
                    Text(L10n.t("shortcuts.scope.\(scope.rawValue)")).tag(scope)
                }
            }
            .pickerStyle(.menu).labelsHidden().frame(width: 124)
            .help(L10n.t("shortcuts.scopeHelp"))
            .accessibilityIdentifier("shortcuts.scope.\(index)")
            HStack(spacing: 0) {
                rowAction("arrow.up", label: L10n.t("shortcuts.moveUp"), id: "up.\(index)",
                    disabled: index == 0) { endRecording(); engine.move(step.id, by: -1) }
                rowAction("arrow.down", label: L10n.t("shortcuts.moveDown"), id: "down.\(index)",
                    disabled: index == sequence.steps.count - 1) { endRecording(); engine.move(step.id, by: 1) }
                rowAction("trash", label: L10n.t("shortcuts.remove"), id: "remove.\(index)",
                    color: Style.danger) { endRecording(); engine.remove(step.id) }
            }
        }
        .padding(.horizontal, 12)
        .background(current || capturing ? Style.focus.opacity(0.08) : Style.control,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(current || capturing ? Style.focus.opacity(0.3) : .clear))
    }

    private func keycaps(_ chord: ShortcutChord) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(ShortcutKeyNames.parts(chord).enumerated()), id: \.offset) { _, name in
                Text(name).font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 7).frame(minWidth: 24).frame(height: 24)
                    .background(Style.recess, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Style.line))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ShortcutKeyNames.display(chord))
    }

    private func rowAction(_ icon: String, label: String, id: String, disabled: Bool = false,
                           color: Color = Style.secondaryText, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12))
                .foregroundStyle(color.opacity(disabled ? 0.3 : 1))
                .frame(width: 34, height: 42).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(disabled).help(label).accessibilityLabel(label)
        .accessibilityIdentifier("shortcuts.\(id)")
    }

    private func beginRecording(_ id: UUID) {
        shield.refresh()
        guard shield.isActive else { return }
        if recordingID == id { endRecording(); return }
        recordingID = id
        engine.setRecording(true)
    }
    private func endRecording() {
        guard recordingID != nil else { return }
        recordingID = nil
        engine.setRecording(false)
    }
    private func capture(_ chord: ShortcutChord) {
        guard let id = recordingID else { return }
        if sequence.steps.contains(where: { $0.id == id }) { engine.replace(id, with: chord) }
        else { engine.add(chord) }
        endRecording()
    }
}

/// The shield follows this page's actual window and focus, including while
/// browsing or editing the sequence without an active recorder.
private struct ShortcutCapture: NSViewRepresentable {
    var isRecording: Bool
    var captured: (ShortcutChord) -> Void
    var cancelled: () -> Void
    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.captured = captured
        view.cancelled = cancelled
        view.recording = isRecording
        view.updateShield()
    }
    static func dismantleNSView(_ view: CaptureView, coordinator: ()) {
        ShortcutInputShield.shared.detach(from: view.window)
    }

    final class CaptureView: NSView {
        var captured: ((ShortcutChord) -> Void)?
        var cancelled: (() -> Void)?
        var recording = false
        func updateShield() {
            ShortcutInputShield.shared.configure(window: window, recording: recording,
                captured: { [weak self] in self?.captured?($0) },
                cancelled: { [weak self] in self?.cancelled?() })
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateShield()
        }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { ShortcutInputShield.shared.detach(from: window) }
            super.viewWillMove(toWindow: newWindow)
        }
    }
}
