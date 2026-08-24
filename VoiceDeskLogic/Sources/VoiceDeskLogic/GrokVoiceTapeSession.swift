import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Live `wss://api.x.ai/v1/realtime` tape.
///
/// Apple uses `URLSessionWebSocketTask` (same `xai-client-secret.` protocol as
/// the iOS client). Linux Foundation/libcurl cannot speak WebSockets, so Linux
/// uses a stdlib Python RFC 6455 client. The API key is sent on stdin only.
enum GrokVoiceTapeSession {
    static func run(
        fixture: GrokVoiceTape.Fixture,
        pcm: Data?,
        apiKey: String,
        firstAudioCap: Duration,
        turnCap: Duration
    ) async -> GrokVoiceTape.Result {
        let transport = makeTransport()
        var userTranscript: String?
        var assistant = ""
        var errors: [String] = []
        var firstAudioMS: Int?
        let usedPCM = pcm.map { !$0.isEmpty } ?? false
        let clock = ContinuousClock()

        do {
            try await transport.connect(apiKey: apiKey)
            try await transport.sendJSON(GrokRealtime.sessionUpdateObject())
            try await waitUntilReady(transport)

            let sentAt = clock.now
            if usedPCM, let pcm, !pcm.isEmpty {
                for json in GrokVoiceTape.appendJSONChunks(pcm: pcm) {
                    try await transport.sendRaw(json)
                }
                try await transport.sendRaw(GrokRealtime.commitAudioJSON())
                try await transport.sendJSON(GrokRealtime.responseCreateObject())
            } else {
                try await transport.sendJSON(GrokRealtime.textItemObject(fixture.utterance))
                try await transport.sendJSON(GrokRealtime.responseCreateObject())
            }

            let turnDeadline = sentAt + turnCap
            let audioDeadline = sentAt + firstAudioCap
            var responseDone = false

            while clock.now < turnDeadline, !responseDone {
                if firstAudioMS == nil, clock.now > audioDeadline {
                    break
                }
                let remaining = min(turnDeadline - clock.now, Duration.milliseconds(250))
                guard let incoming = await transport.next(timeout: remaining) else { continue }
                switch incoming {
                case .opened:
                    break
                case .fail(let message):
                    errors.append(message)
                    responseDone = true
                case .closed:
                    if !responseDone {
                        errors.append("socket closed")
                    }
                    responseDone = true
                case .text(let payload):
                    guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                          let type = json["type"] as? String
                    else { break }
                    switch GrokRealtime.parse(type: type, json: json) {
                    case .userTranscript(let text, _):
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty, !GrokRealtime.isVerbatimSpeakPrompt(trimmed) {
                            userTranscript = trimmed
                        }
                    case .assistantTranscriptDelta(let delta, _):
                        assistant += delta
                    case .outputAudioDelta(let delta):
                        if firstAudioMS == nil, !delta.isEmpty {
                            firstAudioMS = milliseconds(clock.now - sentAt)
                        }
                    case .responseDone:
                        responseDone = true
                    case .ping(let timestamp):
                        try await transport.sendJSON(GrokRealtime.pongObject(timestamp: timestamp))
                    case .error(let code, let message):
                        let detail = "\(code) \(message)".trimmingCharacters(in: .whitespaces)
                        if !detail.isEmpty {
                            errors.append(detail)
                        }
                    default:
                        break
                    }
                }
            }
        } catch {
            errors.append(error.localizedDescription)
        }

        transport.close()

        var failures = GrokVoiceTape.evaluate(
            assistantText: assistant,
            firstAudioDeltaMilliseconds: firstAudioMS,
            firstAudioCapMilliseconds: milliseconds(firstAudioCap)
        )
        if firstAudioMS == nil {
            for error in errors where !error.isEmpty {
                failures.append(.transport(error))
            }
        }
        return GrokVoiceTape.Result(
            fixtureID: fixture.id,
            utterance: fixture.utterance,
            usedPCM: usedPCM,
            userTranscript: userTranscript,
            firstAudioDeltaMilliseconds: firstAudioMS,
            assistantText: assistant,
            errors: errors,
            failures: failures
        )
    }

    private static func waitUntilReady(_ transport: any TapeTransport) async throws {
        let deadline = ContinuousClock.now + Duration.seconds(8)
        while ContinuousClock.now < deadline {
            guard let incoming = await transport.next(timeout: deadline - ContinuousClock.now) else { continue }
            switch incoming {
            case .text(let payload):
                guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                      let type = json["type"] as? String
                else { continue }
                switch GrokRealtime.parse(type: type, json: json) {
                case .sessionCreated:
                    try await transport.sendJSON(GrokRealtime.sessionUpdateObject())
                    return
                case .sessionUpdated:
                    return
                case .error(let code, let message):
                    throw TapeConnectError.failed("\(code) \(message)".trimmingCharacters(in: .whitespaces))
                default:
                    continue
                }
            case .fail(let message):
                throw TapeConnectError.failed(message)
            case .closed:
                throw TapeConnectError.failed("closed before session.update")
            case .opened:
                continue
            }
        }
        throw TapeConnectError.failed("session setup timeout")
    }

    private static func makeTransport() -> any TapeTransport {
        #if os(Linux)
        return LinuxPythonWebSocketTransport()
        #else
        return URLSessionTapeTransport()
        #endif
    }
}

private enum TapeIncoming: Sendable {
    case opened
    case text(String)
    case fail(String)
    case closed
}

private enum TapeConnectError: Error, LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

private protocol TapeTransport: AnyObject, Sendable {
    func connect(apiKey: String) async throws
    func sendRaw(_ text: String) async throws
    func sendJSON(_ object: [String: Any]) async throws
    func next(timeout: Duration) async -> TapeIncoming?
    func close()
}

extension TapeTransport {
    func sendJSON(_ object: [String: Any]) async throws {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8)
        else { return }
        try await sendRaw(string)
    }
}

#if os(Linux)
/// libcurl URLSession on Linux cannot upgrade WebSockets. This process is a
/// stdlib-only RFC 6455 client so the tape stays headless and MockVoice-free.
private final class LinuxPythonWebSocketTransport: TapeTransport, @unchecked Sendable {
    private let mailbox = LineMailbox()
    private var process: Process?
    private var stdin: FileHandle?
    private var leftover = Data()

    func connect(apiKey: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-u", "-c", Self.script]
        let input = Pipe()
        let output = Pipe()
        let err = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = err
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.ingest(handle.availableData)
        }
        try process.run()
        self.process = process
        self.stdin = input.fileHandleForWriting

        let hello: [String: String] = [
            "t": "connect",
            "url": GrokRealtime.realtimeURLString(),
            "protocol": "xai-client-secret.\(apiKey)",
            "authorization": "Bearer \(apiKey)"
        ]
        try writeLine(hello)
        let opened = await mailbox.next(timeout: .seconds(12))
        switch opened {
        case .opened, .text:
            break
        case .fail(let message):
            throw TapeConnectError.failed(message)
        case .closed, .none:
            throw TapeConnectError.failed("WebSocket timeout")
        }
    }

    func sendRaw(_ text: String) async throws {
        try writeLine(["t": "send", "data": text])
    }

    func next(timeout: Duration) async -> TapeIncoming? {
        await mailbox.next(timeout: timeout)
    }

    func close() {
        try? writeLine(["t": "close"])
        stdin?.closeFile()
        stdin = nil
        process?.terminate()
        process = nil
        Task { await mailbox.close() }
    }

    private func writeLine(_ object: [String: String]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        var line = data
        line.append(0x0A)
        stdin?.write(line)
    }

    private func ingest(_ data: Data) {
        guard !data.isEmpty else { return }
        leftover.append(data)
        while let range = leftover.firstIndex(of: 0x0A) {
            let line = leftover.subdata(in: leftover.startIndex..<range)
            leftover.removeSubrange(leftover.startIndex...range)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = object["t"] as? String
            else { continue }
            Task {
                switch type {
                case "open":
                    await mailbox.push(.opened)
                case "msg":
                    if let text = object["data"] as? String {
                        await mailbox.push(.text(text))
                    }
                case "err":
                    await mailbox.push(.fail((object["data"] as? String) ?? "python ws error"))
                case "close":
                    await mailbox.push(.closed)
                default:
                    break
                }
            }
        }
    }

    /// Stdlib-only WebSocket client. No pip packages.
    private static let script = #"""
import base64, json, os, socket, ssl, struct, sys, threading, urllib.parse

class Buf:
    def __init__(self, sock, extra=b""):
        self.sock = sock
        self.buf = extra
    def exact(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(max(n - len(self.buf), 4096))
            if not chunk:
                raise ConnectionError("eof")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

def send_frame(sock, opcode, payload):
    key = os.urandom(4)
    masked = bytes(b ^ key[i % 4] for i, b in enumerate(payload))
    header = bytearray([0x80 | opcode])
    ln = len(masked)
    if ln < 126:
        header.append(0x80 | ln)
    elif ln < 65536:
        header.append(0x80 | 126)
        header += struct.pack("!H", ln)
    else:
        header.append(0x80 | 127)
        header += struct.pack("!Q", ln)
    header += key
    sock.sendall(header + masked)

def read_frame(reader):
    collected = bytearray()
    opcode = None
    while True:
        hdr = reader.exact(2)
        b1, b2 = hdr[0], hdr[1]
        fin = b1 & 0x80
        op = b1 & 0x0F
        masked = b2 & 0x80
        ln = b2 & 0x7F
        if ln == 126:
            ln = struct.unpack("!H", reader.exact(2))[0]
        elif ln == 127:
            ln = struct.unpack("!Q", reader.exact(8))[0]
        mask = reader.exact(4) if masked else b""
        payload = reader.exact(ln)
        if masked:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        if op in (0x8, 0x9, 0xA):
            return op, payload
        if opcode is None:
            opcode = op
        collected.extend(payload)
        if fin:
            return opcode, bytes(collected)

def connect(url, protocol, authorization):
    parsed = urllib.parse.urlparse(url)
    host = parsed.hostname
    port = parsed.port or 443
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query
    raw = socket.create_connection((host, port), timeout=12)
    ctx = ssl.create_default_context()
    sock = ctx.wrap_socket(raw, server_hostname=host)
    sock.settimeout(None)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        f"Sec-WebSocket-Protocol: {protocol}\r\n"
        f"Authorization: {authorization}\r\n"
        "\r\n"
    )
    sock.sendall(req.encode())
    header = b""
    while b"\r\n\r\n" not in header:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("handshake eof")
        header += chunk
    head, leftover = header.split(b"\r\n\r\n", 1)
    status = head.split(b"\r\n", 1)[0]
    if b"101" not in status:
        raise ConnectionError(status.decode("latin1", "replace")[:160])
    return sock, leftover

def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()

hello = json.loads(sys.stdin.readline())
try:
    sock, leftover = connect(hello["url"], hello["protocol"], hello["authorization"])
except Exception as exc:
    emit({"t": "err", "data": str(exc)})
    sys.exit(1)
emit({"t": "open"})
reader = Buf(sock, leftover)

def pump():
    try:
        while True:
            op, payload = read_frame(reader)
            if op == 0x1:
                emit({"t": "msg", "data": payload.decode("utf-8", "replace")})
            elif op == 0x8:
                emit({"t": "close"})
                os._exit(0)
            elif op == 0x9:
                send_frame(sock, 0xA, payload)
    except Exception as exc:
        emit({"t": "err", "data": str(exc)})
        os._exit(1)

threading.Thread(target=pump, daemon=True).start()
try:
    while True:
        line = sys.stdin.readline()
        if not line:
            send_frame(sock, 0x8, b"")
            break
        msg = json.loads(line)
        if msg.get("t") == "send":
            send_frame(sock, 0x1, msg["data"].encode())
        elif msg.get("t") == "close":
            send_frame(sock, 0x8, b"")
            break
except Exception as exc:
    emit({"t": "err", "data": str(exc)})
    sys.exit(1)
"""#
}

private actor LineMailbox {
    private var items: [TapeIncoming] = []
    private var waiters: [Waiter] = []

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<TapeIncoming?, Never>
    }

    func push(_ incoming: TapeIncoming) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume(returning: incoming)
            return
        }
        items.append(incoming)
    }

    func next(timeout: Duration) async -> TapeIncoming? {
        if !items.isEmpty {
            return items.removeFirst()
        }
        if timeout <= .zero { return nil }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters.append(Waiter(id: id, continuation: continuation))
            Task {
                try? await Task.sleep(for: timeout)
                timeoutWaiter(id)
            }
        }
    }

    private func timeoutWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: nil)
    }

    func close() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.continuation.resume(returning: nil)
        }
    }
}
#else
private final class URLSessionTapeTransport: NSObject, TapeTransport, URLSessionWebSocketDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let mailbox = LineMailbox()
    private let sockets = SocketBox()

    func connect(apiKey: String) async throws {
        guard let url = URL(string: GrokRealtime.realtimeURLString()) else {
            throw TapeConnectError.failed("bad realtime URL")
        }
        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let ws = urlSession.webSocketTask(
            with: url,
            protocols: ["xai-client-secret.\(apiKey)"]
        )
        sockets.store(task: ws, session: urlSession)
        ws.resume()
        receiveLoop()
        let opened = await mailbox.next(timeout: .seconds(12))
        switch opened {
        case .opened, .text:
            break
        case .fail(let message):
            throw TapeConnectError.failed(message)
        case .closed, .none:
            throw TapeConnectError.failed("WebSocket timeout")
        }
    }

    func sendRaw(_ text: String) async throws {
        sockets.task()?.send(.string(text)) { _ in }
    }

    func next(timeout: Duration) async -> TapeIncoming? {
        await mailbox.next(timeout: timeout)
    }

    func close() {
        sockets.shutdown()
        Task { await mailbox.close() }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol proto: String?
    ) {
        _ = proto
        Task { await mailbox.push(.opened) }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith code: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        _ = reason
        Task { await mailbox.push(.closed) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            Task { await mailbox.push(.fail(error.localizedDescription)) }
        }
    }

    private func receiveLoop() {
        guard let task = sockets.task() else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    Task { await self.mailbox.push(.text(text)) }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8), text.first == "{" {
                        Task { await self.mailbox.push(.text(text)) }
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure(let error):
                Task { await self.mailbox.push(.fail(error.localizedDescription)) }
            }
        }
    }

    private final class SocketBox: @unchecked Sendable {
        private let lock = NSLock()
        private var webSocket: URLSessionWebSocketTask?
        private var urlSession: URLSession?

        func store(task: URLSessionWebSocketTask, session: URLSession) {
            lock.lock()
            webSocket = task
            urlSession = session
            lock.unlock()
        }

        func task() -> URLSessionWebSocketTask? {
            lock.lock()
            defer { lock.unlock() }
            return webSocket
        }

        func shutdown() {
            lock.lock()
            webSocket?.cancel(with: .normalClosure, reason: nil)
            webSocket = nil
            urlSession?.invalidateAndCancel()
            urlSession = nil
            lock.unlock()
        }
    }
}

private actor LineMailbox {
    private var items: [TapeIncoming] = []
    private var waiters: [Waiter] = []

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<TapeIncoming?, Never>
    }

    func push(_ incoming: TapeIncoming) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.continuation.resume(returning: incoming)
            return
        }
        items.append(incoming)
    }

    func next(timeout: Duration) async -> TapeIncoming? {
        if !items.isEmpty {
            return items.removeFirst()
        }
        if timeout <= .zero { return nil }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters.append(Waiter(id: id, continuation: continuation))
            Task {
                try? await Task.sleep(for: timeout)
                timeoutWaiter(id)
            }
        }
    }

    private func timeoutWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: nil)
    }

    func close() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.continuation.resume(returning: nil)
        }
    }
}
#endif

private func milliseconds(_ duration: Duration) -> Int {
    let (seconds, attoseconds) = duration.components
    return Int(seconds * 1_000 + attoseconds / 1_000_000_000_000_000)
}
