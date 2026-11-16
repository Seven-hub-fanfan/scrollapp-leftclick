import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Reads static Windows cursors, retaining their real click hotspots.
/// Every directory entry is bounded and decoded before any artwork is accepted.
enum StaticCursorImporter {
    static let maximumBytes = 4 * 1024 * 1024

    static func descriptor(at url: URL) throws -> [String: Any] {
        guard url.pathExtension.lowercased() == "cur" else { throw SkinAssetError.unsupportedCursor }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumBytes else { throw SkinAssetError.cursorFormat }
        return try descriptor(from: Data(contentsOf: url))
    }

    static func descriptor(from data: Data) throws -> [String: Any] {
        guard data.count >= 22, data.count <= maximumBytes else { throw SkinAssetError.cursorFormat }
        func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int {
            Int(data[offset]) | Int(data[offset + 1]) << 8 |
                Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
        }
        guard u16(0) == 0, u16(2) == 2 else { throw SkinAssetError.unsupportedCursor }
        let count = u16(4)
        guard (1...8).contains(count), data.count >= 6 + count * 16 else { throw SkinAssetError.cursorFormat }
        var occupied: [Range<Int>] = []
        var best: (png: Data, width: Int, height: Int, x: Int, y: Int)?
        for index in 0..<count {
            let entry = 6 + index * 16
            let w = data[entry] == 0 ? 256 : Int(data[entry])
            let h = data[entry + 1] == 0 ? 256 : Int(data[entry + 1])
            let x = u16(entry + 4), y = u16(entry + 6)
            let length = u32(entry + 8), offset = u32(entry + 12)
            guard data[entry + 3] == 0, x < w, y < h, length > 0,
                  offset >= 6 + count * 16, offset <= data.count,
                  length <= data.count - offset else { throw SkinAssetError.cursorFormat }
            let range = offset..<(offset + length)
            guard !occupied.contains(where: { $0.overlaps(range) }) else { throw SkinAssetError.cursorFormat }
            occupied.append(range)
            // ImageIO supports ICO. Its image bytes match CUR; only the
            // directory's type and hotspot fields need to become ICO fields.
            var ico = Data([0, 0, 1, 0, 1, 0])
            ico.append(data.subdata(in: entry..<(entry + 16)))
            ico[10] = 1; ico[11] = 0; ico[12] = 32; ico[13] = 0
            ico[18] = 22; ico[19] = 0; ico[20] = 0; ico[21] = 0
            ico.append(data.subdata(in: range))
            guard let source = CGImageSourceCreateWithData(ico as CFData, nil),
                  CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  (properties[kCGImagePropertyPixelWidth] as? Int) == w,
                  (properties[kCGImagePropertyPixelHeight] as? Int) == h,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  image.width == w, image.height == h else { throw SkinAssetError.cursorFormat }
            let normalized = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(normalized, UTType.png.identifier as CFString, 1, nil)
            else { throw SkinAssetError.cursorFormat }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw SkinAssetError.cursorFormat }
            if best == nil || w * h > best!.width * best!.height {
                best = (normalized as Data, w, h, x, y)
            }
        }
        guard let best else { throw SkinAssetError.cursorFormat }
        let scale = min(1, 32.0 / Double(max(best.width, best.height)))
        let width = max(1, Int((Double(best.width) * scale).rounded()))
        let height = max(1, Int((Double(best.height) * scale).rounded()))
        guard let source = CGImageSourceCreateWithData(best.png as CFData, nil),
              let master = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw SkinAssetError.cursorFormat }
        // The cursor service requires exact 1x and 2x representations. Keep an
        // additional native-density image when the original has more detail.
        let nativeDensity = Int(ceil(max(Double(best.width) / Double(width), Double(best.height) / Double(height))))
        let densities = nativeDensity > 2 ? [1, 2, nativeDensity] : [1, 2]
        let pngs: [Data] = try densities.map { density in
            guard let context = CGContext(data: nil, width: width * density, height: height * density,
                bitsPerComponent: 8, bytesPerRow: width * density * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw SkinAssetError.cursorFormat }
            context.interpolationQuality = .high
            context.draw(master, in: CGRect(x: 0, y: 0, width: width * density, height: height * density))
            let data = NSMutableData()
            guard let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
            else { throw SkinAssetError.cursorFormat }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw SkinAssetError.cursorFormat }
            return data as Data
        }
        return ["PointsWide": Double(width), "PointsHigh": Double(height),
                "HotSpotX": Double(best.x) * Double(width) / Double(best.width),
                "HotSpotY": Double(best.y) * Double(height) / Double(best.height),
                "FrameCount": 1, "FrameDuration": 0.0, "Representations": pngs]
    }
}

/// A local checksum detects damaged storage; it is not an author signature.
enum ImportedSkinPackage {
    static let maximumBytes = 8 * 1024 * 1024
    static let roleNames: Set<String> = ["arrow", "text", "link", "grab", "crosshair", "horizontal", "vertical",
                                       "diagonalRight", "diagonalLeft", "unavailable", "help", "zoomIn", "zoomOut"]
    static func create(id: String, arrow: URL, link: URL) throws -> Data {
        guard FeaturedSkin.find(id) != nil else { throw SkinAssetError.format }
        var roles = Dictionary(uniqueKeysWithValues: roleNames.map { ($0, ["RestoreOriginal": true] as [String: Any]) })
        roles["arrow"] = try StaticCursorImporter.descriptor(at: arrow)
        roles["link"] = try StaticCursorImporter.descriptor(at: link)
        return try wrap(id: id, roles: roles)
    }
    static func wrap(id: String, roles: [String: [String: Any]]) throws -> Data {
        let payload = try PropertyListSerialization.data(fromPropertyList:
            ["FormatVersion": 1, "Identifier": id, "Roles": roles], format: .binary, options: 0)
        let data = try PropertyListSerialization.data(fromPropertyList:
            ["FormatVersion": 1, "Identifier": id, "Payload": payload, "SHA256": digest(payload)],
            format: .binary, options: 0)
        _ = try validate(data, id: id)
        return data
    }
    static func validate(_ data: Data, id: String) throws -> [String: [String: Any]] {
        guard FeaturedSkin.find(id) != nil, data.count <= maximumBytes,
              let wrapper = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              wrapper["FormatVersion"] as? Int == 1, wrapper["Identifier"] as? String == id,
              let payload = wrapper["Payload"] as? Data, let hash = wrapper["SHA256"] as? String,
              digest(payload) == hash else { throw SkinAssetError.integrity }
        guard let root = try? PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any],
              root["FormatVersion"] as? Int == 1, root["Identifier"] as? String == id,
              let roles = root["Roles"] as? [String: [String: Any]] else { throw SkinAssetError.format }
        _ = try SkinPackageValidator.validateRoles(roles, requiredRoles: roleNames,
            restoredRoles: roleNames.subtracting(["arrow", "link"]))
        for name in ["arrow", "link"] {
            let role = roles[name]!
            let w = role["PointsWide"] as! Double, h = role["PointsHigh"] as! Double
            let pngs = role["Representations"] as! [Data]
            guard w.rounded() == w, h.rounded() == h, w <= 32, h <= 32,
                  (2...6).contains(pngs.count) else { throw SkinAssetError.format }
            var previousWidth = 0
            for (index, png) in pngs.enumerated() {
                let source = CGImageSourceCreateWithData(png as CFData, nil)!
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
                let width = properties[kCGImagePropertyPixelWidth] as! Int
                let height = properties[kCGImagePropertyPixelHeight] as! Int
                guard width > previousWidth, Double(width) / w == Double(height) / h,
                      index >= 2 || (Double(width) == w * Double(index + 1) && Double(height) == h * Double(index + 1))
                else { throw SkinAssetError.format }
                previousWidth = width
            }
        }
        return roles
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
