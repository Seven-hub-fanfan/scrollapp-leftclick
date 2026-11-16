import Foundation
import Darwin

enum CursorProtocol {
    enum Failure: Error { case timeout, closed, malformed }

    /// A stalled helper must not leave Apply or application termination hung.
    /// Each response has one deadline, even if bytes arrive a few at a time.
    static func read(from handle: FileHandle, buffer: inout Data, timeout: TimeInterval = 15) throws -> [String: Any] {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            if buffer.count > 2 * 1024 * 1024 { throw Failure.malformed }
            if let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let response = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw Failure.malformed
                }
                return response
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw Failure.timeout }
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let result = poll(&descriptor, 1, Int32(min(remaining * 1000, 15_000).rounded(.up)))
            if result == 0 { throw Failure.timeout }
            if result < 0 {
                if errno == EINTR { continue }
                throw Failure.closed
            }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw Failure.closed }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }
}
