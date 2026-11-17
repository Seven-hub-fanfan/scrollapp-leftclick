import AppKit
import ApplicationServices
import Carbon
import Combine

extension ShortcutModifiers {
    static var physicalState: Self {
        Self(NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.hidSystemState).rawValue)))
    }
    init(_ flags: NSEvent.ModifierFlags) {
        var result: Self = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }

    var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}

enum ShortcutKeyNames {
    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 71: "Clear",
        76: "⌤", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "↖",
        116: "⇞", 117: "⌦", 118: "F4", 119: "↘", 120: "F2", 121: "⇟",
        122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
        64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]

    static func key(_ keyCode: UInt16) -> String {
        if keyCode == 49 { return L10n.t("shortcuts.space") }
        if let name = special[keyCode] { return name }
        // Resolve the physical key against the user's current keyboard layout.
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data))
                .assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKey: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKey, characters.count, &length, &characters)
            if status == noErr, length > 0 {
                return String(utf16CodeUnits: characters, count: length).uppercased()
            }
        }
        return L10n.t("shortcuts.keyCode", Int(keyCode))
    }

    static func parts(_ chord: ShortcutChord) -> [String] {
        var names: [String] = []
        for (flag, name) in [(ShortcutModifiers.control, "⌃"), (.option, "⌥"),
                              (.shift, "⇧"), (.command, "⌘")] where chord.modifiers.contains(flag) {
            names.append(name)
        }
        return names + [key(chord.keyCode)]
    }

    static func display(_ chord: ShortcutChord) -> String { parts(chord).joined(separator: " ") }
}

protocol ShortcutDelivery {
    var isAuthorized: Bool { get }
    var isSecureInput: Bool { get }
    /// True means the main key-down was submitted, not that the receiver acted.
    func send(_ chord: ShortcutChord, scope: ShortcutScope, to pid: pid_t) -> Bool
}

struct SystemShortcutDelivery: ShortcutDelivery {
    static let syntheticTag: Int64 = 0x53434B455953
    private static let functionKeys: Set<CGKeyCode> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90
    ]
    var isAuthorized: Bool { AXIsProcessTrusted() }
    var isSecureInput: Bool { IsSecureEventInputEnabled() }
    var foregroundPID: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    var currentModifiers: () -> ShortcutModifiers = { .physicalState }

    func send(_ chord: ShortcutChord, scope: ShortcutScope, to pid: pid_t) -> Bool {
        guard isAuthorized, !isSecureInput, currentModifiers().isEmpty,
              pid > 0, pid != ProcessInfo.processInfo.processIdentifier, foregroundPID() == pid,
              chord.isValid, let source = CGEventSource(stateID: .privateState) else { return false }
        source.localEventsSuppressionInterval = 0
        var events: [CGEvent] = []
        var held: ShortcutModifiers = []
        let modifierKeys: [(ShortcutModifiers, CGKeyCode)] = [
            (.control, 59), (.option, 58), (.shift, 56), (.command, 55)
        ]
        func append(_ key: CGKeyCode, down: Bool, flags: ShortcutModifiers) -> Bool {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            else { return false }
            event.flags = flags.eventFlags
            // Carbon dispatch expects the same Fn marker as hardware F1–F20.
            if Self.functionKeys.contains(key) { event.flags.insert(.maskSecondaryFn) }
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            events.append(event)
            return true
        }
        for (modifier, key) in modifierKeys where chord.modifiers.contains(modifier) {
            held.insert(modifier)
            guard append(key, down: true, flags: held) else { return false }
        }
        guard append(chord.keyCode, down: true, flags: held),
              append(chord.keyCode, down: false, flags: held) else { return false }
        for (modifier, key) in modifierKeys.reversed() where held.contains(modifier) {
            held.remove(modifier)
            guard append(key, down: false, flags: held) else { return false }
        }
        if scope == .application {
            for event in events { event.postToPid(pid) }
            return true
        }
        // HID input passes through macOS global hotkey dispatch. Never also send
        // to the PID: a receiver could otherwise run the same action twice.
        let modifierCount = chord.modifiers.rawValue.nonzeroBitCount
        var pressedCount = 0
        var pressed: ShortcutModifiers = []
        let usedModifiers = modifierKeys.filter { chord.modifiers.contains($0.0) }
        func releaseModifiers() {
            for index in (0..<pressedCount).reversed() {
                pressed.remove(usedModifiers[index].0)
                let event = events[events.count - 1 - index]
                event.flags = pressed.eventFlags
                event.post(tap: .cghidEventTap)
            }
        }
        for index in 0...modifierCount {
            // Once main key-down is submitted we must finish key-up/cleanup even
            // if focus changes, and report submitted to avoid a duplicate retry.
            guard foregroundPID() == pid else { releaseModifiers(); return false }
            events[index].post(tap: .cghidEventTap)
            if index < modifierCount {
                pressed.insert(usedModifiers[index].0)
                pressedCount += 1
            }
        }
        events[modifierCount + 1].post(tap: .cghidEventTap)
        releaseModifiers()
        return true
    }
}

final class ShortcutEngine: ObservableObject {
    static let shared = ShortcutEngine()
    static let defaultsKey = "clickShortcutSequence"
    @Published private(set) var sequence: ShortcutSequence
    @Published private(set) var issue: String?
    private let defaults: UserDefaults
    private let delivery: ShortcutDelivery
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var recording = false
    private var downPoint: CGPoint?
    private var didDrag = false
    private var lastMiddleDown: TimeInterval?
    private var ignoreMiddleUp = false
    private var pendingMiddle: DispatchWorkItem?
    private var pendingGeneration: UUID?
    var middleDoubleClickInterval: () -> TimeInterval = { 0 }
    var middleClickAllowed: () -> Bool = { true }
    var foregroundPID: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    var currentModifiers: () -> ShortcutModifiers = { .physicalState }

    init(defaults: UserDefaults = .standard, delivery: ShortcutDelivery = SystemShortcutDelivery()) {
        self.defaults = defaults
        self.delivery = delivery
        var loaded = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(ShortcutSequence.self, from: $0) } ?? ShortcutSequence()
        loaded.normalize()
        sequence = loaded
    }

    func start() {
        guard !started else { return }
        started = true
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name,
                object: nil, queue: .main) { [weak self] _ in self?.cancelClick() })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:
            NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.cancelPendingMiddleClick()
                self?.lastMiddleDown = nil
            })
        refreshListener()
    }

    func stop() {
        started = false
        refreshListener()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    func refreshListener() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        cancelClick()
        lastMiddleDown = nil
        guard started, sequence.isEnabled, !recording, delivery.isAuthorized else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching:
            [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown,
             .otherMouseDown, .otherMouseDragged, .otherMouseUp]) { [weak self] event in
                self?.receive(event)
            }
    }

    private func receive(_ event: NSEvent) {
        guard let point = event.cgEvent?.location else { cancelClick(); return }
        let button = event.buttonNumber
        let isDown = event.type == .leftMouseDown || event.type == .otherMouseDown || event.type == .rightMouseDown
        guard button == sequence.trigger.buttonNumber else {
            if isDown { cancelClick() }
            return
        }
        if isDown {
            registerMouseDown(at: event.timestamp)
            downPoint = point
            didDrag = false
        } else if (event.type == .leftMouseDragged || event.type == .otherMouseDragged), let downPoint {
            if hypot(point.x - downPoint.x, point.y - downPoint.y) > 4 { didDrag = true }
        } else if event.type == .leftMouseUp || event.type == .otherMouseUp {
            let isClick = downPoint.map { hypot(point.x - $0.x, point.y - $0.y) <= 4 } ?? false
            let dragged = didDrag
            downPoint = nil; didDrag = false
            guard isClick, !dragged, let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.isActive, !app.isTerminated else { return }
            completeMouseClick(to: app.processIdentifier, modifiers: ShortcutModifiers(event.modifierFlags))
        }
    }

    func registerMouseDown(at timestamp: TimeInterval) {
        ignoreMiddleUp = false
        guard sequence.trigger == .middle else { return }
        let interval = middleDoubleClickInterval()
        if interval > 0, let lastMiddleDown, timestamp - lastMiddleDown <= interval {
            cancelPendingMiddleClick()
            self.lastMiddleDown = nil
            ignoreMiddleUp = true
        } else { lastMiddleDown = timestamp }
    }

    func completeMouseClick(to pid: pid_t, modifiers: ShortcutModifiers = []) {
        guard sequence.trigger == .middle else { executeClick(to: pid, modifiers: modifiers); return }
        guard !ignoreMiddleUp, middleClickAllowed() else { return }
        let delay = middleDoubleClickInterval()
        guard delay > 0 else { executeClick(to: pid, modifiers: modifiers); return }
        cancelPendingMiddleClick()
        let generation = UUID()
        pendingGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingGeneration == generation else { return }
            self.pendingMiddle = nil
            self.pendingGeneration = nil
            guard self.middleClickAllowed(), self.foregroundPID() == pid else { return }
            self.executeClick(to: pid, modifiers: modifiers)
        }
        pendingMiddle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelPendingMiddleClick() {
        pendingMiddle?.cancel(); pendingMiddle = nil; pendingGeneration = nil
    }

    /// Also used by the native event fixture; delivery failures never consume a step.
    func executeClick(to pid: pid_t, modifiers: ShortcutModifiers = []) {
        guard sequence.isEnabled, !recording, pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier, let step = sequence.next else { return }
        guard delivery.isAuthorized else { issue = "shortcuts.permission"; return }
        guard !delivery.isSecureInput else { issue = "shortcuts.secureInput"; return }
        guard modifiers.isEmpty, currentModifiers().isEmpty else { issue = "shortcuts.releaseModifiers"; return }
        guard foregroundPID() == pid else { issue = "shortcuts.focusChanged"; return }
        guard delivery.send(step.chord, scope: step.scope, to: pid) else {
            issue = "shortcuts.sendFailed"; return
        }
        change { $0.advance() }
    }

    func setRecording(_ value: Bool) {
        recording = value
        issue = nil
        refreshListener()
    }
    func setEnabled(_ value: Bool) {
        change { $0.isEnabled = value && !$0.steps.isEmpty }
        refreshListener()
    }
    func setTrigger(_ trigger: ShortcutTrigger) {
        change { $0.trigger = trigger }
        refreshListener()
    }
    func setLooping(_ value: Bool) { change { $0.isLooping = value } }
    func add(_ chord: ShortcutChord) { change { $0.add(chord) }; refreshListener() }
    func replace(_ id: UUID, with chord: ShortcutChord) { change { $0.replace(id, with: chord) } }
    func setScope(_ scope: ShortcutScope, for id: UUID) { change { $0.setScope(scope, for: id) } }
    func remove(_ id: UUID) { change { $0.remove(id) }; refreshListener() }
    func move(_ id: UUID, by offset: Int) { change { $0.move(id, by: offset) } }
    func back() { change { $0.back() } }
    func reset() { change { $0.reset() } }

    private func cancelClick() {
        downPoint = nil; didDrag = false
        lastMiddleDown = nil
        cancelPendingMiddleClick()
    }
    private func change(_ body: (inout ShortcutSequence) -> Void) {
        cancelClick()
        var updated = sequence
        body(&updated)
        updated.normalize()
        sequence = updated
        issue = nil
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: .init("ScrollappShortcutSequenceChanged"), object: self)
    }
}
