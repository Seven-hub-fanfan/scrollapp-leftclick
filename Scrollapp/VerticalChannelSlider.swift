import SwiftUI
import AppKit

/// A flipped view's upper end is the maximum. All input shares this mapping.
struct ChannelScale {
    let range: ClosedRange<Double>
    let step: Double
    static let inset: CGFloat = 12

    func fraction(_ value: Double) -> Double {
        (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound)
            / (range.upperBound - range.lowerBound)
    }

    func position(_ value: Double, height: CGFloat) -> CGFloat {
        Self.inset + CGFloat(1 - fraction(value)) * max(height - Self.inset * 2, 1)
    }

    func value(at position: CGFloat, height: CGFloat) -> Double {
        let fraction = 1 - Double(min(max((position - Self.inset) / max(height - Self.inset * 2, 1), 0), 1))
        return snapped(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }

    func snapped(_ value: Double) -> Double {
        guard value.isFinite else { return range.lowerBound }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let snapped = range.lowerBound + ((clamped - range.lowerBound) / step).rounded() * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}

/// The fill and grip form one continuous control, without a separate thumb.
struct VerticalChannelSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String
    let unit: String
    let onChange: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engaged = false
    @State private var focused = false
    @State private var hovered = false
    static let width: CGFloat = 50
    static let height: CGFloat = 132
    private let radius: CGFloat = 16

    private var scale: ChannelScale { ChannelScale(range: range, step: step) }
    private var formattedValue: String {
        String(format: step >= 1 ? "%.0f" : "%.1f", value)
    }

    var body: some View {
        GeometryReader { geometry in
            let y = scale.position(value, height: geometry.size.height)
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack(alignment: .bottom) {
                shape.fill(Style.recess)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [
                        Style.adaptive(NSColor(white: 0.92, alpha: 1), NSColor(white: 0.34, alpha: 1)),
                        Style.adaptive(NSColor(white: 0.74, alpha: 1), NSColor(white: 0.19, alpha: 1))
                    ], startPoint: .top, endPoint: .bottom))
                    .frame(height: geometry.size.height - y + ChannelScale.inset)
                Capsule()
                    .fill(Style.adaptive(NSColor(white: 0.28, alpha: 1), NSColor(white: 0.92, alpha: 1)))
                    .frame(width: engaged ? 22 : 18, height: 3)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: engaged)
                    .position(x: geometry.size.width / 2, y: y)
                shape.fill(Style.primaryText.opacity(hovered || engaged ? 0.045 : 0))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovered || engaged)
                shape.strokeBorder(Style.line, lineWidth: 1)
            }
            .clipShape(shape)
            .overlay(shape.inset(by: -3).strokeBorder(Style.focus.opacity(focused ? 0.85 : 0), lineWidth: 1.5))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            ChannelInput(value: $value, scale: scale, label: label,
                         valueDescription: "\(formattedValue) \(unit)", enabled: isEnabled,
                         engaged: $engaged, focused: $focused, hovered: $hovered, onChange: onChange)
        }
        .frame(width: Self.width, height: Self.height)
    }
}

enum ChannelValueTint {
    static func color(fraction amount: Double, scheme: ColorScheme) -> Color {
        let low: (Double, Double, Double) = scheme == .dark ? (0.73, 0.88, 0.29) : (0.36, 0.44, 0.07)
        let middle: (Double, Double, Double) = scheme == .dark ? (0.99, 0.84, 0.25) : (0.60, 0.41, 0.04)
        let high: (Double, Double, Double) = scheme == .dark ? (1.00, 0.59, 0.23) : (0.70, 0.30, 0.09)
        let from = amount < 0.5 ? low : middle
        let to = amount < 0.5 ? middle : high
        let fraction = amount < 0.5 ? amount * 2 : (amount - 0.5) * 2
        return Color(red: from.0 + (to.0 - from.0) * fraction,
                     green: from.1 + (to.1 - from.1) * fraction,
                     blue: from.2 + (to.2 - from.2) * fraction)
    }
}

/// Independent circular meters display the same values as the three native sliders.
struct CircularSliderGauge: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    @Environment(\.colorScheme) private var colorScheme
    static let diameter: CGFloat = 82
    private var fraction: Double { ChannelScale(range: range, step: step).fraction(value) }
    private var tint: Color { ChannelValueTint.color(fraction: fraction, scheme: colorScheme) }

    var body: some View {
        let center = Self.diameter / 2
        let angle = (135 + fraction * 270) * .pi / 180
        ZStack {
            Circle().fill(Style.control)
            Circle().strokeBorder(Style.line, lineWidth: 1)
            MeterArc(fraction: 1).stroke(Style.tick.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            MeterArc(fraction: fraction).stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Canvas { context, _ in
                for index in 0...24 {
                    let angle = (135 + Double(index) / 24 * 270) * .pi / 180
                    let inner: Double = index % 6 == 0 ? 27 : 29
                    var tick = Path()
                    tick.move(to: point(angle: angle, radius: inner))
                    tick.addLine(to: point(angle: angle, radius: 32))
                    context.stroke(tick, with: .color(Style.secondaryText.opacity(index % 6 == 0 ? 0.65 : 0.3)),
                                   lineWidth: 1)
                }
            }
            Circle().fill(tint).frame(width: 5, height: 5)
                .position(point(angle: angle, radius: 37))
            Text(String(format: step >= 1 ? "%.0f" : "%.1f", value))
                .font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(Style.primaryText).position(x: center, y: 37)
            Text(unit).font(.system(size: 9, weight: .medium)).foregroundStyle(Style.secondaryText)
                .position(x: center, y: 53)
            Text(String(format: step >= 1 ? "%.0f" : "%.1f", range.lowerBound))
                .font(.system(size: 7)).foregroundStyle(Style.secondaryText).position(x: 18, y: 72)
            Text(String(format: step >= 1 ? "%.0f" : "%.1f", range.upperBound))
                .font(.system(size: 7)).foregroundStyle(Style.secondaryText).position(x: 64, y: 72)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func point(angle: Double, radius: Double) -> CGPoint {
        let center = Self.diameter / 2
        return CGPoint(x: center + CGFloat(cos(angle) * radius),
                       y: center + CGFloat(sin(angle) * radius))
    }
}

private struct MeterArc: Shape {
    let fraction: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2 - 4
        for index in 0...96 {
            let angle = (135 + Double(index) / 96 * fraction * 270) * .pi / 180
            let point = CGPoint(x: rect.midX + CGFloat(cos(angle)) * radius,
                                y: rect.midY + CGFloat(sin(angle)) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Decoration surrounds a centered slider and shares its exact grip position.
struct ChannelReadout: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let markers: [Double]
    @Environment(\.colorScheme) private var colorScheme
    static let width: CGFloat = 210
    private var scale: ChannelScale { ChannelScale(range: range, step: step) }
    private var tint: Color {
        ChannelValueTint.color(fraction: scale.fraction(value), scheme: colorScheme)
    }

    var body: some View {
        GeometryReader { geometry in
            let y = scale.position(value, height: geometry.size.height)
            let curve = ReadoutCurve(gripY: y)
            ZStack(alignment: .topLeading) {
                RadialGradient(stops: [
                    .init(color: tint.opacity(colorScheme == .dark ? 0.31 : 0.14), location: 0),
                    .init(color: tint.opacity(0.10), location: 0.38),
                    .init(color: .clear, location: 1)
                ], center: .center, startRadius: 0, endRadius: 25)
                    .frame(width: 50, height: 50)
                    .position(x: ReadoutCurve.x - ReadoutCurve.bend, y: y)
                ticks(gripY: y)
                ForEach(markers, id: \.self) { marker in
                    let markerY = scale.position(marker, height: geometry.size.height)
                    let proximity = max(1 - abs(markerY - y) / 60, 0)
                    Text(String(format: marker.rounded() == marker ? "%.0f" : "%.1f", marker))
                        .font(.system(size: 8.5, weight: .regular)).monospacedDigit()
                        .foregroundStyle(Style.secondaryText.opacity(0.4 + proximity * 0.6))
                        .frame(width: 32, alignment: .trailing)
                        .position(x: ReadoutCurve.x - 42, y: markerY)
                }
                curve.stroke(Style.tick, lineWidth: 1)
                curve.stroke(tint, lineWidth: 1.2)
                    .mask(
                        RadialGradient(colors: [.white, .white.opacity(0.65), .clear],
                                       center: UnitPoint(x: ReadoutCurve.x / geometry.size.width,
                                                         y: y / geometry.size.height),
                                       startRadius: 12, endRadius: 62)
                    )
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: step >= 1 ? "%.0f" : "%.1f", value))
                        .font(.system(size: 25, weight: .light)).monospacedDigit()
                    Text(unit).font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(tint)
                .frame(width: 60, alignment: .leading)
                .position(x: geometry.size.width / 2 + VerticalChannelSlider.width / 2 + 40,
                          y: min(max(y, 17), geometry.size.height - 17))
            }
        }
        .frame(width: Self.width, height: VerticalChannelSlider.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var divisionCount: Int {
        let span = range.upperBound - range.lowerBound
        let multiples: [Double] = [1, 2, 2.5, 5, 10]
        let multiple = multiples.first { span / (step * $0) <= 36 } ?? 10
        return max(Int((span / (step * multiple)).rounded()), 1)
    }

    private func ticks(gripY: CGFloat) -> some View {
        Canvas { context, size in
            let count = divisionCount
            for index in 0...max(count, 1) {
                let marker = range.lowerBound + Double(index) / Double(max(count, 1))
                    * (range.upperBound - range.lowerBound)
                let y = scale.position(marker, height: size.height)
                let major = markers.contains { abs($0 - marker) < 0.001 }
                let proximity = max(1 - abs(y - gripY) / 56, 0)
                var tick = Path()
                tick.move(to: CGPoint(x: ReadoutCurve.x - (major ? 22 : 16), y: y))
                tick.addLine(to: CGPoint(x: ReadoutCurve.x - 12, y: y))
                context.stroke(tick, with: .color(Style.tick.opacity(0.45 + proximity * 0.55)), lineWidth: 1)
            }
            // Render major marks independently of the minor interval.
            for marker in markers {
                let y = scale.position(marker, height: size.height)
                var tick = Path()
                tick.move(to: CGPoint(x: ReadoutCurve.x - 22, y: y))
                tick.addLine(to: CGPoint(x: ReadoutCurve.x - 12, y: y))
                context.stroke(tick, with: .color(Style.tick), lineWidth: 1)
            }
        }
    }
}

private struct ReadoutCurve: Shape {
    let gripY: CGFloat
    static var x: CGFloat { ChannelReadout.width / 2 - VerticalChannelSlider.width / 2 - 8 }
    static let bend: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lower = ChannelScale.inset
        let upper = max(lower, rect.height - ChannelScale.inset)
        for y in stride(from: lower, through: upper, by: 1) {
            let distance = abs(y - gripY) / 24
            let displacement = distance < 1 ? Self.bend * pow((1 + cos(distance * .pi)) / 2, 1.2) : 0
            let point = CGPoint(x: Self.x - displacement, y: y)
            if y == lower { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Native event handling prevents the page's ScrollView from stealing drags.
private struct ChannelInput: NSViewRepresentable {
    @Binding var value: Double
    let scale: ChannelScale
    let label: String
    let valueDescription: String
    let enabled: Bool
    @Binding var engaged: Bool
    @Binding var focused: Bool
    @Binding var hovered: Bool
    let onChange: () -> Void

    func makeNSView(context: Context) -> InputView { InputView() }
    func updateNSView(_ view: InputView, context: Context) {
        view.scale = scale
        view.value = value
        view.changed = { newValue in
            guard abs(newValue - value) > 0.0001 else { return }
            value = newValue
            onChange()
        }
        view.engagementChanged = { engaged = $0 }
        view.focusChanged = { focused = $0 }
        view.hoverChanged = { hovered = $0 }
        view.enabled = enabled
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.slider)
        view.setAccessibilityOrientation(.vertical)
        view.setAccessibilityLabel(label)
        view.setAccessibilityValueDescription(valueDescription)
        view.setAccessibilityMinValue(scale.range.lowerBound)
        view.setAccessibilityMaxValue(scale.range.upperBound)
        view.setAccessibilityEnabled(enabled)
        view.window?.invalidateCursorRects(for: view)
    }

    final class InputView: NSView {
        var scale = ChannelScale(range: 0...1, step: 0.1)
        var value = 0.0
        var enabled = true {
            didSet {
                guard enabled != oldValue, !enabled else { return }
                dragging = false
                engagementChanged?(false)
                hoverChanged?(false)
                if window?.firstResponder === self { window?.makeFirstResponder(nil) }
            }
        }
        var changed: ((Double) -> Void)?
        var engagementChanged: ((Bool) -> Void)?
        var focusChanged: ((Bool) -> Void)?
        var hoverChanged: ((Bool) -> Void)?
        private var grabOffset: CGFloat = 0
        private var dragging = false
        private var hoverArea: NSTrackingArea?
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { enabled }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { enabled }

        override func becomeFirstResponder() -> Bool {
            guard enabled else { return false }
            focusChanged?(true)
            return true
        }
        override func resignFirstResponder() -> Bool {
            focusChanged?(false)
            return true
        }
        override func updateTrackingAreas() {
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
            addTrackingArea(area)
            hoverArea = area
            super.updateTrackingAreas()
        }
        override func mouseEntered(with event: NSEvent) { if enabled { hoverChanged?(true) } }
        override func mouseExited(with event: NSEvent) { hoverChanged?(false) }
        override func resetCursorRects() {
            guard enabled else { return }
            addCursorRect(bounds, cursor: .pointingHand)
            let y = scale.position(value, height: bounds.height)
            addCursorRect(NSRect(x: 0, y: y - 14, width: bounds.width, height: 28).intersection(bounds),
                          cursor: dragging ? .closedHand : .openHand)
        }
        override func mouseDown(with event: NSEvent) {
            guard enabled else { return }
            window?.makeFirstResponder(self)
            let point = convert(event.locationInWindow, from: nil)
            let gripY = scale.position(value, height: bounds.height)
            let onGrip = abs(point.y - gripY) <= 14
            grabOffset = onGrip ? point.y - gripY : 0
            dragging = true
            engagementChanged?(true)
            if !onGrip { apply(scale.value(at: point.y, height: bounds.height)) }
            window?.invalidateCursorRects(for: self)
        }
        override func mouseDragged(with event: NSEvent) {
            guard enabled, dragging else { return }
            let point = convert(event.locationInWindow, from: nil)
            apply(scale.value(at: point.y - grabOffset, height: bounds.height))
        }
        override func mouseUp(with event: NSEvent) {
            dragging = false
            engagementChanged?(false)
            window?.invalidateCursorRects(for: self)
        }
        override func keyDown(with event: NSEvent) {
            guard enabled else { return }
            switch event.keyCode {
            case 126, 124: apply(value + scale.step)
            case 125, 123: apply(value - scale.step)
            case 115: apply(scale.range.lowerBound)
            case 119: apply(scale.range.upperBound)
            case 48:
                if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
                else { window?.selectNextKeyView(self) }
            default: super.keyDown(with: event)
            }
        }
        override func accessibilityPerformIncrement() -> Bool {
            guard enabled else { return false }
            apply(value + scale.step)
            return true
        }
        override func accessibilityPerformDecrement() -> Bool {
            guard enabled else { return false }
            apply(value - scale.step)
            return true
        }
        override func accessibilityValue() -> Any? { value }
        override func setAccessibilityValue(_ newValue: Any?) {
            guard enabled,
                  let number = (newValue as? NSNumber)?.doubleValue
                    ?? (newValue as? String).flatMap(Double.init),
                  number.isFinite else { return }
            apply(number)
        }
        private func apply(_ newValue: Double) {
            let snapped = scale.snapped(newValue)
            guard abs(value - snapped) > 0.0001 else { return }
            value = snapped
            changed?(snapped)
            NSAccessibility.post(element: self, notification: .valueChanged)
        }
    }
}
