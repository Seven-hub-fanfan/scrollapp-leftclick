import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ApplicationServices

@MainActor
final class PromptStudioStore: ObservableObject {
    static let shared = PromptStudioStore()
    @Published private(set) var profiles: [VisionProfile] = []
    @Published var selectedProfileID: UUID? {
        didSet { UserDefaults.standard.set(selectedProfileID?.uuidString, forKey: "visionSelectedProfile") }
    }
    @Published private(set) var images: [PromptImage] = []
    @Published var selectedImageID: UUID?
    @Published private(set) var results: [UUID: VisionResult] = [:]
    @Published private(set) var history: [PromptHistoryEntry] = []
    @Published private(set) var processingID: UUID?
    @Published private(set) var liveText = ""
    @Published private(set) var importing = false
    @Published private(set) var capturing = false
    @Published var error: String?
    @Published var notice: String?
    @Published var template = "general" {
        didSet { UserDefaults.standard.set(template, forKey: "visionTemplate") }
    }
    @Published var instructions = ""
    @Published var outputTab = "cn"
    private var work: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var runID = UUID()
    private var importID = UUID()
    private var thumbnailCache = NSCache<NSString, NSImage>()
    private static let profileDefaults = "visionProfiles.v1"
    nonisolated static let maximumImages = 5
    static let templates = ["general", "photo", "illustration", "design", "ui", "product", "game"]
    var profile: VisionProfile? { profiles.first { $0.id == selectedProfileID } }
    var image: PromptImage? { images.first { $0.id == selectedImageID } }
    var result: VisionResult? { selectedImageID.flatMap { results[$0] } }
    var isAnalyzing: Bool { processingID != nil }
    var canAnalyze: Bool { image != nil && profile != nil && !isAnalyzing && !importing && !capturing }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.profileDefaults),
           let saved = try? JSONDecoder().decode([VisionProfile].self, from: data) {
            profiles = saved
        }
        if let value = UserDefaults.standard.string(forKey: "visionSelectedProfile"), let id = UUID(uuidString: value),
           profiles.contains(where: { $0.id == id }) { selectedProfileID = id }
        else { selectedProfileID = profiles.first?.id }
        if let saved = UserDefaults.standard.string(forKey: "visionTemplate"), Self.templates.contains(saved) { template = saved }
        thumbnailCache.countLimit = 40
        thumbnailCache.totalCostLimit = 8 * 1024 * 1024
        Task {
            do { history = try await PromptHistoryDisk.shared.read() }
            catch { self.error = L10n.t("prompt.error.history") }
        }
    }

    func apiKey(_ id: UUID) async throws -> String {
        try await Task.detached(priority: .userInitiated) { try PromptKeychain.read(id) }.value
    }
    func saveProfile(_ value: VisionProfile, key: String) async throws {
        var cleaned = value
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.baseURL = cleaned.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.model = cleaned.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.name.isEmpty else { throw VisionFailure.key("nameMissing") }
        _ = try cleaned.endpoint(suffix: "")
        guard !cleaned.model.isEmpty else { throw VisionFailure.key("modelMissing") }
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.requiresKey || !secret.isEmpty else { throw VisionFailure.key("keyMissing") }
        try await Task.detached(priority: .userInitiated) { try PromptKeychain.write(secret, id: value.id) }.value
        if let index = profiles.firstIndex(where: { $0.id == cleaned.id }) { profiles[index] = cleaned }
        else { profiles.append(cleaned) }
        persistProfiles()
        selectedProfileID = cleaned.id
        error = nil
        notice = L10n.t("prompt.profileSaved")
    }
    func deleteProfile(_ id: UUID) async throws {
        try await Task.detached(priority: .userInitiated) { try PromptKeychain.write("", id: id) }.value
        profiles.removeAll { $0.id == id }
        if selectedProfileID == id { selectedProfileID = profiles.first?.id }
        persistProfiles()
    }
    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: Self.profileDefaults) }
    }

    func openFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = L10n.t("prompt.import")
        let response: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK { self?.importFiles(panel.urls) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: response) }
        else { panel.begin(completionHandler: response) }
    }
    func importFiles(_ urls: [URL]) {
        startImport {
            var values: [PromptImage] = []
            for url in urls.prefix(Self.maximumImages) {
                try Task.checkCancellation()
                values.append(try PromptImageDecoder.file(url))
            }
            return values
        }
    }
    func importData(_ data: Data, title: String) {
        startImport { [try PromptImageDecoder.decode(data, title: title)] }
    }
    func importURL(_ raw: String) {
        let string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            error = L10n.t("prompt.error.imageURL"); return
        }
        startImport { [try await PromptImageDecoder.remote(url)] }
    }
    private func startImport(_ load: @escaping @Sendable () async throws -> [PromptImage]) {
        guard !capturing else { return }
        importTask?.cancel()
        importing = true; error = nil; notice = nil
        let token = UUID(); importID = token
        importTask = Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try await load()
                }.value
                guard !Task.isCancelled, token == importID else { return }
                acceptImages(loaded)
            } catch {
                guard !Task.isCancelled, token == importID else { return }
                self.error = error.localizedDescription
            }
            if token == importID { importing = false; importTask = nil }
        }
    }
    func acceptImages(_ values: [PromptImage]) {
        let available = max(0, Self.maximumImages - images.count)
        guard available > 0 else { error = L10n.t("prompt.error.queue"); return }
        let accepted = Array(values.prefix(available))
        images.append(contentsOf: accepted)
        if let first = accepted.first { selectedImageID = first.id }
        if values.count > available { notice = L10n.t("prompt.queueLimit") }
        outputTab = "cn"
    }
    func removeImage(_ id: UUID) {
        guard id != processingID else { return }
        images.removeAll { $0.id == id }
        results.removeValue(forKey: id)
        if selectedImageID == id { selectedImageID = images.last?.id }
        thumbnailCache.removeObject(forKey: id.uuidString as NSString)
    }
    func imageThumbnail(_ image: PromptImage) -> NSImage? {
        let key = image.id.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let value = NSImage(data: image.thumbnail) else { return nil }
        thumbnailCache.setObject(value, forKey: key, cost: image.thumbnail.count * 8)
        return value
    }
    func paste() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options:
            [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            importFiles(urls); return
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            importData(data, title: L10n.t("prompt.clipboardImage")); return
        }
        if let url = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string),
           URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?.host != nil {
            importURL(url); return
        }
        error = L10n.t("prompt.error.clipboard")
    }
    @discardableResult
    func drop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty, !importing, !capturing else { return false }
        // Prefer a file promise or image bytes to the enclosing webpage's URL.
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        if !files.isEmpty {
            Task {
                var urls: [URL] = []
                for provider in files.prefix(Self.maximumImages) {
                    if let data = try? await providerData(provider, type: UTType.fileURL.identifier),
                       let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
                }
                if !urls.isEmpty { importFiles(urls) }
                else { error = L10n.t("prompt.error.image") }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
           let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
            Task {
                do {
                    let data = try await providerData(provider, type: type)
                    importData(data, title: L10n.t("prompt.droppedImage"))
                } catch { self.error = L10n.t("prompt.error.image") }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            Task {
                if let data = try? await providerData(provider, type: UTType.url.identifier),
                   let url = URL(dataRepresentation: data, relativeTo: nil) { importURL(url.absoluteString) }
                else { error = L10n.t("prompt.error.imageURL") }
            }
            return true
        }
        return false
    }
    private func providerData(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? VisionFailure.key("image")) }
            }
        }
    }

    func capture() {
        guard !capturing, !importing, !isAnalyzing else { return }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            error = L10n.t("prompt.error.capturePermission")
            return
        }
        error = nil; notice = nil; capturing = true
        let window = NSApp.keyWindow
        window?.orderOut(nil)
        Task {
            do {
                let captured = try await Task.detached(priority: .userInitiated) { () -> PromptImage? in
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("scrollapp-capture-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: folder) }
                    let url = folder.appendingPathComponent("Capture.png")
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    process.arguments = ["-i", "-s", "-x", url.path]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    process.waitUntilExit()
                    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                    return try PromptImageDecoder.file(url)
                }.value
                if let captured { acceptImages([captured]) }
            } catch { self.error = L10n.t("prompt.error.capture") }
            capturing = false
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func analyze(all: Bool = false) {
        guard canAnalyze, let profile else { return }
        let targets = all ? images : image.map { [$0] } ?? []
        let template = self.template, instructions = self.instructions
        let prompt = Self.systemPrompt(template: template, instructions: instructions)
        error = nil; notice = nil; liveText = ""; outputTab = "cn"
        let token = UUID(); runID = token
        processingID = targets.first?.id
        work = Task {
            do {
                let key = try await apiKey(profile.id)
                for target in targets {
                    try Task.checkCancellation()
                    guard token == runID else { return }
                    processingID = target.id; selectedImageID = target.id; liveText = ""
                    let result: VisionResult
                    do {
                        result = try await VisionClient.analyze(profile: profile, key: key, image: target.data, instructions: prompt) {
                            [weak self] text in
                            await self?.updateStream(text, token: token)
                        }
                    } catch {
                        throw VisionFailure.detail(VisionClient.sanitized(error.localizedDescription, key: key))
                    }
                    try Task.checkCancellation()
                    guard token == runID else { return }
                    results[target.id] = result
                    let entry = PromptHistoryEntry(id: UUID(), date: Date(), title: target.title, origin: target.origin,
                        width: target.width, height: target.height, provider: profile.displayName, model: profile.model,
                        template: template, instructions: instructions, favorite: false, result: result)
                    history.insert(entry, at: 0)
                    // Preserve favorites when rotating recent history.
                    if history.count > 100 {
                        if let index = history.lastIndex(where: { !$0.favorite }) { history.remove(at: index) }
                        else { history.removeLast() }
                    }
                    await saveHistory(image: target, imageID: entry.id)
                }
                if token == runID { notice = L10n.t("prompt.completed") }
            } catch {
                if !Task.isCancelled, token == runID { self.error = error.localizedDescription }
            }
            if token == runID { processingID = nil; liveText = ""; work = nil }
        }
    }
    private func updateStream(_ text: String, token: UUID) {
        if token == runID { liveText = text }
    }
    func cancel() {
        work?.cancel(); work = nil
        runID = UUID(); processingID = nil; liveText = ""
        notice = L10n.t("prompt.cancelled")
    }
    static func systemPrompt(template: String, instructions: String) -> String {
        let focus: [String: String] = [
            "general": "Describe subject, composition, light, materials, palette, style and mood.",
            "photo": "Focus on photography: framing, light direction, lens feel, depth, texture and color grading.",
            "illustration": "Focus on illustration: line work, rendering technique, shapes, palette and stylization.",
            "design": "Focus on graphic design: hierarchy, typography appearance, layout, spacing and palette.",
            "ui": "Focus on UI design: layout, component shapes, spacing, typography, color and material treatment.",
            "product": "Focus on product photography: materials, studio light, background, reflections and framing.",
            "game": "Focus on game assets: silhouette, perspective, materials, rendering style and environment."
        ]
        return """
        You translate a reference image into reusable image-generation prompts.
        Infer visible characteristics; do not claim to recover its exact original prompt, hidden parameters, or artist identity.
        \(focus[template] ?? focus["general"]!)
        Return one JSON object without Markdown fences, using exactly these keys:
        {"prompt_cn":"a detailed Simplified Chinese prompt","prompt_en":"the corresponding detailed English prompt","negative_prompt":"concise English exclusions relevant to the image","tags":["3 to 7 concise style tags"]}
        Keep prompts precise and usable; avoid commentary and invented text that is not visible.
        The following optional user instructions may intentionally change the desired output:
        \(String(instructions.prefix(6000)))
        """
    }
    func probe(_ profile: VisionProfile, key: String) async throws {
        // Exercise the actual vision protocol, model and authentication together.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let prepared = try await Task.detached { try PromptImageDecoder.decode(png, title: "test") }.value
        do {
            _ = try await VisionClient.analyze(profile: profile, key: key, image: prepared.data,
                instructions: "Describe the color of this small test image in one short sentence.") { _ in }
        } catch { throw VisionFailure.detail(VisionClient.sanitized(error.localizedDescription, key: key)) }
    }
    private func saveHistory(image: PromptImage? = nil, imageID: UUID? = nil) async {
        let snapshot = history
        let previous = persistenceTask
        let next = Task { [weak self] in
            await previous?.value
            do { try await PromptHistoryDisk.shared.save(snapshot, image: image, imageID: imageID) }
            catch { self?.error = L10n.t("prompt.error.historySave") }
        }
        persistenceTask = next
        await next.value
    }
    func toggleFavorite(_ entry: PromptHistoryEntry) {
        guard let index = history.firstIndex(where: { $0.id == entry.id }) else { return }
        history[index].favorite.toggle()
        Task { await saveHistory() }
    }
    func removeHistory(_ entry: PromptHistoryEntry) {
        history.removeAll { $0.id == entry.id }
        Task { await saveHistory() }
    }
    func restore(_ entry: PromptHistoryEntry) {
        guard !isAnalyzing, !importing else { return }
        importing = true; error = nil
        Task {
            do {
                let restored = try await PromptHistoryDisk.shared.image(entry)
                if images.count >= Self.maximumImages, let last = images.last { removeImage(last.id) }
                acceptImages([restored])
                results[restored.id] = entry.result
                template = entry.template; instructions = entry.instructions; outputTab = "cn"
            } catch { self.error = L10n.t("prompt.error.historyImage") }
            importing = false
        }
    }
    func historyThumbnail(_ id: UUID) async -> NSImage? {
        let key = id.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let data = await PromptHistoryDisk.shared.thumbnail(id), let value = NSImage(data: data) else { return nil }
        thumbnailCache.setObject(value, forKey: key, cost: data.count * 8)
        return value
    }
    func copyResult(_ content: String? = nil) {
        let value = content ?? result?.content(outputTab) ?? ""
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        notice = L10n.t("prompt.copied")
    }
    func export(_ entries: [PromptHistoryEntry]? = nil) {
        let values = entries ?? history
        guard !values.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Scrollapp-Prompts.md"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let text = values.map { entry in
                """
                ## \(entry.title.replacingOccurrences(of: "\n", with: " "))
                \(entry.date.formatted()) · \(entry.provider) · \(entry.model)

                ### 中文
                \(entry.result.chinese)

                ### English
                \(entry.result.english)

                ### Negative
                \(entry.result.negative)

                ### JSON
                ```json
                \(entry.result.raw)
                ```
                """
            }.joined(separator: "\n\n---\n\n")
            Task {
                do {
                    try await Task.detached { try text.write(to: url, atomically: true, encoding: .utf8) }.value
                    self?.notice = L10n.t("prompt.exported")
                } catch { self?.error = L10n.t("prompt.error.export") }
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}
