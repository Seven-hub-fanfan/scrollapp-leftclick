import AppKit
import ApplicationServices
import Carbon
import Combine

/// Intercepts HID input ahead of global hotkey remappers. App-local delivery
/// uses NSApplication's event queue, never another global CGEvent post.
final class ShortcutInputShield: ObservableObject {
    static let shared = ShortcutInputShield()
    @Published private(set) var isActive = false
    @Published private(set) var error: String?
    private weak var window: NSWindow?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private var recording = false
    private var armed = false
    private var heldKeys = Set<UInt16>()
    private var recordedKeys = Set<UInt16>()
    private var captured: ((ShortcutChord) -> Void)?
    private var cancelled: (() -> Void)?
    private var localMonitor: Any?
    private var hotKeyToken: UnsafeMutableRawPointer?

    init() {
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willCloseNotification, .init("ScrollappPermissionsChanged")] {
            observers.append(NotificationCenter.default.addObserver(forName: name,
                object: nil, queue: .main) { [weak self] notification in
                    guard let self else { return }
                    if name == NSWindow.willCloseNotification,
                       let closing = notification.object as? NSWindow, self.window === closing {
                        self.detach(from: closing)
                    } else { self.refresh() }
                })
        }
    }

    func configure(window: NSWindow?, recording: Bool, captured: @escaping (ShortcutChord) -> Void,
                   cancelled: @escaping () -> Void) {
        self.window = window
        if self.recording != recording { armed = recording }
        self.recording = recording
        self.captured = captured
        self.cancelled = cancelled
        refresh()
    }

    func detach(from window: NSWindow?) {
        guard self.window === window else { return }
        self.window = nil
        recording = false; armed = false
        captured = nil; cancelled = nil
        refresh()
    }

    private var inScope: Bool {
        guard let window else { return false }
        return window.isVisible && NSApp.isActive && NSApp.keyWindow === window
    }

    func refresh() {
        let scoped = inScope
        guard scoped else {
            if isActive { isActive = false }
            releaseHotKeys()
            if heldKeys.isEmpty { tearDown() }
            return
        }
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else {
            if isActive { isActive = false }
            setError(AXIsProcessTrusted() ? "shortcuts.secureInput" : "shortcuts.isolationPermission")
            tearDown()
            return
        }
        if port == nil {
            let mask = [CGEventType.keyDown, .keyUp, .flagsChanged]
                .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            guard let created = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<ShortcutInputShield>.fromOpaque(context)
                        .takeUnretainedValue().receive(type, event)
                }, userInfo: pointer) else {
                setError("shortcuts.isolationFailed")
                if isActive { isActive = false }
                return
            }
            port = created
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: created, enable: true)
            // Direct-to-process injections do not traverse HID. Ignore them
            // while recording rather than using them as a fallback chord.
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.inScope, self.recording else { return event }
                return nil
            }
        }
        if hotKeyToken == nil {
            hotKeyToken = PushSymbolicHotKeyMode(OptionBits(kHIHotKeyModeAllDisabled))
            guard hotKeyToken != nil else {
                setError("shortcuts.isolationFailed")
                if isActive { isActive = false }
                tearDown()
                return
            }
        }
        setError(nil)
        if !isActive { isActive = true }
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if inScope || !heldKeys.isEmpty, let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let key = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        let scoped = inScope
        guard scoped || heldKeys.contains(key) else { return Unmanaged.passUnretained(event) }

        // Hardware input has no posting process. Input originating inside this
        // app is also allowed; another application's injected paste is blocked.
        let sender = event.getIntegerValueField(.eventSourceUnixProcessID)
        if scoped && sender != 0 && sender != Int64(ProcessInfo.processInfo.processIdentifier) { return nil }
        var released = type == .keyUp
        if type == .flagsChanged, let flag = Self.modifierFlags[key] {
            released = !event.flags.contains(flag) || heldKeys.contains(key)
        }
        if released { heldKeys.remove(key) }
        else if type == .keyDown || Self.modifierFlags[key] != nil { heldKeys.insert(key) }

        let wasRecorded = recordedKeys.contains(key)
        if released { recordedKeys.remove(key) }
        if !scoped {
            if heldKeys.isEmpty { DispatchQueue.main.async { [weak self] in self?.refresh() } }
            return nil // Finish consuming the paired release after focus changes.
        }
        if recording || wasRecorded {
            if !released { recordedKeys.insert(key) }
            if type == .keyDown, armed, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                let chord = ShortcutChord(keyCode: key, modifiers: ShortcutModifiers(
                    NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))))
                if key == 53 && chord.modifiers.isEmpty {
                    armed = false
                    DispatchQueue.main.async { [weak self] in self?.cancelled?() }
                } else if chord.isValid {
                    armed = false
                    DispatchQueue.main.async { [weak self] in self?.captured?(chord) }
                }
            }
            return nil
        }
        if let native = NSEvent(cgEvent: event), let window {
            // Assign the focused window for ordinary Tab/Space navigation.
            if type == .keyDown || type == .keyUp,
               let local = NSEvent.keyEvent(with: native.type, location: native.locationInWindow,
                    modifierFlags: native.modifierFlags, timestamp: native.timestamp,
                    windowNumber: window.windowNumber, context: nil, characters: native.characters ?? "",
                    charactersIgnoringModifiers: native.charactersIgnoringModifiers ?? "",
                    isARepeat: native.isARepeat, keyCode: native.keyCode) {
                NSApp.postEvent(local, atStart: false)
            } else { NSApp.postEvent(native, atStart: false) }
        }
        return nil
    }

    private static let modifierFlags: [UInt16: CGEventFlags] = [
        54: .maskCommand, 55: .maskCommand, 56: .maskShift, 60: .maskShift,
        58: .maskAlternate, 61: .maskAlternate, 59: .maskControl, 62: .maskControl,
        63: .maskSecondaryFn
    ]

    private func setError(_ value: String?) { if error != value { error = value } }

    private func releaseHotKeys() {
        if let hotKeyToken { PopSymbolicHotKeyMode(hotKeyToken); self.hotKeyToken = nil }
    }

    private func tearDown() {
        releaseHotKeys()
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); self.source = nil }
        if let port { CFMachPortInvalidate(port); self.port = nil }
        heldKeys.removeAll(); recordedKeys.removeAll()
    }
}
