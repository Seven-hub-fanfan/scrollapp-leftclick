// xcrun swiftc Scrollapp/ShortcutSequence.swift Scrollapp/ShortcutEngine.swift \
//   Scrollapp/Localization.swift scripts/verify_shortcuts.swift -o /tmp/verify-shortcuts
// /tmp/verify-shortcuts
import Foundation

private final class TestDelivery: ShortcutDelivery {
    var isAuthorized = true
    var isSecureInput = false
    var succeeds = true
    var sent: [ShortcutChord] = []
    var targets: [pid_t] = []
    var scopes: [ShortcutScope] = []
    func send(_ chord: ShortcutChord, scope: ShortcutScope, to pid: pid_t) -> Bool {
        guard succeeds else { return false }
        sent.append(chord)
        targets.append(pid)
        scopes.append(scope)
        return true
    }
}

@main
struct VerifyShortcuts {
    static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        let a = ShortcutChord(keyCode: 0, modifiers: [.command, .shift])
        let b = ShortcutChord(keyCode: 11, modifiers: [.control, .option])
        var sequence = ShortcutSequence()
        expect(sequence.trigger == .middle, "Middle button is the default")
        expect(!sequence.isLooping, "Loop is off by default")
        for _ in 0..<10 { expect(sequence.add(a), "Ten steps must be supported") }
        expect(!sequence.add(b) && sequence.steps.count == 10, "Reject an eleventh step")
        for _ in 0..<10 { sequence.advance() }
        expect(sequence.position == 10 && sequence.next == nil, "Finish without wrapping")
        sequence.advance()
        expect(sequence.position == 10, "Further clicks cannot overflow")
        sequence.back()
        expect(sequence.position == 9 && sequence.next != nil, "Back selects previous step")
        sequence.reset()
        sequence.back()
        expect(sequence.position == 0, "Back at the beginning stays at zero")
        sequence.advance()
        sequence.replace(sequence.steps[3].id, with: b)
        expect(sequence.position == 0 && sequence.steps[3].chord == b, "Editing resets progress")
        sequence.move(sequence.steps[3].id, by: -1)
        expect(sequence.steps[2].chord == b, "Reorder preserves chord identity")
        let encoded = try JSONEncoder().encode(sequence)
        let decoded = try JSONDecoder().decode(ShortcutSequence.self, from: encoded)
        expect(decoded == sequence,
               "All chords and order round-trip")
        var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        legacy.removeValue(forKey: "trigger")
        legacy.removeValue(forKey: "isLooping")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let migrated = try JSONDecoder().decode(ShortcutSequence.self, from: legacyData)
        expect(migrated.steps == sequence.steps && migrated.trigger == .middle,
               "Old sequences retain chords while adopting the middle-button default")
        expect(!migrated.isLooping, "Old configurations retain stop-at-end behavior")
        var oldStep = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sequence.steps[0])) as! [String: Any]
        oldStep.removeValue(forKey: "scope")
        let oldStepData = try JSONSerialization.data(withJSONObject: oldStep)
        let oldDecoded = try JSONDecoder().decode(ShortcutStep.self, from: oldStepData)
        expect(oldDecoded.scope == .application,
               "Old steps default to application delivery")
        oldStep["scope"] = "futureScope"
        let unknownStepData = try JSONSerialization.data(withJSONObject: oldStep)
        let unknownDecoded = try JSONDecoder().decode(ShortcutStep.self, from: unknownStepData)
        expect(unknownDecoded.scope == .application,
               "Unknown scopes never opt into global input")
        sequence.advance()
        sequence.setScope(.systemHotkey, for: sequence.steps[3].id)
        expect(sequence.position == 0 && sequence.steps[3].scope == .systemHotkey,
               "Changing a scope resets progress")
        sequence.replace(sequence.steps[3].id, with: a)
        expect(sequence.steps[3].scope == .systemHotkey, "Rerecording retains scope")
        let mixedData = try JSONEncoder().encode(sequence)
        let mixedDecoded = try JSONDecoder().decode(ShortcutSequence.self, from: mixedData)
        expect(mixedDecoded == sequence,
               "Mixed scopes round-trip with stable identities")
        let duplicate = ShortcutStep(chord: a)
        sequence.steps = [duplicate, duplicate, ShortcutStep(chord:
            ShortcutChord(keyCode: 55, modifiers: []))] + Array(repeating: b, count: 14)
                .map { ShortcutStep(chord: $0) }
        sequence.position = 100
        sequence.normalize()
        expect(sequence.steps.count == 10 && sequence.position == 10, "Normalize limits and cursor")
        expect(Set(sequence.steps.map(\.id)).count == 10, "Normalize duplicate identities")
        expect(!ShortcutChord(keyCode: 500, modifiers: []).isValid, "Reject invalid keycodes")
        expect(!ShortcutChord(keyCode: 0, modifiers: .init(rawValue: 1024)).isValid,
               "Reject unsupported modifiers")
        sequence.version = 99
        sequence.normalize()
        expect(sequence == ShortcutSequence(), "Do not execute unknown configuration versions")

        let suite = "com.scrollapp.shortcut-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let delivery = TestDelivery()
        let engine = ShortcutEngine(defaults: defaults, delivery: delivery)
        var focusedTarget: pid_t = ProcessInfo.processInfo.processIdentifier + 100
        engine.foregroundPID = { focusedTarget }
        engine.currentModifiers = { [] }
        engine.setEnabled(true)
        expect(!engine.sequence.isEnabled, "Empty sequence cannot be enabled")
        engine.add(a)
        engine.add(b)
        let target: pid_t = ProcessInfo.processInfo.processIdentifier + 100
        engine.executeClick(to: target)
        expect(delivery.sent.isEmpty, "Disabled sequence cannot send")
        engine.setEnabled(true)
        engine.executeClick(to: ProcessInfo.processInfo.processIdentifier)
        expect(delivery.sent.isEmpty, "App's own controls cannot send")
        engine.setRecording(true)
        engine.executeClick(to: target)
        expect(delivery.sent.isEmpty, "Recording suspends execution")
        engine.setRecording(false)
        delivery.isAuthorized = false
        engine.executeClick(to: target)
        expect(engine.sequence.position == 0 && engine.issue == "shortcuts.permission",
               "Revoked permission cannot consume a step")
        delivery.isAuthorized = true
        delivery.isSecureInput = true
        engine.executeClick(to: target)
        expect(engine.sequence.position == 0 && delivery.sent.isEmpty, "Secure input cannot consume a step")
        delivery.isSecureInput = false
        engine.executeClick(to: target, modifiers: .shift)
        expect(engine.sequence.position == 0 && delivery.sent.isEmpty,
               "Physically held modifiers cannot contaminate a chord")
        delivery.succeeds = false
        engine.executeClick(to: target)
        expect(engine.sequence.position == 0, "Failed delivery cannot advance")
        delivery.succeeds = true
        engine.executeClick(to: target)
        focusedTarget = target + 1
        engine.executeClick(to: target + 1)
        focusedTarget = target
        engine.executeClick(to: target)
        expect(delivery.sent == [a, b] && engine.sequence.position == 2,
               "Rapid clicks deliver one ordered chord each and stop at the end")
        expect(delivery.targets == [target, target + 1], "Each click uses its own captured target")
        engine.back()
        engine.executeClick(to: target)
        expect(delivery.sent == [a, b, b], "Back replays previous chord on next click")
        let resumed = ShortcutEngine(defaults: defaults, delivery: delivery)
        expect(resumed.sequence == engine.sequence, "Restart resumes enabled state and exact progress")
        engine.reset()
        engine.executeClick(to: target)
        expect(delivery.sent == [a, b, b, a], "Reset starts again at the first chord")
        engine.setTrigger(.left)
        expect(engine.sequence.position == 1 && engine.sequence.trigger == .left,
               "Changing the mouse trigger preserves progress")
        engine.setTrigger(.middle)
        engine.reset()
        engine.middleDoubleClickInterval = { 0.05 }
        engine.foregroundPID = { target }
        let countBefore = delivery.sent.count
        engine.registerMouseDown(at: 1)
        engine.completeMouseClick(to: target)
        expect(delivery.sent.count == countBefore, "Middle single click waits for double-click classification")
        engine.registerMouseDown(at: 1.02)
        engine.completeMouseClick(to: target)
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        expect(delivery.sent.count == countBefore && engine.sequence.position == 0,
               "Double middle click does not execute either shortcut")
        engine.registerMouseDown(at: 2)
        engine.completeMouseClick(to: target)
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        expect(delivery.sent.count == countBefore + 1 && engine.sequence.position == 1,
               "Single middle click executes exactly once")
        engine.registerMouseDown(at: 3)
        engine.completeMouseClick(to: target)
        engine.reset()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        expect(engine.sequence.position == 0 && delivery.sent.count == countBefore + 1,
               "Reset cancels a pending middle-click action")
        engine.registerMouseDown(at: 4)
        engine.completeMouseClick(to: target)
        engine.foregroundPID = { target + 1 }
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        expect(delivery.sent.count == countBefore + 1, "Pending chords cannot leak into a different foreground app")
        engine.foregroundPID = { target }
        engine.registerMouseDown(at: 5)
        engine.completeMouseClick(to: target)
        engine.middleClickAllowed = { false }
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        expect(delivery.sent.count == countBefore + 1, "Scrolling suppresses a pending middle-click shortcut")
        engine.middleClickAllowed = { true }
        engine.registerMouseDown(at: 6)
        engine.completeMouseClick(to: target)
        engine.currentModifiers = { .option }
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        expect(delivery.sent.count == countBefore + 1 && engine.issue == "shortcuts.releaseModifiers",
               "Modifiers pressed during the middle-click delay cancel delivery")
        engine.currentModifiers = { [] }
        engine.foregroundPID = { target + 1 }
        engine.executeClick(to: target)
        expect(delivery.sent.count == countBefore + 1 && engine.issue == "shortcuts.focusChanged",
               "Immediate execution also checks the captured foreground PID")
        engine.foregroundPID = { target }
        engine.registerMouseDown(at: 7)
        engine.completeMouseClick(to: target)
        engine.setScope(.systemHotkey, for: engine.sequence.steps[1].id)
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        expect(delivery.sent.count == countBefore + 1 && engine.sequence.position == 0,
               "Scope editing cancels pending clicks")
        engine.executeClick(to: target)
        engine.setTrigger(.left)
        engine.middleClickAllowed = { false }
        engine.completeMouseClick(to: target)
        expect(delivery.sent.count == countBefore + 3 && delivery.scopes.suffix(2) == [.application, .systemHotkey],
               "Left-button execution remains immediate while middle scrolling is active")
        for step in engine.sequence.steps { engine.remove(step.id) }
        expect(engine.sequence.steps.isEmpty && !engine.sequence.isEnabled,
               "Deleting every step disables execution")
        defaults.set(Data("malformed".utf8), forKey: ShortcutEngine.defaultsKey)
        expect(ShortcutEngine(defaults: defaults, delivery: delivery).sequence == ShortcutSequence(),
               "Corrupted saved configuration safely falls back to empty")

        let loopSuite = suite + ".loop"
        let loopDefaults = UserDefaults(suiteName: loopSuite)!
        defer { loopDefaults.removePersistentDomain(forName: loopSuite) }
        let loopDelivery = TestDelivery()
        let loopEngine = ShortcutEngine(defaults: loopDefaults, delivery: loopDelivery)
        loopEngine.foregroundPID = { target }
        loopEngine.currentModifiers = { [] }
        loopEngine.add(a)
        loopEngine.setEnabled(true)
        loopEngine.executeClick(to: target)
        expect(loopEngine.sequence.next == nil && loopDelivery.sent == [a],
               "A single non-looping shortcut stops after one click")
        loopEngine.setLooping(true)
        expect(loopEngine.sequence.position == 0 && loopDelivery.sent == [a],
               "Enabling Loop after completion rearms without sending")
        for _ in 0..<8 { loopEngine.executeClick(to: target) }
        expect(loopDelivery.sent == Array(repeating: a, count: 9) && loopEngine.sequence.position == 0,
               "A one-step loop responds once to every subsequent click")
        let restoredLoop = ShortcutEngine(defaults: loopDefaults, delivery: loopDelivery)
        expect(restoredLoop.sequence.isLooping && restoredLoop.sequence == loopEngine.sequence,
               "Loop mode persists across restarts")
        loopEngine.setLooping(false)
        loopEngine.executeClick(to: target)
        loopEngine.executeClick(to: target)
        expect(loopDelivery.sent.count == 10 && loopEngine.sequence.next == nil,
               "Turning Loop off restores stop-at-end behavior")
        loopEngine.add(b)
        loopEngine.setScope(.systemHotkey, for: loopEngine.sequence.steps[1].id)
        loopEngine.setLooping(true)
        loopDelivery.sent = []
        for _ in 0..<6 { loopEngine.executeClick(to: target) }
        expect(loopDelivery.sent == [a, b, a, b, a, b] && loopEngine.sequence.position == 0,
               "Multiple groups loop in order without skipping or duplicating")
        expect(Array(loopDelivery.scopes.suffix(6)) ==
               [.application, .systemHotkey, .application, .systemHotkey, .application, .systemHotkey],
               "A mixed sequence uses exactly one selected route per click")
        loopEngine.back()
        expect(loopEngine.sequence.next?.chord == b, "Back at a loop boundary selects the last group")
        loopEngine.reset()
        expect(loopEngine.sequence.next?.chord == a && loopEngine.sequence.isLooping,
               "Reset keeps Loop on and selects the first group")
        loopDelivery.isAuthorized = false
        let sentBeforeFailure = loopDelivery.sent.count
        loopEngine.executeClick(to: target)
        expect(loopDelivery.sent.count == sentBeforeFailure && loopEngine.sequence.position == 0,
               "Permission failure cannot advance a loop")
        print("Passed \(checks) shortcut sequence and delivery checks")
    }
}
