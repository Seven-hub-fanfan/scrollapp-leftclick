// Built by verify_global_shortcuts.py with the actual ShortcutEngine sources.
import AppKit
import ApplicationServices
import Carbon

private func writeJSON(_ value: [String: Any], to path: String) {
    do {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: path), options: .atomic)
    } catch {
        fputs("Cannot write fixture state: \(error)\n", stderr)
        exit(1)
    }
}

private final class MemoryDefaults: UserDefaults {
    private var storage: [String: Data] = [:]
    override func data(forKey key: String) -> Data? { storage[key] }
    override func set(_ value: Any?, forKey key: String) { storage[key] = value as? Data }
}

private final class KeySink: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
}

private final class Receiver: NSObject, NSApplicationDelegate {
    static var active: Receiver?
    let output: String
    var window: NSWindow!
    var monitor: Any?
    var handler: EventHandlerRef?
    var hotkeys: [EventHotKeyRef] = []
    var events: [[String: Any]] = []
    var registrations: [Int32] = []

    init(output: String) { self.output = output }

    func save() {
        writeJSON([
            "pid": ProcessInfo.processInfo.processIdentifier,
            "registrations": registrations,
            "ready": registrations.count == 4 && registrations.allSatisfy { $0 == noErr },
            "hotkeyMode": GetSymbolicHotKeyMode(),
            "events": events
        ], to: output)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.active = self
        window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 640, height: 320),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Scrollapp · Global Shortcut Verification"
        let sink = KeySink(frame: window.contentView!.bounds)
        window.contentView = sink
        let label = NSTextField(labelWithString:
            "独立热键接收窗口\n测试专用 F18 / F19 / P，不使用剪贴板或正式槽位")
        label.frame = NSRect(x: 30, y: 120, width: 580, height: 70)
        label.font = .systemFont(ofSize: 18)
        sink.addSubview(label)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(sink)
        NSApp.activate(ignoringOtherApps: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == SystemShortcutDelivery.syntheticTag {
                self?.events.append([
                    "kind": "local", "type": event.type.rawValue,
                    "key": Int(event.keyCode),
                    "rawFlags": event.modifierFlags.rawValue,
                    "modifiers": ShortcutModifiers(event.modifierFlags).rawValue
                ])
                self?.save()
            }
            return event
        }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event, let receiver = Receiver.active else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else {
                receiver.events.append(["kind": "handlerError", "status": result])
                receiver.save()
                return result
            }
            receiver.events.append([
                "kind": "carbon", "id": Int(id.id),
                "down": GetEventKind(event) == UInt32(kEventHotKeyPressed)
            ])
            receiver.save()
            return noErr
        }, types.count, &types, nil, &handler)
        guard status == noErr else {
            writeJSON(["ready": false, "handlerError": status], to: output)
            NSApp.terminate(nil)
            return
        }
        for (index, pair) in [
            (UInt32(79), UInt32(controlKey | optionKey | cmdKey)),
            (UInt32(80), UInt32(controlKey | optionKey | shiftKey | cmdKey)),
            (UInt32(35), UInt32(optionKey)),
            (UInt32(35), UInt32(controlKey | optionKey | cmdKey))
        ].enumerated() {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x53435453, id: UInt32(index + 1))
            registrations.append(RegisterEventHotKey(pair.0, pair.1, id,
                GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference))
            if let reference { hotkeys.append(reference) }
        }
        save()
    }

    func applicationWillTerminate(_ notification: Notification) {
        for reference in hotkeys { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

@main
private struct VerifyGlobalShortcuts {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let role = args.first else { exit(2) }
        if role == "--frontmost" {
            print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
            return
        }
        if role == "--receiver", args.count == 2 {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let receiver = Receiver(output: args[1])
            app.delegate = receiver
            withExtendedLifetime(receiver) { app.run() }
            return
        }
        guard role == "--send", args.count == 8,
              let pid = Int32(args[1]), let scope = ShortcutScope(rawValue: args[2]),
              let key = UInt16(args[3]), let modifiers = UInt32(args[4]),
              let count = Int(args[5]), let cancelAt = Int(args[6]), (1...50).contains(count)
        else { fputs("Invalid fixture arguments\n", stderr); exit(2) }
        let output = args[7]
        let delivery = SystemShortcutDelivery()
        let access: [String: Any] = [
            "authorized": delivery.isAuthorized, "postAccess": CGPreflightPostEventAccess(),
            "hotkeyMode": GetSymbolicHotKeyMode(),
            "secureInput": delivery.isSecureInput
        ]
        guard delivery.isAuthorized, !delivery.isSecureInput else {
            writeJSON(access.merging(["blocked": true]) { _, new in new }, to: output)
            exit(3)
        }
        let chord = ShortcutChord(keyCode: key, modifiers: .init(rawValue: modifiers))
        var checkedDelivery = delivery
        var focusChecks = 0
        checkedDelivery.foregroundPID = {
            focusChecks += 1
            if cancelAt > 0 && focusChecks >= cancelAt { return nil }
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        let engine = ShortcutEngine(defaults: MemoryDefaults(), delivery: checkedDelivery)
        engine.add(chord)
        engine.setScope(scope, for: engine.sequence.steps[0].id)
        engine.setLooping(true)
        engine.setEnabled(true)
        var submitted = 0
        for index in 0..<count {
            engine.executeClick(to: pid)
            if engine.issue == nil { submitted += 1 }
            else { break }
            // Separate clicks at 40 Hz, allowing WindowServer to consume the
            // prior chord. Do not bypass production modifier checks or delay
            // any individual key-down/key-up within a chord.
            if index + 1 < count { RunLoop.current.run(until: Date().addingTimeInterval(0.025)) }
        }
        // Wait only for event delivery/readback, never between production events.
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        let flags = ShortcutModifiers(NSEvent.modifierFlags).rawValue
        writeJSON(access.merging([
            "blocked": false, "submitted": submitted, "scope": scope.rawValue,
            "focusChecks": focusChecks, "modifiersAfter": flags,
            "position": engine.sequence.position, "issue": engine.issue as Any? ?? NSNull()
        ]) { _, new in new }, to: output)
    }
}
