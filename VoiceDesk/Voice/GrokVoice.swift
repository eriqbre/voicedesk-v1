import Foundation
import VoiceDeskLogic

/// Where the app looks for an xAI key. Never log the value. Never commit it.
final class UserDefaultsPlaybookStore: PlaybookStoring {
    var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: VoicePlaybook.defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: VoicePlaybook.defaultsKey) }
    }

    var hasSeenConnectOffer: Bool {
        get { UserDefaults.standard.bool(forKey: VoicePlaybook.seenConnectOfferKey) }
        set { UserDefaults.standard.set(newValue, forKey: VoicePlaybook.seenConnectOfferKey) }
    }

    var lastConnectSoftPromptAt: Date? {
        get {
            let interval = UserDefaults.standard.double(forKey: VoicePlaybook.lastSoftPromptKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: VoicePlaybook.lastSoftPromptKey)
        }
    }
}

enum VoiceDeskSecrets {
    /// Scheme env `XAI_API_KEY`, then gitignored `Secrets.plist` in the app bundle.
    static var xaiAPIKey: String? {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["XAI_API_KEY"],
            plistString("XAI_API_KEY")
        ])
    }

    /// Scheme env `XAI_VOICE` or Secrets.plist. Default `eve`.
    static var voiceID: String {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["XAI_VOICE"],
            plistString("XAI_VOICE")
        ]) ?? GrokRealtime.defaultVoice
    }

    static var model: String {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["XAI_VOICE_MODEL"],
            plistString("XAI_VOICE_MODEL")
        ]) ?? GrokRealtime.defaultModel
    }

    /// Scheme env `GOOGLE_CLIENT_ID`, then gitignored `Secrets.plist`.
    static var googleClientID: String? {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"],
            plistString("GOOGLE_CLIENT_ID")
        ])
    }

    static var googleReversedClientID: String? {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["GOOGLE_REVERSED_CLIENT_ID"],
            plistString("GOOGLE_REVERSED_CLIENT_ID")
        ]) ?? googleClientID.flatMap(GoogleScopes.reversedClientID)
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func plistString(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let value = dict[key] as? String
        else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum GrokVoiceAPI {
    static let restBase = URL(string: "https://api.x.ai/v1")!
    static let realtimeClientSecrets = URL(string: GrokRealtime.clientSecretsPath)!

    static func realtimeURL(model: String = VoiceDeskSecrets.model) -> URL {
        URL(string: GrokRealtime.realtimeURLString(model: model))!
    }
}

enum GrokVoiceError: LocalizedError {
    case missingAPIKey
    case connectFailed(String)
    case mintFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "XAI_API_KEY is not set."
        case .connectFailed(let detail):
            return "Grok voice did not connect: \(detail)"
        case .mintFailed(let detail):
            return "Ephemeral token mint failed: \(detail)"
        }
    }
}

@MainActor
protocol LiveGrokVoiceClientDelegate: AnyObject {
    func grokWebSocketDidOpen()
    func grokWebSocketDidClose(code: Int, reason: String?)
    func grokWebSocketDidFail(error: String, httpStatus: Int?)
    func grokWebSocketDidReceive(json: [String: Any], type: String)
    func grokWebSocketDidReceiveBinary(_ data: Data)
}

/// Real URLSession WebSocket to `wss://api.x.ai/v1/realtime?model=grok-voice-latest`.
/// Audio-thread `sendRaw` is lock-protected because URLSessionWebSocketTask is the cookbook path.
final class LiveGrokVoiceClient: @unchecked Sendable {
    weak var delegate: LiveGrokVoiceClientDelegate?

    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var sessionDelegate: WebSocketBridge?
    private var timeoutTask: Task<Void, Never>?
    private var opened = false

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return opened
    }

    /// Dogfood: API key in `Authorization` plus `xai-client-secret.<key>` protocol.
    /// URLSession drops `Authorization` on the HTTP→WS upgrade (xAI VoiceTesterApp).
    /// Ephemeral tokens (`POST /v1/realtime/client_secrets`) are the next hardening — not a dogfood blocker.
    func connect(apiKey: String, model: String = VoiceDeskSecrets.model) {
        disconnect()

        let url = GrokVoiceAPI.realtimeURL(model: model)
        let bridge = WebSocketBridge(
            onOpen: { [weak self] in
                Task { @MainActor in
                    self?.markOpen()
                    self?.delegate?.grokWebSocketDidOpen()
                }
            },
            onClose: { [weak self] code, reason in
                let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
                Task { @MainActor in
                    self?.markClosed()
                    self?.delegate?.grokWebSocketDidClose(code: code.rawValue, reason: reasonText)
                }
            },
            onComplete: { [weak self] task, error in
                let status = (task.response as? HTTPURLResponse)?.statusCode
                if let error {
                    Task { @MainActor in
                        self?.markClosed()
                        self?.delegate?.grokWebSocketDidFail(
                            error: error.localizedDescription,
                            httpStatus: status
                        )
                    }
                }
            }
        )

        lock.lock()
        sessionDelegate = bridge
        let urlSession = URLSession(configuration: .default, delegate: bridge, delegateQueue: nil)
        session = urlSession
        // URLSession drops `Authorization` on the WS upgrade; VoiceTesterApp uses this protocol.
        // Same credential as Bearer. Ephemeral tokens are next hardening, not a dogfood blocker.
        let wsTask = urlSession.webSocketTask(
            with: url,
            protocols: ["xai-client-secret.\(apiKey)"]
        )
        task = wsTask
        opened = false
        lock.unlock()

        wsTask.resume()
        receiveLoop()

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !self.isConnected else { return }
            await MainActor.run {
                self.delegate?.grokWebSocketDidFail(error: "WebSocket timeout", httpStatus: nil)
            }
        }
    }

    func disconnect() {
        timeoutTask?.cancel()
        timeoutTask = nil
        lock.lock()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        sessionDelegate = nil
        opened = false
        lock.unlock()
    }

    func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8)
        else { return }
        sendRaw(string)
    }

    /// Called from the audio render thread with a prebuilt JSON string.
    func sendRaw(_ string: String) {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.send(.string(string)) { _ in }
    }

    func sendBinary(_ data: Data) {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.send(.data(data)) { _ in }
    }

    /// Optional hardening. Default dogfood uses the API key on the socket, not this.
    func mintRealtimeClientSecret(apiKey: String, expiresAfterSeconds: Int = 300) async throws -> String {
        var request = URLRequest(url: GrokVoiceAPI.realtimeClientSecrets)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "expires_after": ["seconds": expiresAfterSeconds]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GrokVoiceError.mintFailed("HTTP \(status) \(body.prefix(160))")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = Self.extractClientSecret(from: object)
        else {
            throw GrokVoiceError.mintFailed("Response did not include a client secret")
        }
        return token
    }

    static func extractClientSecret(from object: [String: Any]) -> String? {
        if let value = object["value"] as? String, !value.isEmpty { return value }
        if let value = object["client_secret"] as? String, !value.isEmpty { return value }
        if let nested = object["client_secret"] as? [String: Any],
           let value = nested["value"] as? String, !value.isEmpty {
            return value
        }
        return nil
    }

    private func markOpen() {
        timeoutTask?.cancel()
        timeoutTask = nil
        lock.lock()
        opened = true
        lock.unlock()
    }

    private func markClosed() {
        lock.lock()
        opened = false
        lock.unlock()
    }

    private func receiveLoop() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.dispatchJSON(text.data(using: .utf8))
                case .data(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["type"] as? String {
                        Task { @MainActor in
                            self.delegate?.grokWebSocketDidReceive(json: json, type: type)
                        }
                    } else {
                        Task { @MainActor in
                            self.delegate?.grokWebSocketDidReceiveBinary(data)
                        }
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure(let error):
                Task { @MainActor in
                    self.markClosed()
                    self.delegate?.grokWebSocketDidFail(error: error.localizedDescription, httpStatus: nil)
                }
            }
        }
    }

    private func dispatchJSON(_ data: Data?) {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return }
        Task { @MainActor in
            self.delegate?.grokWebSocketDidReceive(json: json, type: type)
        }
    }
}

private final class WebSocketBridge: NSObject, URLSessionWebSocketDelegate, URLSessionTaskDelegate {
    let onOpen: () -> Void
    let onClose: (URLSessionWebSocketTask.CloseCode, Data?) -> Void
    let onComplete: (URLSessionTask, Error?) -> Void

    init(
        onOpen: @escaping () -> Void,
        onClose: @escaping (URLSessionWebSocketTask.CloseCode, Data?) -> Void,
        onComplete: @escaping (URLSessionTask, Error?) -> Void
    ) {
        self.onOpen = onOpen
        self.onClose = onClose
        self.onComplete = onComplete
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol proto: String?
    ) {
        _ = proto
        onOpen()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith code: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        onClose(code, reason)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        onComplete(task, error)
    }
}

/// On-device wake phrase while the app is open. Phrase is an open PRD decision.
protocol WakeWordListening: AnyObject {
    var isArmed: Bool { get }
    func arm()
    func disarm()
}

@MainActor
final class WakeWordPlaceholder: WakeWordListening {
    private var session = WakeWordSession()

    var isArmed: Bool { session.isArmed }

    func arm() {
        session.arm()
    }

    func disarm() {
        session.disarm()
    }
}
