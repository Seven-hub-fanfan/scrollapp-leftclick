import AppKit

@main struct GenerateSkinPreviews {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        for package in SkinPackage.all {
            let data = try Data(contentsOf: directory.appendingPathComponent(package.filename))
            let original = try SkinPackageValidator.validate(data, package: package)
            let roles = CursorCatalog.resolvedRoles(original, themeID: package.id)
            let name = CursorCatalog.theme(package.id).resource!
            for role in CursorRole.allCases {
                guard let descriptor = roles[role.rawValue], descriptor["RestoreOriginal"] as? Bool != true,
                      let pngs = descriptor["Representations"] as? [Data],
                      let best = pngs.max(by: { CursorCatalog.pixelWidth($0) < CursorCatalog.pixelWidth($1) }),
                      let image = NSImage(data: best) else { continue }
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSGraphicsContext.current?.imageInterpolation = .high
                image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
                NSGraphicsContext.restoreGraphicsState()
                let png = bitmap.representation(using: .png, properties: [:])!
                try png.write(to: directory.appendingPathComponent("\(name)-\(role.rawValue).png"), options: .atomic)
            }
        }
    }
}
