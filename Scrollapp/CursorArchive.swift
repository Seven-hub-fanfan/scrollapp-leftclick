import Foundation
import Compression

/// Reads only cursor entries in memory. Never extracts paths or executes pack files.
enum CursorArchiveImporter {
    static func roles(_ data: Data, id: String) throws -> [String: [String: Any]] {
        guard data.count >= 22, data.count <= 8 * 1024 * 1024 else { throw SkinAssetError.format }
        func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int {
            Int(data[offset]) | Int(data[offset + 1]) << 8 |
                Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
        }
        let lower = max(0, data.count - 65_557)
        guard let end = stride(from: data.count - 22, through: lower, by: -1).first(where: {
            u32($0) == 0x06054b50 && $0 + 22 + u16($0 + 20) == data.count
        }), u16(end + 4) == 0, u16(end + 6) == 0 else { throw SkinAssetError.format }
        let count = u16(end + 10), centralSize = u32(end + 12), centralOffset = u32(end + 16)
        guard (1...128).contains(count), u16(end + 8) == count,
              centralOffset <= end, centralSize == end - centralOffset else { throw SkinAssetError.format }
        var offset = centralOffset, expandedBytes = 0
        var names: Set<String> = []
        var ranges: [Range<Int>] = []
        var cursors: [String: [String: Any]] = [:]
        for _ in 0..<count {
            guard offset <= end - 46, u32(offset) == 0x02014b50 else { throw SkinAssetError.format }
            let flags = u16(offset + 8), method = u16(offset + 10)
            var size = u32(offset + 24), compressedSize = u32(offset + 20), local = u32(offset + 42)
            let nameLength = u16(offset + 28), extraLength = u16(offset + 30), commentLength = u16(offset + 32)
            let next = offset + 46 + nameLength + extraLength + commentLength
            guard next <= end else { throw SkinAssetError.format }
            // The official packs use ZIP64 entry sizes even for small files.
            // Accept only bounded values, with the upper 32 bits zero.
            var extra = offset + 46 + nameLength
            let extraEnd = extra + extraLength
            var zip64: Range<Int>?
            while extra < extraEnd {
                guard extra <= extraEnd - 4 else { throw SkinAssetError.format }
                let tag = u16(extra), length = u16(extra + 2)
                guard length <= extraEnd - extra - 4 else { throw SkinAssetError.format }
                if tag == 1 {
                    guard zip64 == nil else { throw SkinAssetError.format }
                    zip64 = (extra + 4)..<(extra + 4 + length)
                }
                extra += 4 + length
            }
            if size == Int(UInt32.max) || compressedSize == Int(UInt32.max) || local == Int(UInt32.max) {
                guard let zip64 else { throw SkinAssetError.format }
                var value = zip64.lowerBound
                func bounded64() throws -> Int {
                    guard value <= zip64.upperBound - 8, u32(value + 4) == 0 else { throw SkinAssetError.format }
                    defer { value += 8 }
                    return u32(value)
                }
                if size == Int(UInt32.max) { size = try bounded64() }
                if compressedSize == Int(UInt32.max) { compressedSize = try bounded64() }
                if local == Int(UInt32.max) { local = try bounded64() }
            }
            guard next <= end, flags & 1 == 0, [0, 8].contains(method), u16(offset + 34) == 0,
                  size <= StaticCursorImporter.maximumBytes, compressedSize <= data.count,
                  let name = String(data: data.subdata(in: (offset + 46)..<(offset + 46 + nameLength)), encoding: .utf8),
                  !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"),
                  !name.split(separator: "/").contains(".."), names.insert(name).inserted
            else { throw SkinAssetError.format }
            expandedBytes += size
            guard expandedBytes <= 16 * 1024 * 1024, local <= centralOffset - 30,
                  u32(local) == 0x04034b50, u16(local + 6) == flags, u16(local + 8) == method
            else { throw SkinAssetError.format }
            let localNameLength = u16(local + 26), localExtraLength = u16(local + 28)
            let start = local + 30 + localNameLength + localExtraLength
            guard start <= centralOffset, compressedSize <= centralOffset - start,
                  localNameLength == nameLength,
                  data.subdata(in: (local + 30)..<(local + 30 + localNameLength)) ==
                    data.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            else { throw SkinAssetError.format }
            let occupied = local..<(start + compressedSize)
            guard !ranges.contains(where: { $0.overlaps(occupied) }) else { throw SkinAssetError.format }
            ranges.append(occupied)
            if name.lowercased().hasSuffix(".cur") {
                let role: String
                if name.lowercased().contains("--cursor--") { role = "arrow" }
                else if name.lowercased().contains("--pointer--") { role = "link" }
                else { throw SkinAssetError.format }
                guard cursors[role] == nil, size > 0, compressedSize > 0 else { throw SkinAssetError.format }
                let packed = data.subdata(in: start..<(start + compressedSize))
                let decoded: Data
                if method == 0 {
                    guard packed.count == size else { throw SkinAssetError.format }
                    decoded = packed
                } else {
                    var bytes = [UInt8](repeating: 0, count: size + 1)
                    let actual = packed.withUnsafeBytes { raw in
                        bytes.withUnsafeMutableBufferPointer { output in
                            compression_decode_buffer(output.baseAddress!, output.count,
                                raw.bindMemory(to: UInt8.self).baseAddress!, packed.count, nil, COMPRESSION_ZLIB)
                        }
                    }
                    guard actual == size else { throw SkinAssetError.format }
                    decoded = Data(bytes.prefix(size))
                }
                cursors[role] = try StaticCursorImporter.descriptor(from: decoded)
            }
            offset = next
        }
        guard offset == end, cursors.count == 2 else { throw SkinAssetError.format }
        for role in ImportedSkinPackage.roleNames.subtracting(["arrow", "link"]) {
            cursors[role] = ["RestoreOriginal": true]
        }
        // Validate the same normalized representation contract as local storage.
        _ = try ImportedSkinPackage.wrap(id: id, roles: cursors)
        return cursors
    }
}
