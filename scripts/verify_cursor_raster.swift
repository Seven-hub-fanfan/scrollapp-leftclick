// Compile with CursorThemes.swift, Localization.swift and CursorRaster.m,
// using CursorRaster.h as the Objective-C bridging header. Place the executable
// in a test .app containing the current Skins resources. No global writes.
import AppKit

@main
struct VerifyCursorRaster {
    static func png(_ width: Int, color: NSColor, frames: Int = 1) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: width * frames,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<width * frames {
            let c = (frames == 1 ? color : [NSColor.blue, .green, .yellow][y / width]).usingColorSpace(.sRGB)!
            for x in 0..<width {
                let pixel = bitmap.bitmapData! + y * bitmap.bytesPerRow + x * 4
                pixel[0] = UInt8((c.redComponent * 255).rounded())
                pixel[1] = UInt8((c.greenComponent * 255).rounded())
                pixel[2] = UInt8((c.blueComponent * 255).rounded())
                pixel[3] = 255
            }
        }
        return bitmap.representation(using: .png, properties: [:])!
    }
    static func render(_ d: [String: Any], _ scale: Double, _ marker: Double = 0) -> [String: Any] {
        SCRCursorRaster.render(d, scale: scale, pixelated: false, markerDiameter: marker)!
    }
    static func isRed(_ c: NSColor) -> Bool {
        let rgb = c.usingColorSpace(.sRGB)!
        return rgb.redComponent > 0.8 && rgb.greenComponent < 0.5 && rgb.blueComponent < 0.5 && rgb.alphaComponent > 0.8
    }
    static func verifyMarker(_ d: [String: Any], diameter: Double, frames: Int = 1) {
        let w = d["PointsWide"] as! Double, h = d["PointsHigh"] as! Double
        let x = d["HotSpotX"] as! Double, y = d["HotSpotY"] as! Double
        for (index, png) in (d["Representations"] as! [Data]).prefix(2).enumerated() {
            let density = index + 1
            let bitmap = NSBitmapImageRep(data: png)!
            precondition(bitmap.pixelsWide == Int(w) * density)
            precondition(bitmap.pixelsHigh == Int(h) * density * frames)
            for frame in 0..<frames {
                let centerX = Int(x * Double(density)), centerY = Int((y + Double(frame) * h) * Double(density))
                precondition(isRed(bitmap.colorAt(x: centerX, y: centerY)!),
                             "Dot missed actual hotspot \(centerX),\(centerY), frame \(frame): \(bitmap.colorAt(x: centerX, y: centerY)!)")
                let redPixels = (0..<bitmap.pixelsWide).filter {
                    isRed(bitmap.colorAt(x: $0, y: centerY)!)
                }
                // The white stroke and antialiasing remove up to two red edge
                // pixels at 1x; the requested outside diameter stays fixed.
                precondition(abs(Double(redPixels.count) / Double(density) - diameter) <= 2.1,
                             "Dot size changed with cursor scale: \(redPixels.count)/\(density)")
                let center = Double(redPixels.first! + redPixels.last! + 1) / (2 * Double(density))
                precondition(abs(center - x) <= 0.6, "Dot not centered")
            }
        }
    }
    static func main() throws {
        _ = NSApplication.shared
        CursorCatalog.captureSystemImages()
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        var results: [[String: Any]] = []
        // Deliberately different low-resolution artwork exposes source switching.
        let fixture: [String: Any] = ["PointsWide": 32, "PointsHigh": 32,
            "HotSpotX": 0, "HotSpotY": 0, "FrameCount": 1, "FrameDuration": 0,
            "Representations": [png(32, color: .blue), png(64, color: .yellow), png(320, color: .green)]]
        try (render(fixture, 0.5, 5)["Representations"] as! [Data])[1]
            .write(to: directory.appendingPathComponent("marker-fixture.png"))
        for scale in [0.5, 0.9, 1.0, 1.1, 2.4, 2.5, 2.6, 4.9, 5.0, 5.1, 8.0] {
            let d = render(fixture, scale)
            for png in d["Representations"] as! [Data] {
                let bitmap = NSBitmapImageRep(data: png)!
                let c = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.sRGB)!
                precondition(c.greenComponent > 0.9 && c.redComponent < 0.1 && c.blueComponent < 0.1,
                             "Renderer switched to low-resolution artwork")
            }
            for marker in [3.0, 5.0, 16.0] {
                let marked = render(fixture, scale, marker)
                verifyMarker(marked, diameter: marker)
                let padding = ceil(marker / 2 + 1)
                precondition(marked["HotSpotX"] as! Double == padding && marked["HotSpotY"] as! Double == padding)
                precondition(marked["PointsWide"] as! Double - padding == (32 * scale).rounded())
            }
        }
        let animated: [String: Any] = ["PointsWide": 32, "PointsHigh": 32,
            "HotSpotX": 0, "HotSpotY": 0, "FrameCount": 3, "FrameDuration": 0.12,
            "Representations": [png(32, color: .blue, frames: 3), png(64, color: .blue, frames: 3)]]
        let strip = render(animated, 1.5, 5)
        verifyMarker(strip, diameter: 5, frames: 3)
        precondition(strip["FrameCount"] as! Int == 3 && strip["FrameDuration"] as! Double == 0.12)
        let stripBitmap = NSBitmapImageRep(data: (strip["Representations"] as! [Data])[0])!
        let frameHeight = Int(strip["PointsHigh"] as! Double)
        let originalStrip = NSBitmapImageRep(data: (animated["Representations"] as! [Data])[1])!
        for frame in 0..<3 {
            let actual = stripBitmap.colorAt(x: 30, y: frame * frameHeight + 30)!.usingColorSpace(.sRGB)!
            let color = originalStrip.colorAt(x: 32, y: frame * 64 + 32)!.usingColorSpace(.sRGB)!
            precondition(abs(actual.redComponent - color.redComponent) < 0.02 &&
                         abs(actual.greenComponent - color.greenComponent) < 0.02 &&
                         abs(actual.blueComponent - color.blueComponent) < 0.02,
                         "Animation frame \(frame) changed: \(actual) vs \(color)")
        }
        results.append(["test": "master-selection-fixed-dot-padding-and-animation", "ok": true])

        for theme in CursorCatalog.themes where theme.id != "system" {
            try CursorCatalog.payload(for: theme).write(to: directory.appendingPathComponent("\(theme.id).plist"))
            let source = CursorCatalog.roles(for: theme)
            for role in CursorRole.allCases {
                let d = source[role.rawValue]!
                if d["RestoreOriginal"] as? Bool == true { continue }
                let initial = render(d, 1.8)
                // Shrink/grow across all former source thresholds and return.
                for scale in [0.5, 8, 1, 5, 2.5, 1.8, 8, 0.5, 1.8] {
                    let output = render(d, scale)
                    let pngs = output["Representations"] as! [Data]
                    let width = Int((32 * scale).rounded())
                    precondition(CursorCatalog.pixelWidth(pngs[0]) == width)
                    precondition(CursorCatalog.pixelWidth(pngs[1]) == width * 2)
                    let local = CursorCatalog.cursor(theme, role: role, scale: scale)
                    precondition(local.hotSpot.x == output["HotSpotX"] as! Double &&
                                 local.hotSpot.y == output["HotSpotY"] as! Double)
                    precondition(local.image.representations.compactMap { ($0 as? NSBitmapImageRep)?.pixelsWide } ==
                                 pngs.map(CursorCatalog.pixelWidth))
                }
                precondition(initial["Representations"] as! [Data] == render(d, 1.8)["Representations"] as! [Data])
                let marked = render(d, 8, 5)
                let png = (marked["Representations"] as! [Data])[1]
                let bitmap = NSBitmapImageRep(data: png)!
                precondition(isRed(bitmap.colorAt(x: Int((marked["HotSpotX"] as! Double) * 2),
                    y: Int((marked["HotSpotY"] as! Double) * 2))!))
                try png.write(to: directory.appendingPathComponent("\(theme.id)-\(role.rawValue)-8x-marker.png"))
                let normal = render(d, 1.8, 5)
                let local = CursorCatalog.cursor(theme, role: role, scale: 1.8, markerDiameter: 5)
                precondition(local.hotSpot.x == normal["HotSpotX"] as! Double &&
                             local.hotSpot.y == normal["HotSpotY"] as! Double)
            }
            let arrow = source["arrow"]!
            for _ in 0..<100 {
                autoreleasepool {
                    _ = CursorCatalog.cursor(theme, role: .arrow, scale: 0.5, markerDiameter: 3)
                    _ = CursorCatalog.cursor(theme, role: .arrow, scale: 8, markerDiameter: 16)
                }
            }
            precondition(render(arrow, 1.8)["Representations"] as! [Data] == render(arrow, 1.8)["Representations"] as! [Data])
            results.append(["test": "\(theme.id)-all-roles-density-hotspots-roundtrip-and-cache", "ok": true])
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("raster-verification.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
