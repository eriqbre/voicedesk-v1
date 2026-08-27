import Foundation
import Network
import XCTest
@testable import VoiceDesk

/// In-process WebSocket the real `URLSessionWebSocketTask` can open.
/// xAI is unreachable in XCTest. This is still a socket, not a send recorder.
/// Apple's `NWListener` + `NWProtocolWebSocket` completes the RFC 6455
/// upgrade that URLSession DidOpen on iOS Simulator.
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
        try await server.bind()
        return server
    }

    /// Peer → client. Same path as session.created on accept.
    func sendPeerJSON(_ raw: String) {
        lock.lock()
        let connections = self.connections
        lock.unlock()
        for connection in connections {
            sendText(connection, raw)
        }
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
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
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
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = listener.port, port.rawValue > 0 {
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
        }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendText(connection, #"{"type":"session.created"}"#)
                self.sendText(connection, #"{"type":"session.updated"}"#)
            case .failed, .cancelled:
                break
            default:
                break
            }
        }
        receive(on: connection)
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self else { return }
            _ = isComplete
            if let data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
                self.lock.lock()
                self.received.append(text)
                self.lock.unlock()
            }
            if error != nil {
                connection.cancel()
                return
            }
            self.receive(on: connection)
        }
    }

    private func sendText(_ connection: NWConnection, _ text: String) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(
            content: Data(text.utf8),
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }
}

private enum ListenLoopWebSocketLoopbackError: Error {
    case noPort
}
