import AppKit
import SwiftUI

final class CursorSkinStore: ObservableObject {
    static let shared = CursorSkinStore()
    @Published private(set) var activeID = "system"
    @Published var selectedID = UserDefaults.standard.string(forKey: "cursorTheme") ?? "system"
    @Published private(set) var isBusy = false
    @Published private(set) var isReady = false
    @Published private(set) var errorKey: String?
    @Published private(set) var appliedCount = 0
    @Published private(set) var cursorScale: Double = {
        let saved = UserDefaults.standard.double(forKey: "cursorScale")
        return saved.isFinite && CursorSizing.range.contains(saved) ? saved : 1
    }()
    @Published private(set) var appliedCursorScale = 1.0
    @Published private(set) var clickMarkerEnabled = UserDefaults.standard.bool(forKey: "cursorClickMarkerEnabled")
    @Published private(set) var clickMarkerSize: Double = {
        let saved = UserDefaults.standard.double(forKey: "cursorClickMarkerSize")
        return saved.isFinite && CursorMarkerSizing.range.contains(saved) ? saved : CursorMarkerSizing.defaultSize
    }()
    @Published private(set) var appliedMarkerDiameter = 0.0
    @Published var section = "general"

    private let queue = DispatchQueue(label: "com.scrollapp.cursor-service", qos: .userInitiated)
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var started = false
    private var shuttingDown = false
    private var automaticRecoveries = 0
    private var observers: [NSObjectProtocol] = []
    private var reapplyWork: DispatchWorkItem?
    private var resizeWork: DispatchWorkItem?
    private var resizePending = false
    private var refreshGeneration = 0
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Scrollapp/Cursors", isDirectory: true)

    var activeTheme: CursorTheme { CursorCatalog.theme(activeID) }
    var selectedTheme: CursorTheme { CursorCatalog.theme(selectedID) }
    var isThemed: Bool { activeID != "system" }
    var markerDiameter: Double { clickMarkerEnabled ? clickMarkerSize : 0 }
    var hasCustomCursor: Bool { isThemed || appliedCursorScale != 1 || appliedMarkerDiameter > 0 }

    func start() {
        guard !started else { return }
        started = true; isBusy = true; errorKey = nil
        // Capture genuine system thumbnails before applying a remembered theme.
        CursorCatalog.captureSystemImages()
        selectedID = CursorCatalog.theme(selectedID).id
        let savedID = UserDefaults.standard.string(forKey: "cursorTheme") ?? "system"
        let preferredID = CursorCatalog.theme(savedID).id
        if preferredID != savedID { UserDefaults.standard.set(preferredID, forKey: "cursorTheme") }
        queue.async {
            do {
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.directory.path)
                guard let executable = Bundle.main.url(forAuxiliaryExecutable: "CursorService") else {
                    throw ServiceError(code: "unsupportedSystem")
                }
                let child = Process(), stdinPipe = Pipe(), stdoutPipe = Pipe()
                child.executableURL = executable
                child.arguments = [self.directory.appendingPathComponent("recovery.plist").path, String(ProcessInfo.processInfo.processIdentifier)]
                child.standardInput = stdinPipe; child.standardOutput = stdoutPipe
                child.standardError = FileHandle.nullDevice
                self.process = child; self.input = stdinPipe.fileHandleForWriting
                self.output = stdoutPipe.fileHandleForReading; self.buffer.removeAll()
                try child.run()
                let ready = try self.readResponse()
                guard ready["ok"] as? Bool == true else {
                    throw ServiceError(code: ready["error"] as? String ?? "unsupportedSystem")
                }
                child.terminationHandler = { [weak self] stopped in
                    guard let self else { return }
                    self.queue.async {
                        DispatchQueue.main.async {
                            guard !self.shuttingDown, self.process === stopped else { return }
                            self.isReady = false; self.isBusy = false; self.started = false
                            self.errorKey = "serviceUnavailable"
                            // One automatic reconnect recovers the durable journal.
                            // Repeated failures stay visible instead of restarting forever.
                            if self.automaticRecoveries == 0 {
                                self.automaticRecoveries += 1
                                self.start()
                            }
                        }
                    }
                }
                DispatchQueue.main.async {
                    self.activeID = "system"
                    self.appliedCursorScale = 1
                    self.appliedMarkerDiameter = 0
                    self.isReady = true; self.isBusy = false; self.errorKey = nil
                    self.observeSystemChanges()
                    NotificationCenter.default.post(name: .init("ScrollappCursorSkinChanged"), object: nil)
                    if preferredID != "system" || self.cursorScale != 1 || self.clickMarkerEnabled { self.apply(preferredID) }
                }
            } catch {
                DispatchQueue.main.async {
                    self.started = false; self.isReady = false; self.isBusy = false
                    self.errorKey = (error as? ServiceError)?.code ?? "serviceUnavailable"
                }
            }
        }
    }

    func apply(_ id: String) {
        guard isReady, !isBusy, !shuttingDown else { return }
        let theme = CursorCatalog.theme(id)
        let scale = cursorScale
        let marker = markerDiameter
        let payload: Data?
        do { payload = theme.id == "system" ? nil : try CursorCatalog.payload(for: theme) }
        catch { errorKey = "invalidPayload"; return }
        isBusy = true; errorKey = nil
        resizeWork?.cancel()
        resizePending = false
        queue.async {
            do {
                let response: [String: Any]
                if let payload {
                    let path = self.directory.appendingPathComponent("pending.plist")
                    try payload.write(to: path, options: .atomic)
                    defer { try? FileManager.default.removeItem(at: path) }
                    response = try self.send(["action": "apply", "path": path.path, "scale": scale,
                        "pixelated": theme.id == "mint", "markerDiameter": marker])
                } else {
                    response = try self.send(["action": "system", "scale": scale,
                        "names": CursorCatalog.mapping.keys.sorted(), "markerDiameter": marker])
                }
                DispatchQueue.main.async {
                    self.isBusy = false
                    if response["ok"] as? Bool == true {
                        self.activeID = theme.id
                        self.appliedCursorScale = scale
                        self.appliedMarkerDiameter = marker
                        self.appliedCount = response["applied"] as? Int ?? 0
                        UserDefaults.standard.set(theme.id, forKey: "cursorTheme")
                        UserDefaults.standard.set(scale, forKey: "cursorScale")
                        self.saveMarkerPreferences()
                        NotificationCenter.default.post(name: .init("ScrollappCursorSkinChanged"), object: nil)
                        self.refreshVisibleCursor()
                        if self.resizePending || self.cursorScale != scale || self.markerDiameter != marker { self.requestResize() }
                    } else {
                        self.errorKey = response["error"] as? String ?? "applyFailed"
                        if response["reset"] as? Bool == true {
                            self.activeID = "system"
                            self.appliedCursorScale = 1
                            self.appliedMarkerDiameter = 0
                            UserDefaults.standard.set("system", forKey: "cursorTheme")
                        }
                        if self.cursorScale == scale { self.cursorScale = self.appliedCursorScale }
                        if self.markerDiameter == marker { self.restoreAppliedMarker() }
                        self.resizePending = false
                        self.refreshVisibleCursor()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false; self.isReady = false; self.started = false
                    self.errorKey = "serviceUnavailable"
                    self.cursorScale = self.appliedCursorScale
                    self.restoreAppliedMarker()
                    self.refreshVisibleCursor()
                }
            }
        }
    }

    func reset() {
        selectedID = "system"
        apply("system")
    }

    func setCursorScale(_ value: Double) {
        guard value.isFinite else { return }
        let clamped = (min(max(value, CursorSizing.range.lowerBound), CursorSizing.range.upperBound) * 10).rounded() / 10
        guard clamped != cursorScale else { return }
        cursorScale = clamped
        scheduleResize()
    }

    func setClickMarkerEnabled(_ enabled: Bool) {
        guard clickMarkerEnabled != enabled else { return }
        clickMarkerEnabled = enabled
        scheduleResize()
    }

    func setClickMarkerSize(_ value: Double) {
        guard value.isFinite else { return }
        let size = min(max(value.rounded(), CursorMarkerSizing.range.lowerBound), CursorMarkerSizing.range.upperBound)
        guard size != clickMarkerSize else { return }
        clickMarkerSize = size
        if clickMarkerEnabled { scheduleResize() }
        else { saveMarkerPreferences() }
    }

    private func saveMarkerPreferences() {
        UserDefaults.standard.set(appliedMarkerDiameter > 0, forKey: "cursorClickMarkerEnabled")
        UserDefaults.standard.set(appliedMarkerDiameter > 0 ? appliedMarkerDiameter : clickMarkerSize, forKey: "cursorClickMarkerSize")
    }

    private func restoreAppliedMarker() {
        clickMarkerEnabled = appliedMarkerDiameter > 0
        if clickMarkerEnabled { clickMarkerSize = appliedMarkerDiameter }
    }

    private func scheduleResize() {
        // Local feedback is immediate; coalesce the global PNG registration
        // during dragging instead of putting it into the scroll timer.
        refreshVisibleCursor()
        resizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.requestResize() }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
    private func requestResize() {
        guard !shuttingDown else { return }
        if isBusy || !isReady { resizePending = true; return }
        apply(activeID)
    }

    func activeCursor(role: CursorRole = .arrow) -> NSCursor {
        CursorCatalog.cursor(activeTheme, role: role, scale: appliedCursorScale, markerDiameter: appliedMarkerDiameter)
    }
    private func refreshVisibleCursor() {
        guard NSApp.isActive else { return }
        let point = NSEvent.mouseLocation
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.contains(point) }) else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        if let view = window.contentView {
            view.layoutSubtreeIfNeeded()
            window.invalidateCursorRects(for: view)
        }
        NSCursor.setHiddenUntilMouseMoves(false)
        // A new image cursor bypasses AppKit's cached system arrow. Merely
        // registering a global replacement does not redraw the current sprite.
        setVisibleCursor(phase: "immediate")
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, NSApp.isActive, self.refreshGeneration == generation,
                  window.isVisible, NSEvent.mouseLocation == point else { return }
            // SwiftUI changes the Apply button's enabled state on the next turn,
            // which can reset cursor rects. Reassert once after that layout.
            self.setVisibleCursor(phase: "after-layout")
        }
    }
    private func setVisibleCursor(phase: String) {
        let cursor = CursorCatalog.cursor(activeTheme, role: .arrow, scale: cursorScale, markerDiameter: markerDiameter)
        cursor.set()
        // Opt-in verification of the actual AppKit current cursor, after an
        // Apply click and before any additional mouse input. No default logging.
        if CommandLine.arguments.contains("--cursor-refresh-log") {
            let current: NSCursor? = NSCursor.current
            let result: [String: Any] = [
                "phase": phase, "theme": activeID, "scale": cursorScale, "markerDiameter": markerDiameter,
                "matchesImage": current?.image === cursor.image ||
                    current?.image.tiffRepresentation == cursor.image.tiffRepresentation,
                "matchesHotSpot": current?.hotSpot == cursor.hotSpot,
                "actualSize": [current?.image.size.width ?? 0, current?.image.size.height ?? 0],
                "mousePoint": [NSEvent.mouseLocation.x, NSEvent.mouseLocation.y]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: result) {
                FileHandle.standardOutput.write(data + Data([10]))
            }
        }
    }

    func shutdown(_ completion: @escaping () -> Void) {
        shuttingDown = true
        reapplyWork?.cancel()
        resizeWork?.cancel()
        queue.async {
            if self.process?.isRunning == true {
                _ = try? self.send(["action": "quit"])
                try? self.input?.close()
                self.process?.waitUntilExit()
            }
            DispatchQueue.main.async { completion() }
        }
    }

    private func observeSystemChanges() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleReapply()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.scheduleReapply() })
    }
    private func scheduleReapply() {
        reapplyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hasCustomCursor else { return }
            self.requestResize()
        }
        reapplyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    private struct ServiceError: Error { let code: String }
    private func send(_ command: [String: Any]) throws -> [String: Any] {
        guard process?.isRunning == true, let input else { throw ServiceError(code: "serviceUnavailable") }
        var data = try JSONSerialization.data(withJSONObject: command)
        data.append(10)
        try input.write(contentsOf: data)
        return try readResponse()
    }
    private func readResponse() throws -> [String: Any] {
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw ServiceError(code: "serviceUnavailable")
                }
                return object
            }
            guard let data = output?.availableData, !data.isEmpty else { throw ServiceError(code: "serviceUnavailable") }
            buffer.append(data)
        }
    }
}
