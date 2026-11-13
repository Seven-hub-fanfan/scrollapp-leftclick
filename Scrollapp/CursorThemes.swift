import AppKit
import SwiftUI
import ImageIO

enum CursorSizing {
    static let range: ClosedRange<Double> = 0.5...8.0
    static let step = 0.1
}

enum CursorRole: String, CaseIterable {
    case arrow, text, link, grab, crosshair, horizontal, vertical, diagonalRight, diagonalLeft, unavailable, help, zoomIn, zoomOut
    var label: String { L10n.t("skins.role.\(rawValue)") }
}

struct CursorTheme: Identifiable {
    let id: String
    let category: String
    let color: Color
    let resource: String?
    var name: String { L10n.t("skins.\(id).name") }
    var subtitle: String { L10n.t("skins.\(id).description") }
}

// Semantic roles are the theme-author contract. System identifiers live here,
// in one versioned mapping, rather than being duplicated in every skin.
enum CursorCatalog {
    static let themes: [CursorTheme] = [
        .init(id: "system", category: "minimal", color: Color(red: 0.87, green: 0.88, blue: 0.90), resource: nil),
        .init(id: "frog", category: "colorful", color: Color(red: 0.87, green: 0.94, blue: 0.78), resource: "Frog"),
        .init(id: "xiaoqi", category: "colorful", color: Color(red: 0.92, green: 0.94, blue: 0.79), resource: "Xiaoqi")
    ]
    static func theme(_ id: String) -> CursorTheme { themes.first { $0.id == id } ?? themes[0] }
    static let mapping: [String: CursorRole] = {
        var result: [String: CursorRole] = [:]
        func core(_ suffixes: [String], _ role: CursorRole) {
            for suffix in suffixes { result["com.apple.coregraphics.\(suffix)"] = role }
        }
        func cursors(_ indices: [Int], _ role: CursorRole) {
            for index in indices { result["com.apple.cursor.\(index)"] = role }
        }
        core(["Arrow", "ArrowCtx", "ArrowS"], .arrow)
        core(["IBeam", "IBeamS", "IBeamXOR"], .text)
        core(["Alias", "Copy"], .link)
        core(["Move"], .grab)
        // Confirmed against AppKit's native cursor getters on macOS 26.
        // Busy (4), disappearing-item (25), Wait and Empty remain untouched.
        cursors([20], .crosshair)
        cursors([7, 8, 9, 10, 41], .arrow)
        cursors([2, 5, 13, 24], .link)
        cursors([11, 12], .grab)
        cursors([17, 18, 19, 27, 28, 38], .horizontal)
        cursors([14, 15, 16, 21, 22, 23, 31, 32, 36], .vertical)
        cursors([29, 30, 37], .diagonalRight)
        cursors([33, 34, 35], .diagonalLeft)
        cursors([3], .unavailable)
        cursors([26], .text)
        cursors([40], .help)
        cursors([42], .zoomIn)
        cursors([43], .zoomOut)
        return result
    }()
    private static var resourceCache: [String: [String: [String: Any]]] = [:]
    private static var cacheOrder: [String] = []
    private static var thumbnails: [String: NSImage] = [:]
    private static var systemImages: [CursorRole: NSImage] = [:]
    private static var systemHotSpots: [CursorRole: NSPoint] = [:]
    static func captureSystemImages() {
        guard systemImages.isEmpty else { return }
        for role in CursorRole.allCases {
            let cursor = systemCursor(role)
            systemImages[role] = cursor.image.copy() as? NSImage
            systemHotSpots[role] = cursor.hotSpot
        }
    }
    static func systemCursor(_ role: CursorRole) -> NSCursor {
        switch role {
        case .text: return .iBeam
        case .link, .help: return .pointingHand
        case .grab: return .openHand
        case .crosshair: return .crosshair
        case .horizontal, .diagonalRight, .diagonalLeft: return .resizeLeftRight
        case .vertical: return .resizeUpDown
        case .unavailable: return .operationNotAllowed
        case .zoomIn: return .zoomIn
        case .zoomOut: return .zoomOut
        case .arrow: return .arrow
        }
    }

    static func roles(for theme: CursorTheme) -> [String: [String: Any]] {
        if let cached = resourceCache[theme.id] {
            cacheOrder.removeAll { $0 == theme.id }; cacheOrder.append(theme.id)
            return cached
        }
        var roles: [String: [String: Any]] = [:]
        if let name = theme.resource,
           let url = Bundle.main.url(forResource: name, withExtension: "plist", subdirectory: "Skins"),
           let data = try? Data(contentsOf: url),
           let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let stored = root["Roles"] as? [String: [String: Any]] {
            roles = stored
        } else if theme.resource == nil && theme.id != "system" {
            for role in CursorRole.allCases { roles[role.rawValue] = VectorCursor.descriptor(role, mint: theme.id == "mint") }
        }
        // Existing frog artwork has eight shapes. Rotations generate additional
        // resize orientations while retaining its own artwork and click hotspot.
        if theme.id == "frog", let arrow = roles["arrow"] {
            roles["crosshair"] = VectorCursor.frogVariant(arrow, role: .crosshair)
            roles["help"] = VectorCursor.frogVariant(arrow, role: .help)
            roles["zoomIn"] = VectorCursor.frogVariant(arrow, role: .zoomIn)
            roles["zoomOut"] = VectorCursor.frogVariant(arrow, role: .zoomOut)
        }
        if theme.id == "frog", let vertical = roles["vertical"] {
            roles["diagonalRight"] = VectorCursor.rotated(vertical, radians: .pi / 4)
            roles["diagonalLeft"] = VectorCursor.rotated(vertical, radians: -.pi / 4)
        }
        resourceCache[theme.id] = roles
        cacheOrder.append(theme.id)
        if cacheOrder.count > 2 { resourceCache.removeValue(forKey: cacheOrder.removeFirst()) }
        return roles
    }

    static func thumbnail(_ theme: CursorTheme, role: CursorRole) -> NSImage {
        if theme.id == "system" { return image(theme, role: role) }
        let key = "\(theme.id).\(role.rawValue)"
        if let cached = thumbnails[key] { return cached }
        let image: NSImage
        if let name = theme.resource, let url = Bundle.main.url(forResource: "\(name)-\(role.rawValue)",
            withExtension: "png", subdirectory: "Skins"), let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else if theme.resource != nil {
            image = NSCursor.arrow.image
        } else {
            let d = VectorCursor.descriptor(role, mint: theme.id == "mint")
            image = NSImage(data: (d["Representations"] as! [Data])[1])!
        }
        image.size = NSSize(width: 32, height: 32)
        thumbnails[key] = image
        return image
    }

    static func payload(for theme: CursorTheme) throws -> Data {
        let roles = roles(for: theme)
        var cursors: [String: Any] = [:]
        for (name, role) in mapping {
            guard let descriptor = roles[role.rawValue] else { throw NSError(domain: "CursorThemes", code: 1) }
            cursors[name] = descriptor
        }
        return try PropertyListSerialization.data(fromPropertyList: ["Cursors": cursors], format: .binary, options: 0)
    }

    static func pixelWidth(_ data: Data) -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return 0 }
        return (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    }

    static func image(_ theme: CursorTheme, role: CursorRole, minimumPixels: Int = 64) -> NSImage {
        if theme.id == "system" {
            return systemImages[role] ?? systemCursor(role).image
        }
        let descriptor = roles(for: theme)[role.rawValue]
        if descriptor?["RestoreOriginal"] as? Bool == true {
            return systemImages[role] ?? systemCursor(role).image
        }
        guard let pngs = descriptor?["Representations"] as? [Data],
              let data = pngs.first(where: { pixelWidth($0) >= minimumPixels }) ?? pngs.last,
              let image = NSImage(data: data) else { return NSCursor.arrow.image }
        image.size = NSSize(width: 32, height: 32)
        return image
    }

    static func cursor(_ theme: CursorTheme, role: CursorRole, scale: Double) -> NSCursor {
        let logicalWidth = theme.id == "system" ? 32 :
            (roles(for: theme)[role.rawValue]?["PointsWide"] as? Double) ?? 32
        let base = image(theme, role: role, minimumPixels: Int((logicalWidth * scale).rounded() * 2))
        let size = NSSize(width: (base.size.width * scale).rounded(),
                          height: (base.size.height * scale).rounded())
        let scaled: NSImage
        if scale == 1 {
            scaled = base.copy() as! NSImage
        } else {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            context.imageInterpolation = theme.id == "mint" ? .none : .high
            NSGraphicsContext.current = context
            base.draw(in: NSRect(origin: .zero, size: NSSize(width: size.width * 2, height: size.height * 2)))
            NSGraphicsContext.restoreGraphicsState()
            bitmap.size = size
            scaled = NSImage(size: size)
            scaled.addRepresentation(bitmap)
        }
        let spot: NSPoint
        if theme.id == "system" || roles(for: theme)[role.rawValue]?["RestoreOriginal"] as? Bool == true {
            spot = systemHotSpots[role] ?? systemCursor(role).hotSpot
        } else {
            let d = roles(for: theme)[role.rawValue]
            spot = NSPoint(x: (d?["HotSpotX"] as? CGFloat) ?? 1, y: (d?["HotSpotY"] as? CGFloat) ?? 1)
        }
        scaled.size = size
        return NSCursor(image: scaled, hotSpot: NSPoint(
            x: CGFloat(Float(spot.x * size.width / base.size.width)),
            y: CGFloat(Float(spot.y * size.height / base.size.height))))
    }
}

// Two original vector families: outlined graphite and crisp mint pixels.
// Rasterize only 1x/2x representations on demand; no animation/rendering timer.
enum VectorCursor {
    static func descriptor(_ role: CursorRole, mint: Bool, scales: [Int] = [1, 2]) -> [String: Any] {
        let hotspot: CGPoint
        switch role {
        case .arrow: hotspot = CGPoint(x: 5, y: 3)
        case .link: hotspot = CGPoint(x: 13, y: 3)
        default: hotspot = CGPoint(x: 16, y: 16)
        }
        return ["PointsWide": 32, "PointsHigh": 32, "HotSpotX": hotspot.x, "HotSpotY": hotspot.y,
                "FrameCount": 1, "FrameDuration": 0, "Representations": scales.map { png(role, mint: mint, scale: $0) }]
    }
    private static func png(_ role: CursorRole, mint: Bool, scale: Int) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32 * scale, pixelsHigh: 32 * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        cg.translateBy(x: 0, y: 32); cg.scaleBy(x: 1, y: -1)
        cg.setShouldAntialias(!mint)
        let fill = mint ? NSColor(red: 0.36, green: 0.86, blue: 0.69, alpha: 1) : NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
        func path(_ points: [CGPoint], closed: Bool = false, width: CGFloat = 2) {
            guard let first = points.first else { return }
            let p = CGMutablePath(); p.move(to: first)
            for point in points.dropFirst() { p.addLine(to: point) }
            if closed { p.closeSubpath() }
            cg.addPath(p); cg.setStrokeColor((mint ? NSColor(red: 0.07, green: 0.25, blue: 0.21, alpha: 1) : .white).cgColor)
            cg.setFillColor(fill.cgColor); cg.setLineWidth(width)
            cg.setLineJoin(mint ? .miter : .round); cg.setLineCap(mint ? .square : .round)
            cg.drawPath(using: closed ? .fillStroke : .stroke)
            if !closed {
                cg.addPath(p); cg.setStrokeColor(fill.cgColor); cg.setLineWidth(max(1, width - 2)); cg.strokePath()
            }
        }
        func points(_ values: [(CGFloat, CGFloat)]) -> [CGPoint] { values.map { CGPoint(x: $0.0, y: $0.1) } }
        switch role {
        case .arrow:
            path(points(mint ? [(5,3),(5,25),(11,19),(16,29),(21,26),(16,17),(25,17)] :
                [(5,3),(6,26),(12,20),(17,29),(21,27),(16,18),(26,17)]), closed: true)
        case .text:
            path(points([(11,5),(21,5),(16,5),(16,27),(11,27),(21,27)]), width: 5)
        case .link:
            path(points([(10,18),(10,6),(13,3),(16,6),(16,14),(19,12),(22,14),(25,14),(27,18),(25,28),(14,28),(7,21),(7,18)]), closed: true)
            path(points([(16,16),(16,20),(21,16),(21,21)]), width: 2)
        case .grab:
            path(points([(6,17),(6,11),(9,9),(12,12),(12,6),(15,5),(18,7),(18,12),(21,8),(24,10),(24,15),(27,14),(28,18),(25,27),(12,28),(5,21)]), closed: true)
        case .crosshair:
            path(points([(16,3),(16,29)]), width: 5); path(points([(3,16),(29,16)]), width: 5)
        case .horizontal, .vertical, .diagonalRight, .diagonalLeft:
            cg.translateBy(x: 16, y: 16)
            let angle: CGFloat = role == .vertical ? .pi / 2 : role == .diagonalRight ? .pi / 4 : role == .diagonalLeft ? -.pi / 4 : 0
            cg.rotate(by: angle); cg.translateBy(x: -16, y: -16)
            path(points([(3,16),(10,9),(10,13),(22,13),(22,9),(29,16),(22,23),(22,19),(10,19),(10,23)]), closed: true)
        case .unavailable:
            cg.setFillColor(fill.cgColor); cg.setStrokeColor(NSColor.white.cgColor); cg.setLineWidth(2)
            cg.fillEllipse(in: CGRect(x: 4, y: 4, width: 24, height: 24))
            cg.strokeEllipse(in: CGRect(x: 4, y: 4, width: 24, height: 24))
            cg.setStrokeColor((mint ? NSColor(red: 0.07, green: 0.25, blue: 0.21, alpha: 1) : .white).cgColor)
            cg.setLineWidth(3); cg.move(to: CGPoint(x: 9, y: 9)); cg.addLine(to: CGPoint(x: 23, y: 23)); cg.strokePath()
        case .help:
            path(points([(11,10),(11,7),(14,5),(19,5),(22,8),(22,12),(16,16),(16,19)]), width: 5)
            path(points([(16,24),(16,25)]), width: 5)
        case .zoomIn, .zoomOut:
            cg.setFillColor(fill.cgColor); cg.setStrokeColor((mint ? NSColor(red: 0.07, green: 0.25, blue: 0.21, alpha: 1) : .white).cgColor)
            cg.setLineWidth(2); cg.fillEllipse(in: CGRect(x: 4, y: 4, width: 20, height: 20))
            cg.strokeEllipse(in: CGRect(x: 4, y: 4, width: 20, height: 20))
            path(points([(21,21),(29,29)]), width: 5)
            cg.setStrokeColor((mint ? NSColor(red: 0.07, green: 0.25, blue: 0.21, alpha: 1) : .white).cgColor)
            cg.setLineWidth(2); cg.move(to: CGPoint(x: 9, y: 14)); cg.addLine(to: CGPoint(x: 19, y: 14)); cg.strokePath()
            if role == .zoomIn { cg.move(to: CGPoint(x: 14, y: 9)); cg.addLine(to: CGPoint(x: 14, y: 19)); cg.strokePath() }
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }
    static func frogVariant(_ arrow: [String: Any], role: CursorRole) -> [String: Any] {
        guard let representations = arrow["Representations"] as? [Data] else {
            return descriptor(role, mint: false)
        }
        let scales = representations.map { max(1, CursorCatalog.pixelWidth($0) / 32) }
        var result = descriptor(role, mint: false, scales: scales)
        let symbols = result["Representations"] as! [Data]
        result["Representations"] = symbols.enumerated().map { index, symbol -> Data in
            let scale = CGFloat(scales[index])
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(32 * scale), pixelsHigh: Int(32 * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSImage(data: symbol)?.draw(in: NSRect(x: 0, y: 0, width: 26 * scale, height: 26 * scale))
            NSImage(data: representations[index])?.draw(in: NSRect(x: 12 * scale, y: 1 * scale, width: 20 * scale, height: 20 * scale))
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.representation(using: .png, properties: [:])!
        }
        result["HotSpotX"] = 13; result["HotSpotY"] = 19
        return result
    }
    static func rotated(_ original: [String: Any], radians: CGFloat) -> [String: Any] {
        var result = original
        guard let data = original["Representations"] as? [Data] else { return original }
        result["Representations"] = data.map { png -> Data in
            let scale = max(1, CursorCatalog.pixelWidth(png) / 32)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32 * scale, pixelsHigh: 32 * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            let cg = NSGraphicsContext.current!.cgContext
            cg.translateBy(x: CGFloat(16 * scale), y: CGFloat(16 * scale)); cg.rotate(by: radians)
            NSImage(data: png)?.draw(in: NSRect(x: -16 * scale, y: -16 * scale, width: 32 * scale, height: 32 * scale))
            NSGraphicsContext.restoreGraphicsState()
            return bitmap.representation(using: .png, properties: [:])!
        }
        result["HotSpotX"] = 16; result["HotSpotY"] = 16
        return result
    }
}
