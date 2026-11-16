import Foundation

struct ShortcutModifiers: OptionSet, Codable, Equatable {
    let rawValue: UInt32
    static let control = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let shift = Self(rawValue: 1 << 2)
    static let command = Self(rawValue: 1 << 3)
    static let supported: Self = [.control, .option, .shift, .command]
}

struct ShortcutChord: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: ShortcutModifiers

    var isValid: Bool {
        keyCode < 128 && !(54...63).contains(keyCode)
            && modifiers.subtracting(.supported).isEmpty
    }
}

struct ShortcutStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var chord: ShortcutChord
}

enum ShortcutTrigger: String, Codable, CaseIterable {
    case middle, left
    var buttonNumber: Int { self == .middle ? 2 : 0 }
}

/// Position always identifies the *next* step. `steps.count` means completed.
/// Going back changes that position; it cannot undo an action in another app.
struct ShortcutSequence: Codable, Equatable {
    static let limit = 10
    var version = 1
    var steps: [ShortcutStep] = []
    var isEnabled = false
    var position = 0
    var trigger: ShortcutTrigger = .middle
    var isLooping = false

    init() {}
    private enum CodingKeys: String, CodingKey { case version, steps, isEnabled, position, trigger, isLooping }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        steps = try values.decodeIfPresent([ShortcutStep].self, forKey: .steps) ?? []
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        position = try values.decodeIfPresent(Int.self, forKey: .position) ?? 0
        // Existing 2.4.15 sequences retain their chords and progress, with the
        // newly requested default mouse trigger.
        trigger = try values.decodeIfPresent(ShortcutTrigger.self, forKey: .trigger) ?? .middle
        isLooping = try values.decodeIfPresent(Bool.self, forKey: .isLooping) ?? false
    }

    var next: ShortcutStep? {
        steps.indices.contains(position) ? steps[position] : nil
    }

    mutating func normalize() {
        guard version == 1 else { self = Self(); return }
        var seen = Set<UUID>()
        steps = Array(steps.filter { $0.chord.isValid && seen.insert($0.id).inserted }
            .prefix(Self.limit))
        position = min(max(0, position), steps.count)
        if isLooping && !steps.isEmpty && position == steps.count { position = 0 }
        if steps.isEmpty { isEnabled = false }
    }

    @discardableResult
    mutating func add(_ chord: ShortcutChord) -> Bool {
        guard chord.isValid, steps.count < Self.limit else { return false }
        steps.append(ShortcutStep(chord: chord))
        position = 0
        return true
    }

    mutating func replace(_ id: UUID, with chord: ShortcutChord) {
        guard chord.isValid, let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].chord = chord
        position = 0
    }

    mutating func remove(_ id: UUID) {
        guard steps.contains(where: { $0.id == id }) else { return }
        steps.removeAll { $0.id == id }
        position = 0
        if steps.isEmpty { isEnabled = false }
    }

    mutating func move(_ id: UUID, by offset: Int) {
        guard let index = steps.firstIndex(where: { $0.id == id }),
              steps.indices.contains(index + offset) else { return }
        steps.swapAt(index, index + offset)
        position = 0
    }

    mutating func advance() {
        guard next != nil else { return }
        position += 1
        if isLooping && position == steps.count { position = 0 }
    }
    mutating func back() {
        if isLooping && position == 0 && !steps.isEmpty { position = steps.count - 1 }
        else { position = max(0, position - 1) }
    }
    mutating func reset() { position = 0 }
}
