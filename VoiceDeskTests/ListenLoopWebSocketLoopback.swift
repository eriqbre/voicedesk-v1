import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import VoiceDesk

/// In-process WebSocket the real `URLSessionWebSocketTask` can open.
/// xAI is unreachable in XCTest. This is still a socket, not a send recorder.
/// POSIX bind on 127.0.0.1. A Network.framework listener did not
/// finish a URLSession handshake on the iPhone simulator.
final class ListenLoopWebSocketLoopback: @unchecked Sendable {
    private let lock = NSLock()
    private let acceptQueue = DispatchQueue(label: "listen-loop-ws-loopback-accept")
    private var listenFD: Int32 = -1
    private var clientFDs: [Int32] = []
    private var received: [String] = []
    private var port: UInt16 = 0
    private var stopped = false

    var url: URL {
        lock.lock()
        let port = self.port
        lock.unlock()
        return URL(string: "ws://127.0.0.1:\(port)/")!
    }

    var receivedTexts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    var receivedAppendPCM: [Data] {
        receivedTexts.compactMap { LiveGrokVoiceClient.pcmFromAppendJSON($0) }
    }

    static func start() async throws -> ListenLoopWebSocketLoopback {
        let server = ListenLoopWebSocketLoopback()
        try server.bind()
        return server
    }

    func stop() {
        lock.lock()
        stopped = true
        let listen = listenFD
        listenFD = -1
        let clients = clientFDs
        clientFDs = []
        lock.unlock()
        if listen >= 0 {
            shutdown(listen, SHUT_RDWR)
            close(listen)
        }
        for fd in clients {
            shutdown(fd, SHUT_RDWR)
            close(fd)
        }
    }

    func waitUntilReceived(
        timeoutMs: Int = 2000,
        matching: @escaping (String) -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
        while ContinuousClock.now < deadline {
            if receivedTexts.contains(where: matching) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return receivedTexts.contains(where: matching)
    }

    private func bind() throws {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw ListenLoopWebSocketLoopbackError.bindFailed }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var nosig: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bindOK = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                Darwin.bind(fd, sock, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard bindOK, listen(fd, 8) == 0 else {
            close(fd)
            throw ListenLoopWebSocketLoopbackError.bindFailed
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameOK = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                getsockname(fd, sock, &length) == 0
            }
        }
        let port = UInt16(bigEndian: bound.sin_port)
        guard nameOK, port > 0 else {
            close(fd)
            throw ListenLoopWebSocketLoopbackError.noPort
        }
        lock.lock()
        listenFD = fd
        self.port = port
        lock.unlock()
        acceptQueue.async { [weak self] in
            self?.acceptLoop(listenFD: fd)
        }
    }

    private func acceptLoop(listenFD: Int32) {
        while true {
            lock.lock()
            let done = stopped
            lock.unlock()
            if done { return }
            var addr = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sock in
                    accept(listenFD, sock, &length)
                }
            }
            if client < 0 { return }
            var nodelay: Int32 = 1
            setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &nodelay, socklen_t(MemoryLayout<Int32>.size))
            var nosig: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
            lock.lock()
            if stopped {
                lock.unlock()
                close(client)
                return
            }
            clientFDs.append(client)
            lock.unlock()
            acceptQueue.async { [weak self] in
                self?.serve(client)
            }
        }
    }

    private func serve(_ fd: Int32) {
        var buffer = Data()
        guard let request = readHTTPRequest(fd: fd, buffer: &buffer) else {
            close(fd)
            return
        }
        var key: String?
        var proto: String?
        for line in request.split(whereSeparator: { $0 == "\n" }) {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            if lower.hasPrefix("sec-websocket-key:") {
                key = String(line.dropFirst("sec-websocket-key:".count)).trimmingCharacters(in: .whitespaces)
            }
            if lower.hasPrefix("sec-websocket-protocol:") {
                proto = String(line.dropFirst("sec-websocket-protocol:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let key else {
            close(fd)
            return
        }
        let accept = Self.acceptKey(key)
        var header = "HTTP/1.1 101 Switching Protocols\r\n"
        header += "Upgrade: websocket\r\n"
        header += "Connection: Upgrade\r\n"
        header += "Sec-WebSocket-Accept: \(accept)\r\n"
        if let proto, !proto.isEmpty {
            header += "Sec-WebSocket-Protocol: \(proto)\r\n"
        }
        header += "\r\n"
        // 101 only. Extra WS bytes on the upgrade packet make URLSession
        // reject DidOpen — opened stays false and sendRaw queues.
        guard writeAll(fd, Data(header.utf8)) else {
            close(fd)
            return
        }
        guard writeAll(fd, Self.encodeTextFrame(#"{"type":"session.created"}"#)) else {
            close(fd)
            return
        }
        guard writeAll(fd, Self.encodeTextFrame(#"{"type":"session.updated"}"#)) else {
            close(fd)
            return
        }
        consumeFrames(fd: fd, buffer: &buffer)
        close(fd)
    }

    private func readHTTPRequest(fd: Int32, buffer: inout Data) -> String? {
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count < 32 * 1024 {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<count])
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let request = String(data: buffer[buffer.startIndex..<range.upperBound], encoding: .utf8)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return request
            }
        }
        return nil
    }

    private func consumeFrames(fd: Int32, buffer: inout Data) {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            while let frame = Self.popFrame(from: &buffer) {
                switch frame.opcode {
                case 1:
                    if let text = String(data: frame.payload, encoding: .utf8) {
                        lock.lock()
                        received.append(text)
                        lock.unlock()
                    }
                case 8:
                    return
                case 9:
                    _ = writeAll(fd, Self.encodeFrame(opcode: 0x8A, payload: frame.payload))
                default:
                    break
                }
            }
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { return }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }

    private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            var sent = 0
            while sent < data.count {
                let count = Darwin.send(fd, base + sent, data.count - sent, 0)
                if count <= 0 { return false }
                sent += count
            }
            return true
        }
    }

    private static func acceptKey(_ key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((key + magic).utf8))
        return Data(digest).base64EncodedString()
    }

    private static func encodeTextFrame(_ text: String) -> Data {
        encodeFrame(opcode: 0x81, payload: Data(text.utf8))
    }

    private static func encodeFrame(opcode: UInt8, payload: Data) -> Data {
        var data = Data()
        data.append(opcode)
        let len = payload.count
        if len < 126 {
            data.append(UInt8(len))
        } else if len <= Int(UInt16.max) {
            data.append(126)
            data.append(UInt8((len >> 8) & 0xFF))
            data.append(UInt8(len & 0xFF))
        } else {
            data.append(127)
            var big = UInt64(len).bigEndian
            withUnsafeBytes(of: &big) { data.append(contentsOf: $0) }
        }
        data.append(payload)
        return data
    }

    private static func popFrame(from buffer: inout Data) -> (opcode: UInt8, payload: Data)? {
        guard buffer.count >= 2 else { return nil }
        let b0 = buffer[0]
        let b1 = buffer[1]
        let opcode = b0 & 0x0F
        let masked = (b1 & 0x80) != 0
        var len = Int(b1 & 0x7F)
        var offset = 2
        if len == 126 {
            guard buffer.count >= 4 else { return nil }
            len = Int(buffer[2]) << 8 | Int(buffer[3])
            offset = 4
        } else if len == 127 {
            guard buffer.count >= 10 else { return nil }
            var big: UInt64 = 0
            for index in 0..<8 {
                big = (big << 8) | UInt64(buffer[2 + index])
            }
            len = Int(big)
            offset = 10
        }
        let maskLen = masked ? 4 : 0
        guard buffer.count >= offset + maskLen + len else { return nil }
        var payload = Data(buffer[offset + maskLen ..< offset + maskLen + len])
        if masked {
            let mask = Array(buffer[offset ..< offset + 4])
            for index in 0..<payload.count {
                payload[index] ^= mask[index % 4]
            }
        }
        buffer.removeSubrange(0 ..< offset + maskLen + len)
        return (opcode, payload)
    }
}

private enum ListenLoopWebSocketLoopbackError: Error {
    case noPort
    case bindFailed
}
