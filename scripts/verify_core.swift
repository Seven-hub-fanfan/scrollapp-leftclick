import Foundation

@main
struct VerifyCore {
    static func main() throws {
        var integrator = ScrollIntegrator()
        let slow = (0..<100).map { _ in integrator.pixels(for: 0.25) }.reduce(0, +)
        precondition(slow == 25, "Subpixel scrolling was lost")
        integrator.reset()
        precondition(integrator.pixels(for: 0.9) == 0)
        precondition(integrator.pixels(for: -0.2) == 0)
        precondition(integrator.pixels(for: -0.8) == -1, "Direction change retained old remainder")
        precondition(integrator.pixels(for: .nan) == 0 && integrator.remainder == 0)
        var clicks = DoubleClickActivation()
        precondition(!clicks.click(at: 1, interval: 0.5))
        precondition(clicks.click(at: 1.4, interval: 0.5))
        precondition(!clicks.click(at: 1.6, interval: 0.5))
        precondition(clicks.click(at: 1.8, interval: 0.5))
        precondition(!clicks.click(at: 2, interval: 0.5))
        precondition(!clicks.click(at: 3, interval: 0.5))
        precondition(clicks.click(at: 3.1, interval: 0.5))

        let pipe = Pipe()
        var buffer = Data()
        try pipe.fileHandleForWriting.write(contentsOf: Data("{\"ok\":true}\n{\"ok\":false}\n".utf8))
        let first = try CursorProtocol.read(from: pipe.fileHandleForReading, buffer: &buffer)
        let second = try CursorProtocol.read(from: pipe.fileHandleForReading, buffer: &buffer)
        precondition(first["ok"] as? Bool == true && second["ok"] as? Bool == false)
        let start = ProcessInfo.processInfo.systemUptime
        do {
            _ = try CursorProtocol.read(from: pipe.fileHandleForReading, buffer: &buffer, timeout: 0.1)
            fatalError("Silent helper did not time out")
        } catch CursorProtocol.Failure.timeout {
            precondition(ProcessInfo.processInfo.systemUptime - start < 1)
        }
        try pipe.fileHandleForWriting.close()
        do {
            _ = try CursorProtocol.read(from: pipe.fileHandleForReading, buffer: &buffer)
            fatalError("EOF accepted")
        } catch CursorProtocol.Failure.closed {}
        let malformed = Pipe()
        try malformed.fileHandleForWriting.write(contentsOf: Data("[]\n".utf8))
        do {
            _ = try CursorProtocol.read(from: malformed.fileHandleForReading, buffer: &buffer)
            fatalError("Non-object protocol accepted")
        } catch CursorProtocol.Failure.malformed {}
        let results: [String: Any] = ["passed": true, "checks": [
            "fractional-scroll", "direction-change", "invalid-speed", "double-click-sequences",
            "framed-protocol", "silent-helper-timeout", "closed-helper", "malformed-response"]]
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
