import Foundation
import CoreGraphics
import ImageIO
import CryptoKit

/// Scrollapp-authored role artwork, rendered from style tokens and the user's
/// locally downloaded material. Official pointer/hand files remain untouched.
enum SupplementedCursors {
    static let version = 1
    static let roles = CursorRole.allCases.filter { ![.arrow, .link].contains($0) }
    private static let lock = NSLock()
    private static var memory: [String: (signature: String, roles: [String: [String: Any]], bytes: Int)] = [:]
    private static var order: [String] = []

    static func invalidate(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        memory[id] = nil; order.removeAll { $0 == id }
    }

    static func resolve(_ id: String, base: [String: [String: Any]], directory: URL) throws -> [String: [String: Any]] {
        guard FeaturedSkin.find(id) != nil, let arrow = base["arrow"], let link = base["link"],
              let arrowPNGs = arrow["Representations"] as? [Data],
              let linkPNGs = link["Representations"] as? [Data] else { throw SkinAssetError.format }
        let signature = fingerprint([Data(id.utf8)] + arrowPNGs + linkPNGs)
        lock.lock()
        let hit = memory[id]
        if hit?.signature == signature { order.removeAll { $0 == id }; order.append(id) }
        lock.unlock()
        if let hit, hit.signature == signature { return hit.roles }
        let url = directory.appendingPathComponent("\(id)-states-v1.plist")
        let result: [String: [String: Any]]
        if let cached = try? load(url, signature: signature) {
            result = cached
        } else {
            guard let texture = largestImage(arrowPNGs), let emblem = largestImage(linkPNGs) else { throw SkinAssetError.format }
            let style = Palette(id)
            var generated: [String: [String: Any]] = [:]
            for role in roles {
                let geometry = geometry(role, pixelated: style.pixelated)
                let pngs = try [1, 2, 4, 8].map { try paint(role, geometry: geometry, palette: style,
                    texture: texture, emblem: emblem, density: $0) }
                generated[role.rawValue] = [
                    "PointsWide": 40.0, "PointsHigh": 40.0,
                    "HotSpotX": Double(geometry.hotspot.x), "HotSpotY": Double(geometry.hotspot.y),
                    "FrameCount": 1, "FrameDuration": 0.0, "Representations": pngs,
                    "ScrollappSupplemented": true
                ]
            }
            _ = try SkinPackageValidator.validateRoles(generated, requiredRoles: Set(roles.map(\.rawValue)), restoredRoles: [])
            result = generated
            // Disk caching is optional. A read-only cache directory must not
            // cause the app to apply an incomplete skin.
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? pack(result, signature: signature) { try? data.write(to: url, options: .atomic) }
        }
        let bytes = result.values.reduce(0) { total, role in
            total + ((role["Representations"] as? [Data]) ?? []).reduce(0) { $0 + $1.count }
        }
        lock.lock()
        memory[id] = (signature, result, bytes); order.removeAll { $0 == id }; order.append(id)
        while memory.values.reduce(0, { $0 + $1.bytes }) > 8 * 1024 * 1024 && order.count > 1 {
            memory[order.removeFirst()] = nil
        }
        lock.unlock()
        return result
    }

    private static func fingerprint(_ data: [Data]) -> String {
        var hash = SHA256()
        for image in data {
            var count = UInt64(image.count).littleEndian
            withUnsafeBytes(of: &count) { hash.update(data: Data($0)) }
            hash.update(data: image)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func pack(_ roles: [String: [String: Any]], signature: String) throws -> Data {
        let payload = try PropertyListSerialization.data(fromPropertyList: roles, format: .binary, options: 0)
        return try PropertyListSerialization.data(fromPropertyList:
            ["Version": version, "SourceSignature": signature, "Payload": payload, "SHA256": fingerprint([payload])],
            format: .binary, options: 0)
    }
    private static func load(_ url: URL, signature: String) throws -> [String: [String: Any]] {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 8 * 1024 * 1024,
              let wrapper = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any],
              wrapper["Version"] as? Int == version, wrapper["SourceSignature"] as? String == signature,
              let payload = wrapper["Payload"] as? Data, wrapper["SHA256"] as? String == fingerprint([payload]),
              let decoded = try PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: [String: Any]]
        else { throw SkinAssetError.integrity }
        let result = try SkinPackageValidator.validateRoles(decoded, requiredRoles: Set(roles.map(\.rawValue)), restoredRoles: [])
        for role in result.values {
            guard role["ScrollappSupplemented"] as? Bool == true,
                  role["PointsWide"] as? Double == 40, role["PointsHigh"] as? Double == 40,
                  let pngs = role["Representations"] as? [Data], pngs.count == 4 else { throw SkinAssetError.format }
            for (index, data) in pngs.enumerated() {
                guard let image = largestImage([data]), image.width == 40 * [1, 2, 4, 8][index],
                      image.height == image.width else { throw SkinAssetError.format }
            }
        }
        return result
    }
    private static func largestImage(_ data: [Data]) -> CGImage? {
        data.compactMap {
            CGImageSourceCreateWithData($0 as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        }.max { $0.width < $1.width }
    }

    private struct Palette {
        let id: String
        let body: CGColor
        let outline: CGColor
        let ink: CGColor
        let accent: CGColor
        let edge: CGColor
        let pixelated: Bool
        var fiery: Bool { id == "sweezy-sukuna" || id == "sweezy-lava" }
        init(_ id: String) {
            self.id = id
            func color(_ hex: UInt32) -> CGColor {
                CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                        blue: CGFloat(hex & 255) / 255, alpha: 1)
            }
            pixelated = ["sweezy-bmw-m4", "sweezy-old-roblox"].contains(id)
            switch id {
            case "sweezy-sukuna":
                (body, outline, ink, accent, edge) = (color(0x7D2637), color(0x381820), color(0xFFD9C2), color(0xF47B78), color(0xE7A3A4))
            case "sweezy-lava":
                (body, outline, ink, accent, edge) = (color(0xEC581F), color(0x792719), color(0xFFF2AB), color(0xFFCB3E), color(0xFFE2A2))
            case "sweezy-hello-kitty":
                (body, outline, ink, accent, edge) = (color(0xFFFDF9), color(0x413735), color(0x413735), color(0xF39DB4), color(0xFFFDF9))
            case "sweezy-cinnamoroll-white":
                (body, outline, ink, accent, edge) = (color(0xFFFFFF), color(0x64B7D4), color(0x4295BD), color(0xA3DEED), color(0xFFFFFF))
            case "sweezy-cinnamoroll-strawberry":
                (body, outline, ink, accent, edge) = (color(0xFFFFFF), color(0x67B9D2), color(0x4295BD), color(0xF5A0B3), color(0xFFFFFF))
            case "sweezy-bmw-m4":
                (body, outline, ink, accent, edge) = (color(0x394551), color(0x19232D), color(0xE8F2FC), color(0x548CCC), color(0xBCC6D0))
            default:
                (body, outline, ink, accent, edge) = (color(0xFFFFFF), color(0x171717), color(0x171717), color(0x171717), color(0xFFFFFF))
            }
        }
    }
    private struct Geometry {
        let path: CGPath
        let hotspot: CGPoint
        let ornament: CGPoint
    }
    private static func polygon(_ values: [(CGFloat, CGFloat)]) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: values[0].0, y: values[0].1))
        for point in values.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
        path.closeSubpath()
        return path
    }
    private static func geometry(_ role: CursorRole, pixelated: Bool) -> Geometry {
        let path = CGMutablePath()
        var hotspot = CGPoint(x: 20, y: 20), ornament = CGPoint(x: 29, y: 9)
        switch role {
        case .text:
            path.addPath(polygon([(11,5),(29,5),(29,9),(23,9),(23,31),(29,31),(29,35),
                                  (11,35),(11,31),(17,31),(17,9),(11,9)]))
            ornament = CGPoint(x: 28, y: 7)
        case .grab:
            if pixelated {
                path.addPath(polygon([(7,22),(7,17),(11,17),(11,8),(15,8),(15,5),(19,5),(19,9),
                    (23,9),(23,12),(27,12),(27,16),(31,16),(31,25),(27,25),(27,34),(14,34),(14,30),(10,30),(10,26)]))
            } else {
                path.move(to: CGPoint(x: 13, y: 33))
                path.addCurve(to: CGPoint(x: 7, y: 22), control1: CGPoint(x: 11, y: 29), control2: CGPoint(x: 5, y: 25))
                path.addCurve(to: CGPoint(x: 11, y: 18), control1: CGPoint(x: 5, y: 17), control2: CGPoint(x: 9, y: 15))
                path.addLine(to: CGPoint(x: 12, y: 21))
                path.addLine(to: CGPoint(x: 12, y: 11))
                path.addCurve(to: CGPoint(x: 17, y: 11), control1: CGPoint(x: 12, y: 7), control2: CGPoint(x: 17, y: 7))
                path.addLine(to: CGPoint(x: 17, y: 8))
                path.addCurve(to: CGPoint(x: 22, y: 8), control1: CGPoint(x: 17, y: 4), control2: CGPoint(x: 22, y: 4))
                path.addLine(to: CGPoint(x: 22, y: 11))
                path.addCurve(to: CGPoint(x: 27, y: 12), control1: CGPoint(x: 25, y: 7), control2: CGPoint(x: 28, y: 9))
                path.addLine(to: CGPoint(x: 27, y: 17))
                path.addCurve(to: CGPoint(x: 31, y: 20), control1: CGPoint(x: 30, y: 13), control2: CGPoint(x: 33, y: 16))
                path.addLine(to: CGPoint(x: 29, y: 28))
                path.addLine(to: CGPoint(x: 27, y: 34))
                path.closeSubpath()
            }
            hotspot = CGPoint(x: 20, y: 22); ornament = CGPoint(x: 23, y: 32)
        case .crosshair:
            path.addPath(polygon([(18,4),(22,4),(22,14),(26,14),(26,18),(36,18),(36,22),
                                  (26,22),(26,26),(22,26),(22,36),(18,36),(18,26),(14,26),
                                  (14,22),(4,22),(4,18),(14,18),(14,14),(18,14)]))
            ornament = CGPoint(x: 28, y: 10)
        case .horizontal, .vertical, .diagonalRight, .diagonalLeft:
            let arrow = polygon([(4,20),(12,12),(12,17),(28,17),(28,12),(36,20),
                                 (28,28),(28,23),(12,23),(12,28)])
            let angle: CGFloat = role == .vertical ? .pi / 2 : role == .diagonalRight ? -.pi / 4 :
                role == .diagonalLeft ? .pi / 4 : 0
            var transform = CGAffineTransform(translationX: 20, y: 20).rotated(by: angle).translatedBy(x: -20, y: -20)
            path.addPath(arrow.copy(using: &transform)!)
            ornament = CGPoint(x: 20, y: 20)
        case .unavailable:
            path.addEllipse(in: CGRect(x: 7, y: 7, width: 26, height: 26))
            ornament = CGPoint(x: 30, y: 10)
        case .help:
            if pixelated {
                path.addPath(polygon([(8,6),(31,6),(31,29),(18,29),(12,35),(12,29),(8,29)]))
            } else {
                path.addRoundedRect(in: CGRect(x: 8, y: 6, width: 24, height: 25), cornerWidth: 7, cornerHeight: 7)
                path.addPath(polygon([(12,27),(12,35),(20,29)]))
            }
            hotspot = CGPoint(x: 12, y: 34); ornament = CGPoint(x: 29, y: 29)
        case .zoomIn, .zoomOut:
            path.addEllipse(in: CGRect(x: 6, y: 6, width: 23, height: 23))
            path.addPath(polygon([(24,23),(35,32),(32,35),(23,25)]))
            hotspot = CGPoint(x: 17.5, y: 17.5); ornament = CGPoint(x: 31, y: 31)
        case .arrow, .link: break
        }
        return Geometry(path: path, hotspot: hotspot, ornament: ornament)
    }

    private static func paint(_ role: CursorRole, geometry: Geometry, palette p: Palette,
                              texture: CGImage, emblem: CGImage, density: Int) throws -> Data {
        let side = 40 * density
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw SkinAssetError.format }
        ctx.scaleBy(x: CGFloat(density), y: CGFloat(density))
        ctx.translateBy(x: 0, y: 40); ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(!p.pixelated)
        ctx.setLineCap(p.pixelated ? .square : .round); ctx.setLineJoin(p.pixelated ? .miter : .round)
        func line(_ points: [(CGFloat, CGFloat)], color: CGColor, width: CGFloat) {
            ctx.beginPath(); ctx.move(to: CGPoint(x: points[0].0, y: points[0].1))
            for point in points.dropFirst() { ctx.addLine(to: CGPoint(x: point.0, y: point.1)) }
            ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.strokePath()
        }
        func image(_ image: CGImage, in rect: CGRect) {
            ctx.saveGState(); ctx.translateBy(x: rect.minX, y: rect.maxY); ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = p.pixelated ? .none : .high
            ctx.draw(image, in: CGRect(origin: .zero, size: rect.size)); ctx.restoreGState()
        }
        ctx.addPath(geometry.path); ctx.setStrokeColor(p.edge); ctx.setLineWidth(3.6); ctx.strokePath()
        ctx.addPath(geometry.path); ctx.setFillColor(p.body); ctx.setStrokeColor(p.outline); ctx.setLineWidth(1.8)
        ctx.drawPath(using: .fillStroke)
        if p.fiery {
            ctx.saveGState(); ctx.addPath(geometry.path); ctx.clip()
            let colors = [p.accent, p.body] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 10, y: 4), end: CGPoint(x: 27, y: 36), options: [])
            }
            ctx.setAlpha(0.66); image(texture, in: CGRect(x: 4, y: 3, width: 33, height: 34))
            ctx.restoreGState()
            ctx.addPath(geometry.path); ctx.setStrokeColor(p.outline); ctx.setLineWidth(1.3); ctx.strokePath()
        }
        switch role {
        case .grab:
            line([(16,17),(16,23)], color: p.ink, width: 1)
            line([(22,16),(22,22)], color: p.ink, width: 1)
            line([(27,19),(26,24)], color: p.ink, width: 1)
        case .text:
            line([(20,11),(20,29)], color: p.accent, width: p.pixelated ? 2 : 1.2)
        case .crosshair:
            ctx.setFillColor(p.ink); ctx.fillEllipse(in: CGRect(x: 18.5, y: 18.5, width: 3, height: 3))
        case .unavailable:
            // The interior is open enough to read the prohibition bar at 1x.
            ctx.setFillColor(p.body); ctx.fillEllipse(in: CGRect(x: 12, y: 12, width: 16, height: 16))
            line([(11,29),(29,11)], color: p.ink, width: 3.2)
        case .help:
            ctx.beginPath(); ctx.move(to: CGPoint(x: 16, y: 14))
            ctx.addCurve(to: CGPoint(x: 24, y: 14), control1: CGPoint(x: 16, y: 8), control2: CGPoint(x: 25, y: 8))
            ctx.addCurve(to: CGPoint(x: 20, y: 21), control1: CGPoint(x: 25, y: 18), control2: CGPoint(x: 20, y: 18))
            ctx.setStrokeColor(p.ink); ctx.setLineWidth(2.3); ctx.strokePath()
            ctx.setFillColor(p.ink); ctx.fillEllipse(in: CGRect(x: 18.7, y: 25, width: 2.6, height: 2.6))
        case .zoomIn, .zoomOut:
            line([(12,17.5),(23,17.5)], color: p.ink, width: 2.2)
            if role == .zoomIn { line([(17.5,12),(17.5,23)], color: p.ink, width: 2.2) }
        default: break
        }
        let c = geometry.ornament
        switch p.id {
        case "sweezy-hello-kitty":
            let bow = CGMutablePath()
            bow.move(to: CGPoint(x: c.x, y: c.y))
            bow.addCurve(to: CGPoint(x: c.x - 5, y: c.y - 3), control1: CGPoint(x: c.x - 3, y: c.y - 4), control2: CGPoint(x: c.x - 6, y: c.y - 5))
            bow.addCurve(to: CGPoint(x: c.x, y: c.y + 1), control1: CGPoint(x: c.x - 7, y: c.y + 3), control2: CGPoint(x: c.x - 4, y: c.y + 4))
            bow.addCurve(to: CGPoint(x: c.x + 5, y: c.y + 3), control1: CGPoint(x: c.x + 3, y: c.y + 4), control2: CGPoint(x: c.x + 6, y: c.y + 5))
            bow.addCurve(to: CGPoint(x: c.x, y: c.y), control1: CGPoint(x: c.x + 7, y: c.y - 3), control2: CGPoint(x: c.x + 3, y: c.y - 4))
            ctx.addPath(bow); ctx.setFillColor(p.accent); ctx.setStrokeColor(p.outline); ctx.setLineWidth(0.8); ctx.drawPath(using: .fillStroke)
            ctx.setFillColor(p.accent); ctx.fillEllipse(in: CGRect(x: c.x - 1.7, y: c.y - 1.7, width: 3.4, height: 3.4))
            ctx.setStrokeColor(p.outline); ctx.setLineWidth(0.7); ctx.strokeEllipse(in: CGRect(x: c.x - 1.7, y: c.y - 1.7, width: 3.4, height: 3.4))
        case "sweezy-cinnamoroll-white":
            // The source head supplies the long ears and tiny face, rather
            // than an unrelated generic decoration.
            image(emblem, in: CGRect(x: c.x - 6, y: c.y - 5, width: 12, height: 10))
        case "sweezy-cinnamoroll-strawberry":
            let berry = CGMutablePath()
            berry.move(to: CGPoint(x: c.x, y: c.y + 5))
            berry.addCurve(to: CGPoint(x: c.x - 4, y: c.y - 2), control1: CGPoint(x: c.x - 4, y: c.y + 4), control2: CGPoint(x: c.x - 6, y: c.y - 1))
            berry.addCurve(to: CGPoint(x: c.x + 4, y: c.y - 2), control1: CGPoint(x: c.x - 3, y: c.y - 5), control2: CGPoint(x: c.x + 3, y: c.y - 5))
            berry.addCurve(to: CGPoint(x: c.x, y: c.y + 5), control1: CGPoint(x: c.x + 6, y: c.y - 1), control2: CGPoint(x: c.x + 4, y: c.y + 4))
            ctx.addPath(berry); ctx.setFillColor(p.accent); ctx.setStrokeColor(CGColor(red: 0.73, green: 0.40, blue: 0.49, alpha: 1))
            ctx.setLineWidth(0.8); ctx.drawPath(using: .fillStroke)
            ctx.setFillColor(CGColor(red: 0.72, green: 0.82, blue: 0.48, alpha: 1))
            ctx.addPath(polygon([(c.x-4,c.y-3),(c.x-1,c.y-6),(c.x,c.y-4),(c.x+3,c.y-6),(c.x+4,c.y-3)])); ctx.fillPath()
            ctx.setFillColor(CGColor(red: 1, green: 0.91, blue: 0.67, alpha: 1))
            for (x,y) in [(-2.0,-0.5),(1.5,-0.5),(0.0,2.0)] {
                ctx.fillEllipse(in: CGRect(x: c.x + x, y: c.y + y, width: 0.9, height: 1.3))
            }
        case "sweezy-sukuna", "sweezy-lava":
            let flame = CGMutablePath()
            flame.move(to: CGPoint(x: c.x, y: c.y + 4))
            flame.addCurve(to: CGPoint(x: c.x - 3, y: c.y - 2), control1: CGPoint(x: c.x - 5, y: c.y + 4), control2: CGPoint(x: c.x - 5, y: c.y))
            flame.addLine(to: CGPoint(x: c.x - 1, y: c.y))
            flame.addCurve(to: CGPoint(x: c.x + 1, y: c.y - 7), control1: CGPoint(x: c.x - 2, y: c.y - 4), control2: CGPoint(x: c.x + 2, y: c.y - 4))
            flame.addCurve(to: CGPoint(x: c.x, y: c.y + 4), control1: CGPoint(x: c.x + 8, y: c.y - 1), control2: CGPoint(x: c.x + 5, y: c.y + 4))
            ctx.addPath(flame); ctx.setFillColor(p.accent); ctx.setStrokeColor(p.outline); ctx.setLineWidth(0.8); ctx.drawPath(using: .fillStroke)
            if p.id == "sweezy-sukuna" {
                line([(c.x-1,c.y+1),(c.x+2,c.y-2)], color: p.outline, width: 0.8)
                line([(c.x-1,c.y-1),(c.x+2,c.y+1)], color: p.outline, width: 0.8)
            }
        case "sweezy-bmw-m4":
            for (index, color) in [CGColor(red: 0.37, green: 0.75, blue: 0.95, alpha: 1),
                                  CGColor(red: 0.16, green: 0.31, blue: 0.60, alpha: 1),
                                  CGColor(red: 0.84, green: 0.27, blue: 0.33, alpha: 1)].enumerated() {
                ctx.setFillColor(color)
                ctx.addPath(polygon([(c.x-5+CGFloat(index)*3,c.y+3),(c.x-1+CGFloat(index)*3,c.y-3),
                                    (c.x+1+CGFloat(index)*3,c.y-3),(c.x-3+CGFloat(index)*3,c.y+3)])); ctx.fillPath()
            }
        default:
            // Keep the old Roblox's black-and-white block silhouettes.
            ctx.setFillColor(p.outline)
            ctx.fill(CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6))
            ctx.setFillColor(p.body); ctx.fill(CGRect(x: c.x - 1, y: c.y - 1, width: 2, height: 2))
        }
        let data = NSMutableData()
        guard let image = ctx.makeImage(), let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        else { throw SkinAssetError.format }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SkinAssetError.format }
        return data as Data
    }
}
