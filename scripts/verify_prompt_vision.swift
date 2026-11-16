import Foundation
import AppKit

@main
struct VisionChecks {
    static func main() async throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        let base = CommandLine.arguments[1]
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let image = try PromptImageDecoder.decode(png, title: "test.png")
        expect(image.width == 1 && image.height == 1 && image.ratio == "1:1", "Image dimensions")
        expect(!image.data.isEmpty && !image.thumbnail.isEmpty, "Prepared image and thumbnail")
        do { _ = try PromptImageDecoder.decode(Data("HTML instead of image".utf8), title: "bad"); preconditionFailure("Reject HTML") }
        catch { checks += 1 }
        let resultJSON = #"{"prompt_cn":"测试图片，柔和光线","prompt_en":"A reference image with soft lighting","negative_prompt":"blur","tags":["soft","studio"]}"#
        let parsed = try VisionResult.parse("```json\n\(resultJSON)\n```")
        expect(parsed.chinese == "测试图片，柔和光线" && parsed.tags.count == 2, "Parse structured text")
        expect(VisionResult.partial(#"{"prompt_cn":"第一行\n第二"#, tab: "cn") == "第一行\n第二", "Incremental escaped text")
        let unstructured = try VisionResult.parse("unstructured model response")
        expect(unstructured.english.isEmpty, "Do not invent translations")
        for format in VisionWireFormat.allCases {
            let profile = VisionProfile(name: "Test", preset: "custom", format: format, baseURL: base + "/v1", model: "vision-test")
            let request = try VisionWire.request(profile: profile, key: "unit-key-DO-NOT-EXPOSE", image: image.data, instructions: "fixture")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            expect(body["stream"] as? Bool == true || format == .gemini, "\(format) stream request")
            expect(request.url!.host == "127.0.0.1", "\(format) custom endpoint")
            let response = try await VisionClient.analyze(profile: profile, key: "unit-key-DO-NOT-EXPOSE",
                image: image.data, instructions: "fixture") { _ in }
            expect(response == parsed, "\(format) end-to-end streamed result")
        }
        var profile = VisionProfile(name: "Test", preset: "custom", format: .openAI, baseURL: base + "/v1", model: "nonstream")
        let response = try await VisionClient.analyze(profile: profile, key: "unit-key-DO-NOT-EXPOSE",
            image: image.data, instructions: "fixture") { _ in }
        expect(response == parsed, "Nonstream gateway fallback")
        profile.model = "error"
        do {
            _ = try await VisionClient.analyze(profile: profile, key: "unit-key-DO-NOT-EXPOSE", image: image.data, instructions: "fixture") { _ in }
            preconditionFailure("401 must fail")
        } catch { expect(!error.localizedDescription.contains("unit-key-DO-NOT-EXPOSE"), "Key redaction in server errors") }
        profile.model = "slow"
        let slowProfile = profile
        let task = Task {
            try await VisionClient.analyze(profile: slowProfile, key: "unit-key-DO-NOT-EXPOSE",
                image: image.data, instructions: "fixture") { _ in }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Cancellation must not complete") }
        catch { checks += 1 }
        var bad = profile
        bad.baseURL = "https://api.example.com/v1?key=secret"
        do { _ = try bad.endpoint(suffix: "chat/completions"); preconditionFailure("Reject secret query") }
        catch { checks += 1 }
        bad.baseURL = "http://remote.example.com/v1"
        do { _ = try bad.endpoint(suffix: "chat/completions"); preconditionFailure("Reject plaintext remote API") }
        catch { checks += 1 }
        let remote = try await PromptImageDecoder.remote(URL(string: base + "/reference.png?temporary-signature=test")!)
        expect(remote.width == 1 && !remote.origin.contains("?"), "Remote image and signed URL sanitization")
        for path in ["webpage", "too-large"] {
            do {
                _ = try await PromptImageDecoder.remote(URL(string: base + "/" + path)!)
                preconditionFailure("Reject \(path)")
            } catch { checks += 1 }
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vision-history-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = PromptHistoryDisk(directory: folder)
        let entry = PromptHistoryEntry(id: UUID(), date: Date(), title: image.title, origin: "", width: 1, height: 1,
            provider: "Test", model: "vision-test", template: "general", instructions: "", favorite: true, result: parsed)
        try await disk.save([entry], image: image, imageID: entry.id)
        let restored = try await disk.read()
        expect(restored == [entry], "History and favorite round trip")
        let restoredImage = try await disk.image(entry)
        expect(restoredImage.width == 1 && restoredImage.height == 1, "History reference reopens")
        let thumbnail = await disk.thumbnail(entry.id)
        expect(thumbnail != nil, "Thumbnail persisted")
        try await disk.save([])
        expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(entry.id.uuidString).jpg").path), "Deleted history removes reference")
        print("PASS: \(checks) vision checks: all 3 protocols, streaming, errors, cancellation, remote images, history")
    }
}
