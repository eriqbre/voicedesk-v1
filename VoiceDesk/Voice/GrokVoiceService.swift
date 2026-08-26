import AVFoundation
import Foundation
import Observation
import VoiceDeskLogic

/// Production voice path: live Grok speech-to-speech via `LiveGrokVoiceClient`.
@MainActor
@Observable
final class GrokVoiceService: VoiceServicing {
    let backendLabel: String
    let isInstant = false
    let needsCredentials = false
    let usesLiveLoop = true
    var eventHandler: ((VoiceServiceEvent) -> Void)?

    private var session = VoiceSession()
    private let client = LiveGrokVoiceClient()
    private let audio = GrokVoiceAudioEngine()
    private let apiKey: String
    private let voiceID: String
    private let model: String

    private var currentResponseID: String?
    private var audioDeltaCount = 0
    private var assistantGate = AssistantTranscriptGate()
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var isTearingDown = false
    private var isRecovering = false
    private var reconnectsUsed = 0
    /// User tap-stop / cancel / explicit voice off. Blocks auto-reconnect and
    /// auto `startListening` until the next Tap to talk.
    private var userWantsVoiceOff = false
    private var dropAssistantTranscript = false
    private var dropAssistantAudio = false
    private var instructions = GrokRealtime.presenceInstructions
    /// In-flight `connectAndConfigure` so warmup and first tap share one handshake.
    private var connectingTask: Task<Void, Error>?
    /// True once the live socket opened during this process lifetime.
    private var didConnectThisLaunch = false
    /// First Tap to talk armed this live loop. Cleared only on user stop.
    /// Independent of VoiceSession flipping idle after TTS / timeout.
    private var liveSessionArmed = false
    /// True only while `speak()` is writing and the player is draining.
    /// Cleared in `returnToListenAfterDeskTTS`. stayLive after drain is
    /// armed + running audio, not this flag.
    private var clientTTSInFlight = false
    /// How many times socket recover ran. Tests only — not a second loop.
    private var recoverAfterDropCount = 0
    /// Same frames the live tap sends to Grok. Tests only — not a second loop.
    /// The HAL tap is Sendable; this box is captured like `socket`, not read
    /// off `self` inside that closure.
    private let micFrames = ListenLoopMicFrames()
    var onMicFrame: (@Sendable (Data) -> Void)? {
        didSet { micFrames.set(onMicFrame) }
    }

    var state: VoiceState { session.state }
    var hasPendingPlayback: Bool { audio.hasPendingPlayback }

    init(apiKey: String, voiceID: String = VoiceDeskSecrets.voiceID, model: String = VoiceDeskSecrets.model) {
        self.apiKey = apiKey
        self.voiceID = voiceID
        self.model = model
        self.backendLabel = "Grok live · \(model) · voice \(voiceID)"
        client.delegate = self
        VoiceEarcon.playThroughLiveEngine = { [weak self] pcm in
            guard let self, self.audio.isRunning else { return false }
            self.audio.playPCM16(pcm)
            return true
        }
    }

    func warmUp() async {
        userWantsVoiceOff = false
        isTearingDown = false
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { return }
        liveSessionArmed = true
        do {
            try await ensureReadyForFirstListen()
        } catch {
            // First tap waits / retries. Stay idle so we do not swallow a turn.
        }
    }

    func startListening() async -> String {
        userWantsVoiceOff = false
        liveSessionArmed = true
        if session.state != .idle {
            if !client.isConnected, !isRecovering {
                await recoverAfterDrop(reason: "tap talk")
            }
            return ""
        }
        isTearingDown = false
        reconnectsUsed = 0
        apply(.tapTalk)
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            eventHandler?(.failed("Microphone permission denied"))
            apply(.cancel)
            return ""
        }

        do {
            try await ensureReadyForFirstListen()
        } catch {
            if session.state != .idle {
                eventHandler?(.failed(error.localizedDescription))
                teardown(sendCancel: false)
            }
        }
        return ""
    }

    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !audio.isRunning, !userWantsVoiceOff {
            startAudioIfNeeded()
        }
        clientTTSInFlight = true
        await ClientVoiceSpeech.shared.speak(trimmed) { [weak self] pcm in
            self?.audio.playPCM16(pcm)
        }
        await waitUntilPlaybackDrained()
        returnToListenAfterDeskTTS()
    }

    /// After write→player drain. Leftover created/done must not park
    /// speaking. Session back to listening. No second start.
    private func returnToListenAfterDeskTTS() {
        ListenResumePolicy.applyLeftoverGrokDuringClientTTS(&session)
        let result = ListenResumePolicy.afterClientTTSFinished(
            session: &session,
            userWantsVoiceOff: userWantsVoiceOff,
            liveSessionArmed: liveSessionArmed,
            captureRunning: audio.isRunning
        )
        clientTTSInFlight = false
        eventHandler?(.state(session.state))
        audio.reinstallTapIfSilentWhileRunning()
        logListenResume(
            note: "after desk tts drain listenArmed=\(result.listenArmed) stayLive=\(result.stayLive) \(result.close1000) startAgain=\(result.startAgain) state=\(session.state.rawValue)"
        )
    }

    private func waitUntilPlaybackDrained() async {
        if !audio.hasPendingPlayback { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            let finish = {
                guard !resumed else { return }
                resumed = true
                self.audio.onPlaybackDrained = nil
                cont.resume()
            }
            audio.onPlaybackDrained = finish
            Task { @MainActor in
                let deadline = ContinuousClock.now + .seconds(8)
                while self.audio.hasPendingPlayback, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(40))
                }
                finish()
            }
        }
    }

    func sendTextTurn(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if session.state == .idle {
            _ = await startListening()
        }
        if !client.isConnected {
            await recoverAfterDrop(reason: "text turn")
        }
        guard client.isConnected else { return }
        interruptAssistant(sendCancel: true)
        client.sendJSON(GrokRealtime.textItemObject(trimmed))
        client.sendJSON(GrokRealtime.responseCreateObject())
    }

    func updatePresenceInstructions(_ text: String) {
        instructions = text
        if client.isConnected {
            sendSessionUpdate()
        }
    }

    func interruptResponse() {
        interruptAssistant(sendCancel: true)
    }

    func suppressAssistantOutput(_ suppress: Bool) {
        if suppress {
            dropAssistantTranscript = true
            dropAssistantAudio = true
            interruptAssistant(sendCancel: true)
            return
        }
        dropAssistantTranscript = false
        dropAssistantAudio = false
    }

    func cancel() {
        userWantsVoiceOff = true
        liveSessionArmed = false
        clientTTSInFlight = false
        teardown(sendCancel: true)
    }

    private func ensureReadyForFirstListen() async throws {
        var alreadyRetried = false
        while true {
            let ready = FirstListenPolicy.isReady(
                socketConnected: client.isConnected,
                audioSessionReady: audio.isRunning
            )
            if FirstListenPolicy.beforeListen(isReady: ready) == .waitForReady {
                try await connectIfNeeded()
                await retryAudioIfNeeded()
            }

            let readyAfter = FirstListenPolicy.isReady(
                socketConnected: client.isConnected,
                audioSessionReady: audio.isRunning
            )
            if readyAfter { return }

            let next = FirstListenPolicy.afterEmptyListen(
                didConnectThisLaunch: didConnectThisLaunch,
                alreadyRetried: alreadyRetried
            )
            guard next == .retryConnectThenListen else {
                if client.isConnected { return }
                throw GrokVoiceError.connectFailed("Session not ready")
            }
            alreadyRetried = true
            client.disconnect()
            audio.stop()
        }
    }

    private func connectIfNeeded() async throws {
        if client.isConnected {
            startAudioIfNeeded()
            return
        }
        if let connectingTask {
            try await connectingTask.value
            startAudioIfNeeded()
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { throw GrokVoiceError.connectFailed("Released") }
            try await self.connectAndConfigure()
        }
        connectingTask = task
        defer { connectingTask = nil }
        try await task.value
    }

    private func retryAudioIfNeeded() async {
        startAudioIfNeeded()
        if audio.isRunning { return }
        try? await Task.sleep(for: .milliseconds(200))
        startAudioIfNeeded()
    }

    private func connectAndConfigure() async throws {
        if client.isConnected {
            startAudioIfNeeded()
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation
            client.connect(apiKey: apiKey, model: model)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                self?.failReady(GrokVoiceError.connectFailed("Session setup timeout"))
            }
        }
    }

    private func sendSessionUpdate() {
        client.sendJSON(GrokRealtime.sessionUpdateObject(voice: voiceID, instructions: instructions))
    }

    private func sendListenResumeSessionUpdate() {
        client.sendJSON(
            GrokRealtime.listenResumeSessionUpdateObject(voice: voiceID, instructions: instructions)
        )
    }

    private func startAudioIfNeeded() {
        guard !userWantsVoiceOff, !audio.isRunning else { return }
        let socket = client
        let frames = micFrames
        let logs = audio.start(echoCancellation: true) { base64 in
            socket.sendRaw(GrokRealtime.appendAudioJSON(base64: base64))
            if let pcm = Data(base64Encoded: base64) {
                frames.emit(pcm)
            }
        }
        if audio.isRunning {
            liveSessionArmed = true
        }
        logListenResume(
            note: "audio.start \(logs.joined(separator: "; ")) running=\(audio.isRunning)",
            errors: audio.isRunning ? [] : logs
        )
    }

    /// Socket recover only. Client TTS never leaves listen and must not
    /// reinstall the mic tap.
    private func armListenIfSessionLive(reason: String) {
        guard !userWantsVoiceOff, !isTearingDown else { return }
        ListenResumePolicy.applySessionAfterDeskSpeak(&session)
        eventHandler?(.state(session.state))
        let decision = ListenResumePolicy.afterDeskSpeak(
            userWantsVoiceOff: userWantsVoiceOff,
            socketConnected: client.isConnected
        )
        logListenResume(
            note: "after \(reason): \(decision) state=\(session.state.rawValue) capture=\(audio.isRunning)"
        )
        switch decision {
        case .stayIdle:
            return
        case .keepListening:
            reconnectsUsed = 0
            startAudioIfNeeded()
        case .reconnect:
            guard !isRecovering else {
                startAudioIfNeeded()
                return
            }
            Task { await recoverAfterDrop(reason: "listen resume after \(reason)") }
        }
    }

    private var sessionShouldStayLive: Bool {
        ListenResumePolicy.sessionShouldStayLive(
            userWantsVoiceOff: userWantsVoiceOff,
            liveSessionArmed: liveSessionArmed,
            audioStarted: audio.isRunning || didConnectThisLaunch,
            clientTTSInFlight: clientTTSInFlight
        )
    }

    private func logListenResume(note: String, errors: [String] = []) {
        guard VoiceDogfoodGate.allowsLogging else { return }
        let entry = ListenResumeLog.entry(note: note, errors: errors)
        #if DEBUG
        DebugVoiceLogFile.append(entry)
        #endif
        VoiceCloudDogfoodClient.shared.enqueue(entry)
    }

    private func interruptAssistant(sendCancel: Bool) {
        if sendCancel, currentResponseID != nil || session.state == .speaking {
            client.sendJSON(GrokRealtime.responseCancelObject())
        }
        ClientVoiceSpeech.shared.stop()
        audio.interruptPlayback()
        currentResponseID = nil
        audioDeltaCount = 0
        if session.state == .speaking || session.state == .thinking {
            apply(.turnFinished)
        }
    }

    private func teardown(sendCancel: Bool) {
        guard !isTearingDown else { return }
        isTearingDown = true
        if sendCancel, client.isConnected {
            interruptAssistant(sendCancel: true)
            client.sendJSON(GrokRealtime.clearBufferObject())
        }
        failReady(GrokVoiceError.connectFailed("Cancelled"))
        ClientVoiceSpeech.shared.stop()
        audio.interruptPlayback()
        audio.stop()
        client.disconnect()
        currentResponseID = nil
        audioDeltaCount = 0
        apply(.cancel)
        isTearingDown = false
    }

    private func apply(_ event: VoiceSessionEvent) {
        session.apply(event)
        eventHandler?(.state(session.state))
    }

    private func finishReady() {
        if let readyContinuation {
            self.readyContinuation = nil
            readyContinuation.resume()
        }
    }

    private func failReady(_ error: Error) {
        if let readyContinuation {
            self.readyContinuation = nil
            readyContinuation.resume(throwing: error)
        }
    }

    private func recoverAfterDrop(reason: String) async {
        _ = reason
        guard !userWantsVoiceOff, !isTearingDown, !isRecovering else { return }
        isRecovering = true
        recoverAfterDropCount += 1
        client.disconnect()
        do {
            try await connectAndConfigure()
            guard !userWantsVoiceOff else {
                isRecovering = false
                audio.stop()
                client.disconnect()
                return
            }
            reconnectsUsed = 0
            eventHandler?(.recovered)
            sendListenResumeSessionUpdate()
            armListenIfSessionLive(reason: "socket recover")
            isRecovering = false
        } catch {
            isRecovering = false
            guard !userWantsVoiceOff else { return }
            eventHandler?(.failed(error.localizedDescription))
            guard sessionShouldStayLive || liveSessionArmed || audio.isRunning else {
                teardown(sendCancel: false)
                return
            }
        }
    }
}

extension GrokVoiceService: LiveGrokVoiceClientDelegate {
    func grokWebSocketDidOpen() {
        didConnectThisLaunch = true
        sendSessionUpdate()
        startAudioIfNeeded()
    }

    func grokWebSocketDidClose(code: Int, reason: String?) {
        failReady(GrokVoiceError.connectFailed("closed \(code) \(reason ?? "")"))
        let stayLive = sessionShouldStayLive
        let decision = ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: userWantsVoiceOff,
            sessionShouldStayLive: stayLive,
            closeCode: code,
            voiceState: session.state
        )
        logListenResume(
            note: "session close code=\(code) reason=\(reason ?? "") state=\(session.state.rawValue) stayLive=\(stayLive) \(decision)"
        )
        guard !isTearingDown, !isRecovering else { return }
        let detail = "Grok disconnected"
        if decision == .reconnect,
           VoiceSocketRecovery.shouldReconnect(
            error: detail,
            alreadyTried: reconnectsUsed >= VoiceSocketRecovery.maxAutomaticReconnects,
            userWantsVoiceOff: userWantsVoiceOff
           ) {
            reconnectsUsed += 1
            Task { await recoverAfterDrop(reason: "close \(code)") }
            return
        }
        guard stayLive else { return }
        eventHandler?(.failed(detail))
    }

    func grokWebSocketDidFail(error: String, httpStatus: Int?) {
        let detail = httpStatus.map { "\($0) \(error)" } ?? error
        failReady(GrokVoiceError.connectFailed(detail))
        guard !isTearingDown, !isRecovering else { return }
        guard !userWantsVoiceOff else { return }
        if VoiceSocketRecovery.shouldReconnect(
            error: detail,
            alreadyTried: reconnectsUsed >= VoiceSocketRecovery.maxAutomaticReconnects,
            userWantsVoiceOff: userWantsVoiceOff
        ) {
            reconnectsUsed += 1
            Task { await recoverAfterDrop(reason: detail) }
            return
        }
        eventHandler?(.failed(detail))
        guard sessionShouldStayLive || liveSessionArmed || audio.isRunning else {
            teardown(sendCancel: false)
            return
        }
    }

    func grokWebSocketDidReceiveBinary(_ data: Data) {
        guard !dropAssistantAudio else { return }
        audio.playPCM16(data)
    }

    func grokWebSocketDidReceive(json: [String: Any], type: String) {
        switch GrokRealtime.parse(type: type, json: json) {
        case .sessionCreated:
            sendSessionUpdate()
            startAudioIfNeeded()
            finishReady()
        case .sessionUpdated:
            startAudioIfNeeded()
            finishReady()
        case .speechStarted:
            break
        case .speechStopped:
            break
        case .audioCommitted:
            break
        case .userTranscript(let text, let itemID):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if GrokRealtime.isVerbatimSpeakPrompt(trimmed) { break }
            guard !trimmed.isEmpty else { break }
            clientTTSInFlight = false
            eventHandler?(.userTranscript(trimmed, isFinal: true, itemID: itemID))
        case .responseCreated(let id):
            currentResponseID = id
            assistantGate.reset()
            guard ListenResumePolicy.shouldApplyGrokSpeakStarted(
                clientTTSSpeaking: audio.hasPendingPlayback || clientTTSInFlight
            ) else { break }
            apply(.speakStarted)
        case .assistantTranscriptDelta(let delta, let source):
            guard !dropAssistantTranscript, !delta.isEmpty, assistantGate.shouldAccept(source) else { break }
            eventHandler?(.assistantTranscript(delta, isFinal: false))
        case .assistantTranscriptDone:
            break
        case .outputAudioDelta(let delta):
            guard !dropAssistantAudio else { break }
            if json["response_id"] as? String == currentResponseID || currentResponseID == nil {
                audio.playAudioDelta(base64: delta)
                audioDeltaCount += 1
            }
        case .outputAudioDone:
            break
        case .responseDone:
            if ListenResumePolicy.shouldApplyGrokTurnFinished(
                clientTTSSpeaking: audio.hasPendingPlayback || clientTTSInFlight
            ) {
                apply(.turnFinished)
            } else {
                ListenResumePolicy.applySessionAfterDeskSpeak(&session)
                eventHandler?(.state(session.state))
            }
            currentResponseID = nil
            audioDeltaCount = 0
            assistantGate.reset()
            eventHandler?(.assistantTranscript("", isFinal: true))
        case .ping(let timestamp):
            client.sendJSON(GrokRealtime.pongObject(timestamp: timestamp))
        case .error(let code, let message):
            eventHandler?(.failed("\(code) \(message)".trimmingCharacters(in: .whitespaces)))
            if code == "timeout" || code == "max_duration" {
                let decision = ListenResumePolicy.afterRealtimeTimeout(
                    userWantsVoiceOff: userWantsVoiceOff,
                    liveSessionArmed: liveSessionArmed
                )
                logListenResume(note: "realtime \(code) \(decision) stayLive=\(sessionShouldStayLive)")
                if decision == .reconnect {
                    Task { await recoverAfterDrop(reason: "timeout \(code)") }
                } else {
                    teardown(sendCancel: false)
                }
            }
        case .ignored:
            break
        }
    }
}

extension GrokVoiceService {
    /// Same engine `speak()` owns. Delayed-yank tests must use this instance.
    var listenLoopEngine: GrokVoiceAudioEngine { audio }

    var listenLoopStayLive: Bool { sessionShouldStayLive }

    var listenLoopArmed: Bool { ListenResumePolicy.isListenArmed(state: session.state) }

    var listenLoopClose1000: ListenResumeDecision {
        ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: userWantsVoiceOff,
            sessionShouldStayLive: sessionShouldStayLive,
            closeCode: 1000,
            voiceState: session.state
        )
    }

    /// Same `startAudioIfNeeded` `speak()` uses. Not a second engine.
    func startListenLoopAudioForTests() {
        liveSessionArmed = true
        apply(.tapTalk)
        startAudioIfNeeded()
    }

    /// Same close the phone logged after version/desk TTS.
    /// `listenLoopClose1000` only computes policy. This fires DidClose.
    func simulateListenLoopSocketClose1000() async {
        grokWebSocketDidClose(code: 1000, reason: nil)
        await Task.yield()
        var spins = 0
        while isRecovering, spins < 400 {
            try? await Task.sleep(for: .milliseconds(50))
            spins += 1
        }
    }

    var listenLoopRecoverCount: Int { recoverAfterDropCount }

    /// `LiveGrokVoiceClient.sendRaw` no-ops when this is false.
    var listenLoopSocketHasSendTask: Bool { client.hasSendTask }
}

/// Same-thread tap observer. The HAL callback is Sendable; do not touch
/// MainActor `self` from that closure. Not a second listen loop.
private final class ListenLoopMicFrames: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (Data) -> Void)?

    func set(_ handler: (@Sendable (Data) -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func emit(_ pcm: Data) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?(pcm)
    }
}
