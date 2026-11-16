import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import Security
import LocalAuthentication

enum VisionWireFormat: String, Codable, CaseIterable {
    case openAI, gemini, anthropic
    var label: String {
        switch self {
        case .openAI: return "OpenAI Compatible"
        case .gemini: return "Gemini"
        case .anthropic: return "Anthropic"
        }
    }
}

struct VisionProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var preset: String
    var format: VisionWireFormat
    var baseURL: String
    var model: String
    var requiresKey = true

    static let presets: [VisionProfile] = [
        .init(name: "OpenAI", preset: "openai", format: .openAI,
              baseURL: "https://api.openai.com/v1", model: "gpt-4.1-mini"),
        .init(name: "Gemini", preset: "gemini", format: .gemini,
              baseURL: "https://generativelanguage.googleapis.com/v1beta", model: "gemini-2.5-flash"),
        .init(name: "Claude", preset: "anthropic", format: .anthropic,
              baseURL: "https://api.anthropic.com/v1", model: "claude-sonnet-4-5"),
        .init(name: "Qwen", preset: "qwen", format: .openAI,
              baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-vl-max"),
        .init(name: "Volcengine", preset: "volcengine", format: .openAI,
              baseURL: "https://ark.cn-beijing.volces.com/api/v3", model: ""),
        .init(name: "Zhipu", preset: "zhipu", format: .openAI,
              baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4.5v"),
        .init(name: "OpenRouter", preset: "openrouter", format: .openAI,
              baseURL: "https://openrouter.ai/api/v1", model: "google/gemini-2.5-flash"),
        .init(name: "Ollama", preset: "ollama", format: .openAI,
              baseURL: "http://localhost:11434/v1", model: "llava", requiresKey: false),
        .init(name: "Custom", preset: "custom", format: .openAI,
              baseURL: "", model: "")
    ]
    func freshCopy() -> VisionProfile {
        var copy = self
        copy.id = UUID()
        return copy
    }
    var displayName: String {
        if name == "Custom" { return L10n.t("prompt.custom") }
        if name == "Volcengine" { return L10n.t("prompt.volcengine") }
        return name
    }
    func endpoint(suffix: String) throws -> URL {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: raw),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.scheme == "https" ||
                (components.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host))
        else { throw VisionFailure.key("endpoint") }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([components.path, suffix].filter { !$0.isEmpty }.joined(separator: "/"))
        guard let url = components.url else { throw VisionFailure.key("endpoint") }
        return url
    }
}

enum VisionFailure: LocalizedError {
    case key(String)
    case http(Int, String)
    case detail(String)
    var errorDescription: String? {
        switch self {
        case .key(let key): return L10n.t("prompt.error.\(key)")
        case .http(let status, let message):
            let key = status == 401 || status == 403 ? "auth" :
                status == 429 ? "rate" : status == 404 ? "model" : "server"
            let hint = L10n.t("prompt.error.\(key)")
            return message.isEmpty ? "\(hint) (\(status))" : "\(hint) (\(status))\n\(message)"
        case .detail(let value): return value
        }
    }
}

struct PromptImage: Identifiable, Sendable {
    let id: UUID
    let title: String
    let origin: String
    let width: Int
    let height: Int
    let data: Data
    let thumbnail: Data
    var dimensions: String { "\(width) × \(height)" }
    var ratio: String {
        var a = width, b = height
        while b != 0 { let remainder = a % b; a = b; b = remainder }
        return "\(width / max(a, 1)):\(height / max(a, 1))"
    }
}

enum PromptImageDecoder {
    static let maximumBytes = 32 * 1024 * 1024
    static func decode(_ data: Data, title: String, origin: String = "", id: UUID = UUID()) throws -> PromptImage {
        guard !data.isEmpty, data.count <= maximumBytes else { throw VisionFailure.key("imageSize") }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = info[kCGImagePropertyPixelWidth] as? Int,
              let h = info[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 40_000, h <= 40_000, Int64(w) * Int64(h) <= 250_000_000
        else { throw VisionFailure.key("image") }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw VisionFailure.key("image")
        }
        let encoded = try jpeg(image, quality: 0.88)
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 240,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary
        let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) ?? image
        let orientation = info[kCGImagePropertyOrientation] as? Int ?? 1
        return PromptImage(id: id, title: title, origin: origin,
                           width: (5...8).contains(orientation) ? h : w,
                           height: (5...8).contains(orientation) ? w : h,
                           data: encoded, thumbnail: try jpeg(thumb, quality: 0.8))
    }
    private static func jpeg(_ image: CGImage, quality: Double) throws -> Data {
        // Flatten alpha to a neutral white matte; never send a huge source raster.
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw VisionFailure.key("image") }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flattened = context.makeImage() else { throw VisionFailure.key("image") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw VisionFailure.key("image")
        }
        CGImageDestinationAddImage(destination, flattened,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw VisionFailure.key("image") }
        return output as Data
    }
    static func file(_ url: URL) throws -> PromptImage {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? maximumBytes + 1) <= maximumBytes else {
            throw VisionFailure.key("imageSize")
        }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe), title: url.lastPathComponent)
    }
    static func remote(_ url: URL) async throws -> PromptImage {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw VisionFailure.key("imageURL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VisionFailure.key("download")
        }
        if let mime = response.mimeType, !mime.hasPrefix("image/") && mime != "application/octet-stream" {
            throw VisionFailure.key("imageURL")
        }
        guard response.expectedContentLength <= maximumBytes else { throw VisionFailure.key("imageSize") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw VisionFailure.key("imageSize") }
            data.append(byte)
        }
        // Signed query parameters are never persisted in history.
        var clean = URLComponents(url: url, resolvingAgainstBaseURL: false)
        clean?.query = nil; clean?.fragment = nil; clean?.user = nil; clean?.password = nil
        return try decode(data, title: url.lastPathComponent.isEmpty ? L10n.t("prompt.webImage") : url.lastPathComponent,
                          origin: clean?.string ?? "")
    }
}

struct VisionResult: Codable, Equatable, Sendable {
    var chinese: String
    var english: String
    var negative: String
    var tags: [String]
    var raw: String

    static func parse(_ text: String) throws -> VisionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VisionFailure.key("empty") }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"),
           start < end, let data = String(trimmed[start...end]).data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let cn = object["prompt_cn"] as? String ?? ""
            let en = object["prompt_en"] as? String ?? ""
            if !cn.isEmpty || !en.isEmpty {
                return .init(chinese: cn, english: en,
                             negative: object["negative_prompt"] as? String ?? "",
                             tags: object["tags"] as? [String] ?? [], raw: String(trimmed[start...end]))
            }
        }
        // Some compatible models ignore the requested schema. Keep the actual
        // response readable and exportable rather than fabricating translations.
        return .init(chinese: trimmed, english: "", negative: "", tags: [], raw: trimmed)
    }
    func content(_ tab: String) -> String {
        switch tab {
        case "en": return english
        case "json": return raw
        case "negative": return negative
        default: return chinese.isEmpty ? english : chinese
        }
    }
    static func partial(_ raw: String, tab: String) -> String {
        if tab == "json" { return raw }
        let key = tab == "en" ? "prompt_en" : tab == "negative" ? "negative_prompt" : "prompt_cn"
        guard let range = raw.range(of: "\"\(key)\""),
              let colon = raw[range.upperBound...].firstIndex(of: ":"),
              let quote = raw[raw.index(after: colon)...].firstIndex(of: "\"") else {
            return raw.hasPrefix("{") ? L10n.t("prompt.analyzing") : raw
        }
        var value = "", escaped = false
        for character in raw[raw.index(after: quote)...] {
            if character == "\"" && !escaped { break }
            value.append(character)
            if character == "\\" && !escaped { escaped = true } else { escaped = false }
        }
        if escaped { value.removeLast() }
        if let data = "[\"\(value)\"]".data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String], let text = array.first {
            return text
        }
        return value
    }
}

struct PromptHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var title: String
    var origin: String
    var width: Int
    var height: Int
    var provider: String
    var model: String
    var template: String
    var instructions: String
    var favorite: Bool
    var result: VisionResult
}

enum VisionWire {
    static func request(profile: VisionProfile, key: String, image: Data, instructions: String) throws -> URLRequest {
        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw VisionFailure.key("modelMissing") }
        guard !profile.requiresKey || !key.isEmpty else { throw VisionFailure.key("keyMissing") }
        let encoded = image.base64EncodedString()
        var body: [String: Any]
        let endpoint: URL
        switch profile.format {
        case .openAI:
            endpoint = try profile.endpoint(suffix: "chat/completions")
            body = ["model": model, "stream": true, "max_tokens": 2400,
                    "messages": [
                        ["role": "system", "content": instructions],
                        ["role": "user", "content": [
                            ["type": "text", "text": "Analyze this reference image."],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(encoded)"]]
                        ]]
                    ]]
        case .gemini:
            // A model ID is one path component, not an endpoint or query.
            guard !model.contains("/"), !model.contains("?"), !model.contains("#") else {
                throw VisionFailure.key("modelMissing")
            }
            let base = try profile.endpoint(suffix: "models/\(model):streamGenerateContent")
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            endpoint = components.url!
            body = ["systemInstruction": ["parts": [["text": instructions]]],
                    "contents": [["role": "user", "parts": [
                        ["text": "Analyze this reference image."],
                        ["inlineData": ["mimeType": "image/jpeg", "data": encoded]]
                    ]]],
                    "generationConfig": ["maxOutputTokens": 4096]]
        case .anthropic:
            endpoint = try profile.endpoint(suffix: "messages")
            body = ["model": model, "max_tokens": 2400, "stream": true, "system": instructions,
                    "messages": [["role": "user", "content": [
                        ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": encoded]],
                        ["type": "text", "text": "Analyze this reference image."]
                    ]]]]
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        switch profile.format {
        case .openAI:
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        case .gemini:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func chunk(_ object: [String: Any], format: VisionWireFormat, streaming: Bool) throws -> String {
        if let error = object["error"] as? [String: Any] {
            let message = error["message"] as? String ?? L10n.t("prompt.error.server")
            throw VisionFailure.detail(String(message.prefix(500)))
        }
        switch format {
        case .openAI:
            let choices = object["choices"] as? [[String: Any]] ?? []
            let message = choices.first?[streaming ? "delta" : "message"] as? [String: Any] ?? [:]
            if let content = message["content"] as? String { return content }
            return (message["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
        case .gemini:
            if let feedback = object["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil {
                throw VisionFailure.key("blocked")
            }
            let candidates = object["candidates"] as? [[String: Any]] ?? []
            if let reason = candidates.first?["finishReason"] as? String,
               ["SAFETY", "RECITATION", "PROHIBITED_CONTENT"].contains(reason) {
                throw VisionFailure.key("blocked")
            }
            let content = candidates.first?["content"] as? [String: Any] ?? [:]
            return (content["parts"] as? [[String: Any]] ?? [])
                .filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        case .anthropic:
            if streaming {
                let delta = object["delta"] as? [String: Any] ?? [:]
                return delta["text"] as? String ?? ""
            }
            return (object["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
        }
    }
}

enum VisionClient {
    static func analyze(profile: VisionProfile, key: String, image: Data, instructions: String,
                        update: @escaping @Sendable (String) async -> Void) async throws -> VisionResult {
        let request = try VisionWire.request(profile: profile, key: key, image: image, instructions: instructions)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 180
        // Never reuse cookies or a cached response across API profiles.
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw VisionFailure.key("server") }
        guard (200..<300).contains(http.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                if errorData.count >= 4096 { break }
                errorData.append(byte)
            }
            let object = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any]
            let message = (object?["error"] as? [String: Any])?["message"] as? String ?? ""
            throw VisionFailure.http(http.statusCode, sanitized(message, key: key))
        }
        var text = ""
        if (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/event-stream") {
            var eventData: [String] = []
            var lastUpdate = Date.distantPast
            func consume() throws {
                let payload = eventData.joined(separator: "\n")
                eventData.removeAll(keepingCapacity: true)
                if payload.isEmpty || payload == "[DONE]" { return }
                guard let data = payload.data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw VisionFailure.key("response")
                }
                text += try VisionWire.chunk(object, format: profile.format, streaming: true)
                guard text.utf8.count <= 512_000 else { throw VisionFailure.key("response") }
            }
            for try await line in bytes.lines {
                try Task.checkCancellation()
                if line.isEmpty {
                    try consume()
                    if Date().timeIntervalSince(lastUpdate) >= 0.06 {
                        await update(text); lastUpdate = Date()
                    }
                } else if line.hasPrefix("data:") {
                    eventData.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                    if eventData.reduce(0, { $0 + $1.utf8.count }) > 512_000 {
                        throw VisionFailure.key("response")
                    }
                    // URLSession's line sequence can omit empty separator lines.
                    // Consume complete JSON events immediately; retain only a
                    // genuinely multiline payload until it becomes complete.
                    let payload = eventData.joined(separator: "\n")
                    if payload == "[DONE]" ||
                        payload.data(using: .utf8).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) != nil {
                        try consume()
                        if Date().timeIntervalSince(lastUpdate) >= 0.06 {
                            await update(text); lastUpdate = Date()
                        }
                    }
                }
            }
            try consume()
        } else {
            // Compatible gateways sometimes return ordinary JSON despite stream=true.
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 1_048_576 else { throw VisionFailure.key("response") }
                data.append(byte)
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw VisionFailure.key("response")
            }
            text = try VisionWire.chunk(object, format: profile.format, streaming: false)
        }
        try Task.checkCancellation()
        await update(text)
        return try VisionResult.parse(text)
    }
    static func sanitized(_ text: String, key: String) -> String {
        let clean = key.isEmpty ? text : text.replacingOccurrences(of: key, with: "••••")
        return String(clean.prefix(500))
    }
}

enum PromptKeychain {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "com.scrollapp.app") + ".vision-api" }
    static func read(_ id: UUID) throws -> String {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw VisionFailure.key("keychain") }
        return value
    }
    static func write(_ key: String, id: UUID) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw VisionFailure.key("keychain") }
            return
        }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw VisionFailure.key("keychain") }
        } else if status != errSecSuccess { throw VisionFailure.key("keychain") }
    }
}

actor PromptHistoryDisk {
    static let shared = PromptHistoryDisk()
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.scrollapp.app")
            .appendingPathComponent("PromptStudio", isDirectory: true)
    }
    func read() throws -> [PromptHistoryEntry] {
        let url = directory.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([PromptHistoryEntry].self, from: data)
    }
    func save(_ entries: [PromptHistoryEntry], image: PromptImage? = nil, imageID: UUID? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let image, let imageID {
            try image.data.write(to: directory.appendingPathComponent("\(imageID.uuidString).jpg"), options: .atomic)
            try image.thumbnail.write(to: directory.appendingPathComponent("\(imageID.uuidString)-thumb.jpg"), options: .atomic)
        }
        try JSONEncoder().encode(entries).write(to: directory.appendingPathComponent("history.json"), options: .atomic)
        let live = Set(entries.flatMap { ["\($0.id.uuidString).jpg", "\($0.id.uuidString)-thumb.jpg"] })
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where file.pathExtension == "jpg" && !live.contains(file.lastPathComponent) {
            try FileManager.default.removeItem(at: file)
        }
    }
    func image(_ entry: PromptHistoryEntry) throws -> PromptImage {
        let data = try Data(contentsOf: directory.appendingPathComponent("\(entry.id.uuidString).jpg"))
        let decoded = try PromptImageDecoder.decode(data, title: entry.title, origin: entry.origin)
        return .init(id: decoded.id, title: entry.title, origin: entry.origin,
                     width: entry.width, height: entry.height, data: decoded.data, thumbnail: decoded.thumbnail)
    }
    func thumbnail(_ id: UUID) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent("\(id.uuidString)-thumb.jpg"))
    }
}
