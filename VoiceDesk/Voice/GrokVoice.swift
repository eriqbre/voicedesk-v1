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

    /// Non-live chat completions model for email summaries. Default grok-3-mini.
    static var textModel: String {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["XAI_TEXT_MODEL"],
            plistString("XAI_TEXT_MODEL")
        ]) ?? EmailSummary.defaultTextModel
    }

    /// Scheme env `GOOGLE_CLIENT_ID`, then gitignored `Secrets.plist`.
    static var googleClientID: String? {
        let raw = firstNonEmpty([
            ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"],
            plistString("GOOGLE_CLIENT_ID")
        ])
        return GoogleSignInSetup.isPlaceholder(raw) ? nil : raw
    }

    static var googleReversedClientID: String? {
        GoogleSignInSetup.resolvedReversedClientID(
            clientID: googleClientID,
            reversedOverride: firstNonEmpty([
                ProcessInfo.processInfo.environment["GOOGLE_REVERSED_CLIENT_ID"],
                plistString("GOOGLE_REVERSED_CLIENT_ID")
            ])
        )
    }

    static var registeredURLSchemes: [String] {
        let types = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        return types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    }

    /// Fine-grained PAT with gist or contents:write. DEBUG / TestFlight only.
    static var voiceDogfoodGitHubToken: String? {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["VOICE_DOGFOOD_GITHUB_TOKEN"],
            plistString("VOICE_DOGFOOD_GITHUB_TOKEN")
        ])
    }

    static var voiceDogfoodGistID: String? {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["VOICE_DOGFOOD_GIST_ID"],
            plistString("VOICE_DOGFOOD_GIST_ID")
        ])
    }

    /// `owner/repo` for a private dogfood log repo.
    static var voiceDogfoodGitHubRepo: String? {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["VOICE_DOGFOOD_GITHUB_REPO"],
            plistString("VOICE_DOGFOOD_GITHUB_REPO")
        ])
    }

    static var voiceDogfoodGitHubPath: String? {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["VOICE_DOGFOOD_GITHUB_PATH"],
            plistString("VOICE_DOGFOOD_GITHUB_PATH")
        ])
    }

    static var voiceDogfoodUploadURL: String? {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["VOICE_DOGFOOD_UPLOAD_URL"],
            plistString("VOICE_DOGFOOD_UPLOAD_URL")
        ])
    }

    static var voiceDogfoodUploadSecret: String? {
        firstNonEmpty([
            ProcessInfo.processInfo.environment["VOICE_DOGFOOD_UPLOAD_SECRET"],
            plistString("VOICE_DOGFOOD_UPLOAD_SECRET")
        ])
    }

    static var signInDiagnosis: GoogleSignInSetup.Diagnosis {
        GoogleSignInSetup.diagnose(
            clientID: googleClientID,
            reversedOverride: firstNonEmpty([
                ProcessInfo.processInfo.environment["GOOGLE_REVERSED_CLIENT_ID"],
                plistString("GOOGLE_REVERSED_CLIENT_ID")
            ]),
            registeredSchemes: registeredURLSchemes
        )
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
/// `@unchecked Sendable` is required: the audio render thread calls `sendRaw` while
/// URLSession callbacks arrive on a session queue. Mutable socket state is lock-protected.
/// The MainActor delegate is only written from the voice service and only read after a hop.
final class LiveGrokVoiceClient: @unchecked Sendable {
    /// Written from `@MainActor` (`GrokVoiceService`); read after hopping to the main actor.
    nonisolated(unsafe) weak var delegate: LiveGrokVoiceClientDelegate?

    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var sessionDelegate: WebSocketBridge?
    private var timeoutTask: Task<Void, Never>?
    private var opened = false
    /// Mic appends during a dead or unconfigured socket. Flushed after
    /// session.update is acknowledged (`session.updated`), not on raw DidOpen.
    /// Not a second listen loop.
    private var outboundQueue: [String] = []
    private var testSendSink = false
    private var sessionReady = false
    private var deliveredForTests: [String] = []
    /// Close a flushed command on a short quiet after flush. The
    /// queued utterance is already in the buffer. Do not postpone
    /// on live appends — a later command is a new server-VAD turn.
    private var pendingQuietCommit = false
    private var quietCommitGeneration = 0
    private static let maxOutbound = 64
    private static let quietCommitMs = 80
    /// Tests only. Recover still creates a real `URLSessionWebSocketTask`.
    private var realtimeURLOverrideForTests: URL?

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return opened
    }

    /// Live send path: socket opened, or a test attach-send-task.
    /// A leftover URLSession task that never opened is not live.
    var hasSendTask: Bool {
        lock.lock()
        defer { lock.unlock() }
        return opened || testSendSink
    }

    /// Phone sendRaw: `opened && task`, and not the testSendSink paper.
    var hasProductionSendTask: Bool {
        lock.lock()
        defer { lock.unlock() }
        return opened && task != nil && !testSendSink
    }

    var productionWebSocketTaskForTests: URLSessionWebSocketTask? {
        lock.lock()
        defer { lock.unlock() }
        return task
    }

    var usesTestSendSinkForTests: Bool {
        lock.lock()
        defer { lock.unlock() }
        return testSendSink
    }

    func setRealtimeURLOverrideForTests(_ url: URL?) {
        lock.lock()
        realtimeURLOverrideForTests = url
        lock.unlock()
    }

    var deliveredSendCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return deliveredForTests.count
    }

    var deliveredAppendPCM: [Data] {
        lock.lock()
        let payloads = deliveredForTests
        lock.unlock()
        return payloads.compactMap { Self.pcmFromAppendJSON($0) }
    }

    var deliveredSendTypes: [String] {
        lock.lock()
        let payloads = deliveredForTests
        lock.unlock()
        return payloads.compactMap { Self.typeOfSend($0) }
    }

    var deliveredSends: [String] {
        lock.lock()
        defer { lock.unlock() }
        return deliveredForTests
    }

    /// Dogfood: API key in `Authorization` plus `xai-client-secret.<key>` protocol.
    /// URLSession drops `Authorization` on the HTTP→WS upgrade (xAI VoiceTesterApp).
    /// Ephemeral tokens (`POST /v1/realtime/client_secrets`) are the next hardening — not a dogfood blocker.
    func connect(apiKey: String, model: String = VoiceDeskSecrets.model) {
        disconnect()

        lock.lock()
        let override = realtimeURLOverrideForTests
        let url = override ?? GrokVoiceAPI.realtimeURL(model: model)
        lock.unlock()
        let bridge = WebSocketBridge(client: self)

        lock.lock()
        sessionDelegate = bridge
        let urlSession = URLSession(configuration: .default, delegate: bridge, delegateQueue: nil)
        session = urlSession
        // URLSession drops `Authorization` on the WS upgrade; VoiceTesterApp uses this protocol.
        // Same credential as Bearer. Ephemeral tokens are next hardening, not a dogfood blocker.
        // Override is a local loopback — still URLSessionWebSocketTask. Skip the
        // xAI subprotocol so the RFC 6455 handshake can finish.
        let wsTask: URLSessionWebSocketTask
        if override != nil {
            wsTask = urlSession.webSocketTask(with: url)
        } else {
            wsTask = urlSession.webSocketTask(
                with: url,
                protocols: ["xai-client-secret.\(apiKey)"]
            )
        }
        task = wsTask
        opened = false
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !self.isConnected else { return }
            Task { @MainActor in
                self.delegate?.grokWebSocketDidFail(error: "WebSocket timeout", httpStatus: nil)
            }
        }
        lock.unlock()

        wsTask.resume()
        receiveLoop()
    }

    func disconnect() {
        lock.lock()
        timeoutTask?.cancel()
        timeoutTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        sessionDelegate = nil
        opened = false
        sessionReady = false
        pendingQuietCommit = false
        quietCommitGeneration += 1
        lock.unlock()
    }

    func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8)
        else { return }
        sendRaw(string)
    }

    /// Called from the audio render thread with a prebuilt JSON string.
    /// Appends hold until the session is ready. `session.update` goes now.
    func sendRaw(_ string: String) {
        lock.lock()
        if Self.isAudioAppend(string), !sessionReady {
            enqueueLocked(string)
            lock.unlock()
            return
        }
        if testSendSink {
            deliveredForTests.append(string)
            lock.unlock()
            return
        }
        if opened, let task {
            lock.unlock()
            task.send(.string(string)) { _ in }
            return
        }
        enqueueLocked(string)
        lock.unlock()
    }

    /// Test hook. Not a mock Grok network client. Makes send live and
    /// flushes. The DidOpen / session-ready path is separate.
    func attachTestSendTask() {
        lock.lock()
        testSendSink = true
        sessionReady = true
        flushLockedToTestSink()
        lock.unlock()
    }

    /// Record later sends. Do not flush — session-ready does that.
    func attachTestSendRecorder() {
        lock.lock()
        testSendSink = true
        lock.unlock()
    }

    /// Eve still sees `opened` (chosen) but `sendRaw` cannot send —
    /// `opened && task` is false. 83a5c6a void-returned here.
    func dropSendTaskKeepingOpenedForTests() {
        lock.lock()
        task = nil
        lock.unlock()
    }

    func markSessionReadyAndFlush() {
        lock.lock()
        sessionReady = true
        let queued = outboundQueue
        outboundQueue.removeAll()
        let task = self.task
        let sink = testSendSink
        let shouldCloseTurn = queued.contains { Self.isAudioAppend($0) }
        if sink {
            deliveredForTests.append(contentsOf: queued)
        }
        lock.unlock()
        if !sink {
            for item in queued {
                task?.send(.string(item)) { _ in }
            }
        }
        if shouldCloseTurn {
            lock.lock()
            pendingQuietCommit = true
            quietCommitGeneration += 1
            let gen = quietCommitGeneration
            lock.unlock()
            scheduleQuietCommit(generation: gen)
        }
    }

    private func scheduleQuietCommit(generation: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.quietCommitMs))
            self?.commitIfStillQuiet(generation: generation)
        }
    }

    private func commitIfStillQuiet(generation: Int) {
        lock.lock()
        guard pendingQuietCommit, quietCommitGeneration == generation else {
            lock.unlock()
            return
        }
        pendingQuietCommit = false
        lock.unlock()
        sendJSON(GrokRealtime.commitAudioBufferObject())
    }

    func dropOutbound() {
        lock.lock()
        outboundQueue.removeAll()
        deliveredForTests.removeAll()
        testSendSink = false
        sessionReady = false
        pendingQuietCommit = false
        quietCommitGeneration += 1
        lock.unlock()
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

    private func enqueueLocked(_ string: String) {
        if outboundQueue.count >= Self.maxOutbound {
            outboundQueue.removeFirst()
        }
        outboundQueue.append(string)
    }

    private func flushLockedToTestSink() {
        deliveredForTests.append(contentsOf: outboundQueue)
        outboundQueue.removeAll()
    }

    static func isAudioAppend(_ raw: String) -> Bool {
        raw.contains("input_audio_buffer.append")
    }

    static func typeOfSend(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }
        return type
    }

    static func pcmFromAppendJSON(_ raw: String) -> Data? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "input_audio_buffer.append",
              let audio = object["audio"] as? String
        else { return nil }
        return Data(base64Encoded: audio)
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

    /// URLSession delivers these on a background queue. Hop Sendable values only.
    /// Socket is open. Do not flush appends — session is not ready yet.
    /// Paper DidOpen without a real task must not mark the client opened —
    /// phone sendRaw only sends when `opened && task`.
    nonisolated func notifyOpen() {
        lock.lock()
        opened = task != nil
        let timeout = timeoutTask
        timeoutTask = nil
        lock.unlock()
        timeout?.cancel()
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.grokWebSocketDidOpen()
        }
    }

    nonisolated func notifyClose(code: Int, reason: Data?) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }
        setOpened(false)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.grokWebSocketDidClose(code: code, reason: reasonText)
        }
    }

    nonisolated func notifyComplete(status: Int?, error: String?) {
        guard let error else { return }
        setOpened(false)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.grokWebSocketDidFail(error: error, httpStatus: status)
        }
    }

    private func setOpened(_ value: Bool) {
        lock.lock()
        opened = value
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
                    self.forwardJSON(text.data(using: .utf8))
                case .data(let data):
                    if Self.looksLikeJSONObject(data) {
                        self.forwardJSON(data)
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
                let message = error.localizedDescription
                self.setOpened(false)
                Task { @MainActor in
                    self.delegate?.grokWebSocketDidFail(error: message, httpStatus: nil)
                }
            }
        }
    }

    /// Parse on the main actor so `[String: Any]` never crosses isolation.
    private func forwardJSON(_ data: Data?) {
        guard let data else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else { return }
            self.delegate?.grokWebSocketDidReceive(json: json, type: type)
        }
    }

    private static func looksLikeJSONObject(_ data: Data) -> Bool {
        guard let first = data.first(where: { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\n") && $0 != UInt8(ascii: "\r") && $0 != UInt8(ascii: "\t") }) else {
            return false
        }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }
}

/// URLSession owns this object on its delegate queue. It is not Sendable: it only
/// extracts Int / String / Data and hops those onto the client.
private final class WebSocketBridge: NSObject, URLSessionWebSocketDelegate, URLSessionTaskDelegate {
    /// Set once in `init`, then only read from session callbacks.
    nonisolated(unsafe) private weak var client: LiveGrokVoiceClient?

    init(client: LiveGrokVoiceClient) {
        self.client = client
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol proto: String?
    ) {
        _ = proto
        client?.notifyOpen()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith code: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        client?.notifyClose(code: code.rawValue, reason: reason)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode
        client?.notifyComplete(status: status, error: error?.localizedDescription)
    }
}

/// On-device wake phrase while the app is open. Phrase is an open PRD decision.
@MainActor
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
