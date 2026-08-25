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
    private var verbatim = VerbatimSpeakGate()
    /// Same leftover-echo families as AppModel. Lives here so `speech_started`
    /// can drop before `interruptAssistant` — AppModel never sees the cancel.
    private var echoGate = EchoTranscriptGate()
    private var restoreAudioSuppressAfterVerbatim = false
    private var instructions = GrokRealtime.presenceInstructions
    /// In-flight `connectAndConfigure` so warmup and first tap share one handshake.
    private var connectingTask: Task<Void, Error>?
    /// True once the live socket opened during this process lifetime.
    private var didConnectThisLaunch = false
    /// Set when a local desk / verbatim line starts. Cleared after playback
    /// drains (or immediately when there is no audio left to play).
    private var pendingListenAfterDeskSpeak = false

    var state: VoiceState { session.state }

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
        audio.onPlaybackDrained = { [weak self] in
            self?.armListenAfterPlaybackDrained()
        }
    }

    func warmUp() async {
        userWantsVoiceOff = false
        isTearingDown = false
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { return }
        do {
            try await ensureReadyForFirstListen()
        } catch {
            // First tap waits / retries. Stay idle so we do not swallow a turn.
        }
    }

    func startListening() async -> String {
        userWantsVoiceOff = false
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
        echoGate.beginSpeaking(trimmed)
        if GrokRealtime.shouldSpeakViaRealtime(
            usesLiveLoop: usesLiveLoop,
            isConnected: client.isConnected,
            userWantsVoiceOff: userWantsVoiceOff
        ) {
            speakVerbatimViaGrok(trimmed)
            return
        }
        ClientVoiceSpeech.shared.speak(trimmed)
        echoGate.finishSpeaking()
        pendingListenAfterDeskSpeak = false
        armListenIfSessionLive(reason: "client tts")
    }

    /// Eve reads the already-written local desk reply. Never mute this path —
    /// only leftover Grok handoff audio stays dropped until this response starts.
    private func speakVerbatimViaGrok(_ text: String) {
        ClientVoiceSpeech.shared.stop()
        pendingListenAfterDeskSpeak = true
        verbatim.begin()
        restoreAudioSuppressAfterVerbatim = dropAssistantAudio || dropAssistantTranscript
        // Keep leftover Grok handoff muted until THIS verbatim response.created.
        dropAssistantAudio = true
        dropAssistantTranscript = true
        interruptAssistant(sendCancel: true)
        client.sendJSON(GrokRealtime.verbatimSpeakSessionUpdateObject(voice: voiceID, text: text))
        client.sendJSON(GrokRealtime.textItemObject(GrokRealtime.verbatimSpeakUserText(text: text)))
        client.sendJSON(GrokRealtime.responseCreateObject())
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
        // claimLocalAssistantReply() calls this on every desk turn. Do not
        // cancel an in-flight Eve SPEAK_VERBATIM — leftover Grok handoff
        // is already muted, and response.cancel here kills the digest.
        if verbatim.isSpeaking { return }
        interruptAssistant(sendCancel: true)
    }

    func suppressAssistantOutput(_ suppress: Bool) {
        if suppress {
            // Claim/mute Grok handoff only. An in-flight Eve digest must keep speaking.
            if verbatim.isSpeaking {
                dropAssistantTranscript = true
                dropAssistantAudio = verbatim.awaitingCreated
                return
            }
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
        pendingListenAfterDeskSpeak = false
        echoGate.cancelSpeaking()
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
        let logs = audio.start(echoCancellation: true) { base64 in
            socket.sendRaw(GrokRealtime.appendAudioJSON(base64: base64))
        }
        logListenResume(
            note: "audio.start \(logs.joined(separator: "; ")) running=\(audio.isRunning)",
            errors: audio.isRunning ? [] : logs
        )
    }

    /// Desk TTS can leave `engine.isRunning == true` with a silent tap.
    /// Always reinstall the tap when the policy says resume.
    private func resumeCaptureAfterDeskSpeak() {
        guard !userWantsVoiceOff else { return }
        let socket = client
        let logs = audio.resumeCapture(echoCancellation: true) { base64 in
            socket.sendRaw(GrokRealtime.appendAudioJSON(base64: base64))
        }
        logListenResume(
            note: "audio.resume \(logs.joined(separator: "; ")) running=\(audio.isRunning)",
            errors: audio.isRunning ? [] : logs
        )
    }

    /// After a completed desk speak (or a socket recover mid-session): keep
    /// hearing. Resume capture if the socket is up; reconnect without a new
    /// first-tap if it closed and the user did not tap stop.
    private func armListenIfSessionLive(reason: String) {
        guard !userWantsVoiceOff, !isTearingDown else { return }
        echoGate.finishSpeaking()
        ListenResumePolicy.applySessionAfterDeskSpeak(&session)
        eventHandler?(.state(session.state))
        let decision = ListenResumePolicy.afterDeskSpeak(
            userWantsVoiceOff: userWantsVoiceOff,
            socketConnected: client.isConnected,
            captureRunning: audio.isRunning
        )
        logListenResume(
            note: "after \(reason): \(decision) state=\(session.state.rawValue) capture=\(audio.isRunning)"
        )
        switch decision {
        case .stayIdle:
            return
        case .keepListening, .resumeCapture:
            sendListenResumeSessionUpdate()
            resumeCaptureAfterDeskSpeak()
        case .reconnect:
            guard !isRecovering else {
                sendListenResumeSessionUpdate()
                resumeCaptureAfterDeskSpeak()
                return
            }
            Task { await recoverAfterDrop(reason: "listen resume after \(reason)") }
        }
    }

    /// `response.done` is early. Walks 1–2 went deaf after the spoken calendar
    /// line finished in the speaker — re-arm the tap once playback drains.
    private func armListenAfterPlaybackDrained() {
        guard pendingListenAfterDeskSpeak else { return }
        pendingListenAfterDeskSpeak = false
        armListenIfSessionLive(reason: "playback drained")
    }

    private func logListenResume(note: String, errors: [String] = []) {
        guard VoiceDogfoodGate.allowsLogging else { return }
        let entry = ListenResumeLog.entry(note: note, errors: errors)
        #if DEBUG
        DebugVoiceLogFile.append(entry)
        #endif
        VoiceCloudDogfoodClient.shared.enqueue(entry)
    }

    /// Gate first. Dropped echo never cancels Eve or reaches Grok as a turn.
    private func applyBargeInIfNeeded(event: GrokRealtime.EventKind) {
        guard EchoBargeIn.shouldCancelSpeak(
            event: event,
            gate: echoGate,
            voiceState: session.state
        ) else { return }
        if verbatim.isSpeaking {
            verbatim.cancel()
            echoGate.cancelSpeaking()
        }
        interruptAssistant(sendCancel: true)
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
        client.disconnect()
        audio.interruptPlayback()
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
            armListenIfSessionLive(reason: "socket recover")
            isRecovering = false
        } catch {
            isRecovering = false
            guard !userWantsVoiceOff else { return }
            eventHandler?(.failed(error.localizedDescription))
            teardown(sendCancel: false)
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
        logListenResume(
            note: "session close code=\(code) reason=\(reason ?? "") state=\(session.state.rawValue)"
        )
        guard !isTearingDown, !isRecovering else { return }
        let stayLive = ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: userWantsVoiceOff,
            sessionShouldStayLive: session.state != .idle
        )
        let detail = "Grok disconnected"
        if stayLive == .reconnect,
           VoiceSocketRecovery.shouldReconnect(
            error: detail,
            alreadyTried: reconnectsUsed >= VoiceSocketRecovery.maxAutomaticReconnects,
            userWantsVoiceOff: userWantsVoiceOff
           ) {
            reconnectsUsed += 1
            Task { await recoverAfterDrop(reason: detail) }
            return
        }
        guard session.state != .idle, !userWantsVoiceOff else { return }
        eventHandler?(.failed(detail))
        teardown(sendCancel: false)
    }

    func grokWebSocketDidFail(error: String, httpStatus: Int?) {
        let detail = httpStatus.map { "\($0) \(error)" } ?? error
        if !isRecovering {
            failReady(GrokVoiceError.connectFailed(detail))
        }
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
        teardown(sendCancel: false)
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
            applyBargeInIfNeeded(event: .speechStarted)
        case .speechStopped:
            if session.state == .listening {
                apply(.listenFinished)
            }
        case .audioCommitted:
            break
        case .userTranscript(let text, let itemID):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if GrokRealtime.isVerbatimSpeakPrompt(trimmed) { break }
            guard !trimmed.isEmpty else { break }
            // Drop echo BEFORE barge-in / AppModel / Grok. A leftover
            // "voice" / "point" / "build" must not stop the version line.
            guard EchoBargeIn.acceptedUserTranscript(
                trimmed,
                gate: echoGate,
                voiceState: session.state
            ) != nil else { break }
            applyBargeInIfNeeded(event: .userTranscript(text: trimmed, itemID: itemID))
            eventHandler?(.userTranscript(trimmed, isFinal: true, itemID: itemID))
        case .responseCreated(let id):
            currentResponseID = id
            assistantGate.reset()
            if verbatim.created(id) {
                dropAssistantAudio = false
            }
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
        case .responseDone(let doneID):
            if verbatim.shouldIgnoreDone(eventID: doneID, currentID: currentResponseID) {
                break
            }
            apply(.turnFinished)
            let finishedID = currentResponseID
            currentResponseID = nil
            audioDeltaCount = 0
            assistantGate.reset()
            if verbatim.finishDone(eventID: doneID, currentID: finishedID) {
                dropAssistantAudio = restoreAudioSuppressAfterVerbatim
                dropAssistantTranscript = restoreAudioSuppressAfterVerbatim
                armListenIfSessionLive(reason: "desk speak")
                break
            }
            eventHandler?(.assistantTranscript("", isFinal: true))
        case .ping(let timestamp):
            client.sendJSON(GrokRealtime.pongObject(timestamp: timestamp))
        case .error(let code, let message):
            eventHandler?(.failed("\(code) \(message)".trimmingCharacters(in: .whitespaces)))
            if code == "timeout" || code == "max_duration" {
                teardown(sendCancel: false)
            }
        case .ignored:
            break
        }
    }
}
