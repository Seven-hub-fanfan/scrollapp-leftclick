import Foundation

struct ScrollIntegrator {
    private(set) var remainder = 0.0
    mutating func reset() { remainder = 0 }
    mutating func pixels(for amount: Double) -> Int32 {
        guard amount.isFinite else { reset(); return 0 }
        if amount == 0 { reset(); return 0 }
        if remainder * amount < 0 { remainder = 0 }
        let value = max(-1000, min(1000, remainder + amount))
        let pixels = Int32(value)
        remainder = value - Double(pixels)
        return pixels
    }
}

struct DoubleClickActivation {
    private var last: TimeInterval?
    mutating func reset() { last = nil }
    mutating func click(at time: TimeInterval, interval: TimeInterval) -> Bool {
        defer { last = last == nil ? time : nil }
        if let last, time >= last, time - last <= interval { return true }
        last = nil
        return false
    }
}
