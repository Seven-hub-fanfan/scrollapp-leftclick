import Foundation
import CryptoKit

final class FixtureProtocol: URLProtocol {
    static var body = Data()
    static var status = 200
    static var mode = "success"
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        if Self.mode == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let headers = Self.mode == "oversized-header" ? ["Content-Length": "999999999"] : [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if Self.mode == "hold" { return }
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct VerifySkinAssets {
    static func spin(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        precondition(condition(), "Async operation timed out")
    }
    static func main() throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scrollapp-assets-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var checks: [String] = []
        let frog = SkinPackage.find("frog")!
        let data = try Data(contentsOf: source.appendingPathComponent(frog.filename))
        for package in SkinPackage.all.filter({ !$0.isCursorArchive }) {
            let bytes = try Data(contentsOf: source.appendingPathComponent(package.filename))
            _ = try SkinPackageValidator.validate(bytes, package: package)
            checks.append("\(package.id)-official-hash-and-images")
        }
        var corrupt = data; corrupt[corrupt.count - 1] ^= 1
        do { _ = try SkinPackageValidator.validate(corrupt, package: frog); fatalError("Bad hash accepted") }
        catch SkinAssetError.integrity { checks.append("checksum-rejection") }
        var root = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        var roles = root["Roles"] as! [String: [String: Any]]
        roles["arrow"]?["HotSpotX"] = Double.infinity
        root["Roles"] = roles
        let malformed = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        do { _ = try SkinPackageValidator.validateStructure(malformed, package: frog); fatalError("Infinite hotspot accepted") }
        catch SkinAssetError.format { checks.append("metadata-rejection") }
        roles["arrow"]?["HotSpotX"] = 6
        roles["arrow"]?["Representations"] = [Data("bad image".utf8)]; root["Roles"] = roles
        let badImage = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        do { _ = try SkinPackageValidator.validateStructure(badImage, package: frog); fatalError("Invalid image accepted") }
        catch SkinAssetError.format { checks.append("image-rejection") }

        let store = SkinAssetStore(directory: directory)
        var invalidations = 0
        store.didChange = { _ in invalidations += 1 }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        func transfer(_ bytes: Data, mode: String = "success", status: Int = 200) {
            FixtureProtocol.body = bytes; FixtureProtocol.mode = mode; FixtureProtocol.status = status
            store.download("frog", configuration: config)
            spin { store.progress["frog"] == nil }
        }
        transfer(data)
        precondition(store.isInstalled("frog") && invalidations == 1)
        let saved = try Data(contentsOf: store.fileURL(frog))
        precondition(saved == data)
        checks.append("atomic-download-install")
        let offline = SkinAssetStore(directory: directory)
        precondition(offline.isInstalled("frog"))
        checks.append("offline-installed-relaunch")
        precondition(store.remove("frog") && !store.isInstalled("frog") && invalidations == 2)
        precondition(!FileManager.default.fileExists(atPath: store.fileURL(frog).path))
        checks.append("delete-and-invalidate")
        for (name, bytes, mode, status, expected) in [
            ("offline-error", data, "offline", 200, "network"),
            ("http-error", data, "success", 404, "network"),
            ("truncated", Data(data.dropLast()), "success", 200, "integrity"),
            ("too-many-bytes", data + Data([0]), "success", 200, "integrity"),
            ("oversized-header", data, "oversized-header", 200, "integrity"),
            ("bad-download-hash", corrupt, "success", 200, "integrity")
        ] {
            transfer(bytes, mode: mode, status: status)
            precondition(store.errors["frog"] == expected && !store.isInstalled("frog"), name)
            precondition(!FileManager.default.fileExists(atPath: store.fileURL(frog).path))
            checks.append(name)
        }
        FixtureProtocol.mode = "hold"; FixtureProtocol.status = 200
        let before = FixtureProtocol.requests
        store.download("frog", configuration: config); store.download("frog", configuration: config)
        spin { FixtureProtocol.requests == before + 1 }
        precondition(FixtureProtocol.requests == before + 1)
        checks.append("duplicate-request-suppressed")
        store.cancel("frog")
        precondition(store.progress["frog"] == nil && store.errors["frog"] == nil && !store.isInstalled("frog"))
        transfer(data)
        precondition(store.isInstalled("frog"), "Cancelled callback overwrote subsequent download")
        checks.append("cancel-and-immediate-retry")
        try corrupt.write(to: store.fileURL(frog), options: .atomic)
        let reload = SkinAssetStore(directory: directory)
        precondition(!reload.isInstalled("frog") && reload.errors["frog"] == "integrity")
        checks.append("corrupt-local-resource-on-relaunch")
        precondition(reload.remove("frog"))
        let blocker = directory.appendingPathComponent("file-not-directory")
        try data.write(to: blocker)
        let blocked = SkinAssetStore(directory: blocker)
        blocked.download("frog", configuration: config)
        spin { blocked.progress["frog"] == nil }
        precondition(blocked.errors["frog"] == "storage" && !blocked.isInstalled("frog"))
        checks.append("disk-write-failure")
        let result: [String: Any] = ["passed": true, "checks": checks]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}
