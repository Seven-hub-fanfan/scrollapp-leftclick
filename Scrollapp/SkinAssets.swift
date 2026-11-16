import Foundation
import Combine
import CryptoKit
import ImageIO

struct SkinPackage {
    let id: String
    let filename: String
    let byteCount: Int
    let sha256: String
    let requiredRoles: Set<String>
    var isCursorArchive = false
    var isBundled = false
    var url: URL {
        if isBundled {
            return (Bundle.main.resourceURL ?? Bundle.main.bundleURL)
                .appendingPathComponent("Skins", isDirectory: true).appendingPathComponent(filename)
        }
        if let skin = FeaturedSkin.find(id) {
            return skin.sourceURL.appendingPathComponent("downloads/complete-pack/")
        }
        return URL(string: "https://github.com/Seven-hub-fanfan/scrollapp-leftclick/releases/download/skins-v1/\(filename)")!
    }
    static let all: [SkinPackage] = [
        .init(id: "doubao", filename: "Doubao.plist", byteCount: 2358739,
              sha256: "9cb3d564be31c2c9086e0322baf6b9f6f0537f3c47e6faad2faf6e360ee77d64",
              requiredRoles: ImportedSkinPackage.roleNames, isBundled: true),
        .init(id: "frog", filename: "Frog.plist", byteCount: 569856,
              sha256: "e3c8df3f7c14ac7554101cbf757cee445cb38764af42a63add61f2c0300525dd",
              requiredRoles: ["arrow", "text", "link", "grab", "crosshair", "horizontal", "vertical", "unavailable", "help"]),
        .init(id: "xiaoqi", filename: "Xiaoqi.plist", byteCount: 3060458,
              sha256: "ab2328268f3b7f122766c6d6b7156d2fbfbfbfd2e8ab6e1804dae99eba6304cc",
              requiredRoles: ["arrow", "text", "link", "grab", "crosshair", "horizontal", "vertical",
                              "diagonalRight", "diagonalLeft", "unavailable", "help", "zoomIn", "zoomOut"])
    ] + FeaturedSkin.all.map {
        .init(id: $0.id, filename: "\($0.id).zip", byteCount: $0.archiveByteCount, sha256: $0.archiveSHA256,
              requiredRoles: ImportedSkinPackage.roleNames, isCursorArchive: true)
    }
    static func find(_ id: String) -> SkinPackage? { all.first { $0.id == id } }
}

enum SkinAssetError: String, Error {
    case network, integrity, format, storage
    case unsupportedCursor, cursorFormat
}

enum SkinPackageValidator {
    static func validate(_ data: Data, package: SkinPackage) throws -> [String: [String: Any]] {
        guard data.count == package.byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == package.sha256
        else { throw SkinAssetError.integrity }
        return try validateStructure(data, package: package)
    }

    static func validateStructure(_ data: Data, package: SkinPackage) throws -> [String: [String: Any]] {
        if package.isCursorArchive { return try CursorArchiveImporter.roles(data, id: package.id) }
        guard data.count <= 8 * 1024 * 1024,
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              root["FormatVersion"] as? Int == 1, root["Identifier"] as? String == package.id,
              let roles = root["Roles"] as? [String: [String: Any]],
              Set(roles.keys) == package.requiredRoles else { throw SkinAssetError.format }
        return try validateRoles(roles, requiredRoles: package.requiredRoles, restoredRoles: ["zoomIn", "zoomOut"])
    }

    static func validateRoles(_ roles: [String: [String: Any]], requiredRoles: Set<String>,
                              restoredRoles: Set<String>) throws -> [String: [String: Any]] {
        guard Set(roles.keys) == requiredRoles else { throw SkinAssetError.format }
        var totalPixels = 0
        for (role, descriptor) in roles {
            if descriptor["RestoreOriginal"] as? Bool == true {
                guard restoredRoles.contains(role), descriptor.count == 1 else { throw SkinAssetError.format }
                continue
            }
            guard let width = descriptor["PointsWide"] as? Double,
                  let height = descriptor["PointsHigh"] as? Double,
                  let x = descriptor["HotSpotX"] as? Double, let y = descriptor["HotSpotY"] as? Double,
                  [width, height, x, y].allSatisfy(\.isFinite),
                  width > 0, width <= 256, height > 0, height <= 256,
                  x >= 0, x < width, y >= 0, y < height,
                  descriptor["FrameCount"] as? Int == 1,
                  descriptor["FrameDuration"] as? Double == 0,
                  let pngs = descriptor["Representations"] as? [Data],
                  !pngs.isEmpty, pngs.count <= 8 else { throw SkinAssetError.format }
            for png in pngs {
                guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                      CGImageSourceGetCount(source) == 1,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let w = properties[kCGImagePropertyPixelWidth] as? Int,
                      let h = properties[kCGImagePropertyPixelHeight] as? Int,
                      w > 0, h > 0, w <= 2048, h <= 2048 else { throw SkinAssetError.format }
                totalPixels += w * h
                guard totalPixels <= 32 * 1024 * 1024,
                      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw SkinAssetError.format }
            }
        }
        return roles
    }
}

/// Serial URLSession callbacks keep bytes bounded before they reach the plist/image decoders.
/// Each transfer owns its session; invalidation breaks the delegate retain cycle on every exit.
final class SkinDownload: NSObject, URLSessionDataDelegate {
    let token = UUID()
    private let package: SkinPackage
    private let progress: (Double) -> Void
    private let completion: (Result<Data, SkinAssetError>) -> Void
    private let prepareRoles: ((String, [String: [String: Any]]) throws -> Void)?
    private var bytes = Data()
    private var failure: SkinAssetError?
    private var session: URLSession!
    private var task: URLSessionDataTask?

    init(package: SkinPackage, configuration: URLSessionConfiguration = .ephemeral,
         prepareRoles: ((String, [String: [String: Any]]) throws -> Void)? = nil,
         progress: @escaping (Double) -> Void, completion: @escaping (Result<Data, SkinAssetError>) -> Void) {
        self.package = package; self.progress = progress; self.completion = completion; self.prepareRoles = prepareRoles
        super.init()
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }
    func start() {
        task = session.dataTask(with: package.url)
        task?.resume()
    }
    func cancel() { task?.cancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else {
            failure = .network; completionHandler(nil); return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https" else {
            failure = .network; completionHandler(.cancel); return
        }
        guard response.expectedContentLength < 0 || response.expectedContentLength == Int64(package.byteCount)
        else { failure = .integrity; completionHandler(.cancel); return }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        guard data.count <= package.byteCount - bytes.count else {
            failure = .integrity; dataTask.cancel(); return
        }
        bytes.append(data)
        progress(Double(bytes.count) / Double(package.byteCount))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.invalidateAndCancel() }
        if let failure { completion(.failure(failure)); return }
        guard error == nil else { completion(.failure(.network)); return }
        do {
            let roles = try SkinPackageValidator.validate(bytes, package: package)
            try prepareRoles?(package.id, roles)
            let installed = package.isCursorArchive ? try ImportedSkinPackage.wrap(id: package.id, roles: roles) : bytes
            completion(.success(installed))
        } catch {
            completion(.failure((error as? SkinAssetError) ?? .format))
        }
    }
}

/// Main-thread model. A cancelled transfer's token can never install over a newer attempt.
final class SkinAssetStore: ObservableObject {
    #if SCROLLAPP_TESTING
    static var shared = SkinAssetStore()
    #else
    static let shared = SkinAssetStore()
    #endif
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var importing: Set<String> = []
    private var jobs: [String: SkinDownload] = [:]
    let directory: URL
    var didChange: ((String) -> Void)?
    var prepareRoles: ((String, [String: [String: Any]]) throws -> Void)?

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Scrollapp/Skins", isDirectory: true)) {
        self.directory = directory
        for package in SkinPackage.all {
            let url = fileURL(package)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                _ = try validatedRoles(package)
                installed.insert(package.id)
            } catch { errors[package.id] = "integrity" }
        }
    }
    func isInstalled(_ id: String) -> Bool { id == "system" || installed.contains(id) }
    func fileURL(_ package: SkinPackage) -> URL {
        if package.isBundled { return package.url }
        return package.isCursorArchive ? importedFileURL(package.id) : directory.appendingPathComponent("\(package.id)-v1.plist")
    }
    func validatedRoles(_ package: SkinPackage) throws -> [String: [String: Any]] {
        let url = fileURL(package)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        if package.isCursorArchive {
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0, size <= ImportedSkinPackage.maximumBytes else { throw SkinAssetError.integrity }
            return try ImportedSkinPackage.validate(Data(contentsOf: url), id: package.id)
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == package.byteCount
        else { throw SkinAssetError.integrity }
        return try SkinPackageValidator.validate(Data(contentsOf: url), package: package)
    }
    func diskBytes(_ id: String) -> Int? {
        guard let package = SkinPackage.find(id) else { return nil }
        if package.isBundled { return package.byteCount }
        let base = (try? fileURL(package).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let states = (try? directory.appendingPathComponent("\(id)-states-v1.plist")
            .resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return base + states
    }
    func importedFileURL(_ id: String) -> URL { directory.appendingPathComponent("\(id)-local-v1.plist") }
    func validatedRoles(_ id: String) throws -> [String: [String: Any]] {
        if let package = SkinPackage.find(id) { return try validatedRoles(package) }
        guard FeaturedSkin.find(id) != nil else { throw SkinAssetError.format }
        let url = importedFileURL(id)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= ImportedSkinPackage.maximumBytes
        else { throw SkinAssetError.integrity }
        return try ImportedSkinPackage.validate(Data(contentsOf: url), id: id)
    }
    func importSkin(_ id: String, arrow: URL, link: URL, completion: @escaping (Bool) -> Void) {
        guard FeaturedSkin.find(id) != nil, !isInstalled(id), !importing.contains(id) else { completion(false); return }
        importing.insert(id); errors[id] = nil
        let identity = UUID()
        generations[id] = identity
        let preparation = prepareRoles
        DispatchQueue.global(qos: .userInitiated).async {
            let result: Result<Data, Error> = Result {
                let data = try ImportedSkinPackage.create(id: id, arrow: arrow, link: link)
                try preparation?(id, ImportedSkinPackage.validate(data, id: id))
                return data
            }
            DispatchQueue.main.async {
                guard self.generations[id] == identity else { completion(false); return }
                self.generations[id] = nil; self.importing.remove(id)
                do {
                    let data = try result.get()
                    do {
                        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                                                attributes: [.posixPermissions: 0o700])
                        try data.write(to: self.importedFileURL(id), options: .atomic)
                    } catch { throw SkinAssetError.storage }
                    self.installed.insert(id); self.errors[id] = nil
                    self.didChange?(id)
                    completion(true)
                } catch {
                    self.errors[id] = (error as? SkinAssetError)?.rawValue ?? SkinAssetError.cursorFormat.rawValue
                    completion(false)
                }
            }
        }
    }
    func download(_ id: String, configuration: URLSessionConfiguration = .ephemeral) {
        guard let package = SkinPackage.find(id), !package.isBundled,
              jobs[id] == nil, !isInstalled(id) else { return }
        errors[id] = nil; progress[id] = 0
        // Capture a stable identity before resuming; queued callbacks from cancellation are ignored.
        let identity = UUID()
        generations[id] = identity
        let transfer = SkinDownload(package: package, configuration: configuration, prepareRoles: prepareRoles, progress: { [weak self] value in
            DispatchQueue.main.async {
                guard let self, self.generations[id] == identity else { return }
                self.progress[id] = value
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.generations[id] == identity else { return }
                self.jobs[id] = nil; self.generations[id] = nil; self.progress[id] = nil
                switch result {
                case .success(let data):
                    do {
                        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                                                attributes: [.posixPermissions: 0o700])
                        try data.write(to: self.fileURL(package), options: .atomic)
                        self.installed.insert(id); self.errors[id] = nil
                        self.didChange?(id)
                    } catch { self.errors[id] = SkinAssetError.storage.rawValue }
                case .failure(let error): self.errors[id] = error.rawValue
                }
            }
        })
        jobs[id] = transfer; transfer.start()
    }
    private var generations: [String: UUID] = [:]
    func cancel(_ id: String) {
        generations[id] = nil
        jobs.removeValue(forKey: id)?.cancel()
        importing.remove(id); progress[id] = nil; errors[id] = nil
    }
    /// Caller must first restore an active theme through CursorSkinStore.
    @discardableResult func remove(_ id: String) -> Bool {
        guard SkinPackage.find(id)?.isBundled != true, jobs[id] == nil, !importing.contains(id),
              SkinPackage.find(id) != nil || FeaturedSkin.find(id) != nil else { return false }
        do {
            let url = SkinPackage.find(id).map(fileURL) ?? importedFileURL(id)
            if FeaturedSkin.find(id) != nil {
                let states = directory.appendingPathComponent("\(id)-states-v1.plist")
                if FileManager.default.fileExists(atPath: states.path) { try FileManager.default.removeItem(at: states) }
            }
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            installed.remove(id); errors[id] = nil
            didChange?(id)
            return true
        } catch { errors[id] = SkinAssetError.storage.rawValue; return false }
    }
}
