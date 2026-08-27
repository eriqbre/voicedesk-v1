import CryptoKit
import Foundation
import Network
import XCTest
@testable import VoiceDesk

/// In-process WebSocket the real `URLSessionWebSocketTask` can open.
/// xAI is unreachable in XCTest. This is still a socket, not a send recorder.
final class ListenLoopWebSocketLoopback: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "listen-loop-ws-loopback")
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var received: [String] = []
    private var port: UInt16 = 0

    var url: URL {
        lock.lock()
        let port = self.port
        lock.unlock()
        return URL(string: "ws://127.0.0.1:\(port)")!
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
        try await server.bind()
        return server
    }

    func stop() {
        lock.lock()
        let listener = self.listener
        let connections = self.connections
        self.listener = nil
        self.connections = []
        lock.unlock()
        listener?.cancel()
        connections.forEach { $0.cancel() }
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

    private func bind() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            let finish: (Result<Void, Error>) -> Void = { result in
                self.lock.lock()
                let already = resumed
                if !already { resumed = true }
                self.lock.unlock()
                guard !already else { return }
                switch result {
                case .success:
                    cont.resume()
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(
                    host: "127.0.0.1",
                    port: NWEndpoint.Port(rawValue: 0)!
                )
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let port = listener.port {
                            self.lock.lock()
                            self.port = port.rawValue
                            self.lock.unlock()
                            finish(.success(()))
                        } else {
                            finish(.failure(ListenLoopWebSocketLoopbackError.noPort))
                        }
                    case .failed(let error):
                        finish(.failure(error))
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            } catch {
                finish(.failure(error))
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
        let stream = ConnectionStream()
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
            if case .cancelled = state { return }
        }
        connection.start(queue: queue)
        receive(on: connection, stream: stream)
    }

    private func receive(on connection: NWConnection, stream: ConnectionStream) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                stream.buffer.append(data)
                if !stream.upgraded {
                    if let range = stream.buffer.range(of: Data("\r\n\r\n".utf8)) {
                        let request = String(
                            data: stream.buffer.subdata(in: stream.buffer.startIndex..<range.upperBound),
                            encoding: .utf8
                        ) ?? ""
                        stream.buffer.removeSubrange(stream.buffer.startIndex..<range.upperBound)
                        self.completeHandshake(request, on: connection)
                        stream.upgraded = true
                    }
                }
                if stream.upgraded {
                    self.consumeFrames(from: &stream.buffer, on: connection)
                }
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(on: connection, stream: stream)
        }
    }

    private func completeHandshake(_ request: String, on connection: NWConnection) {
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
            connection.cancel()
            return
        }
        let accept = Self.acceptKey(key)
        var response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r

        """
        if let proto, !proto.isEmpty {
            response = """
            HTTP/1.1 101 Switching Protocols\r
            Upgrade: websocket\r
            Connection: Upgrade\r
            Sec-WebSocket-Accept: \(accept)\r
            Sec-WebSocket-Protocol: \(proto)\r

            """
        }
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.send(content: Self.encodeTextFrame(#"{"type":"session.created"}"#), completion: .contentProcessed { _ in
                connection.send(content: Self.encodeTextFrame(#"{"type":"session.updated"}"#), completion: .idempotent)
            })
        })
    }

    private func consumeFrames(from buffer: inout Data, on connection: NWConnection) {
        while let frame = Self.popFrame(from: &buffer) {
            switch frame.opcode {
            case 1:
                if let text = String(data: frame.payload, encoding: .utf8) {
                    lock.lock()
                    received.append(text)
                    lock.unlock()
                }
            case 8:
                connection.cancel()
                return
            case 9:
                connection.send(content: Self.encodeFrame(opcode: 0x8A, payload: frame.payload), completion: .idempotent)
            default:
                break
            }
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
}

/// One accepted TCP connection. Receive callbacks must not use `inout` locals.
private final class ConnectionStream {
    var buffer = Data()
    var upgraded = false
}
