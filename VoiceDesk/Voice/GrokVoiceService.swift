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
    /// Tags each connect attempt so a stale setup timeout cannot fail the
    /// session that replaced it.
    private var connectAttempt = 0
    private var isTearingDown = false
    private var isRecovering = false
    private var reconnectsUsed = 0
    /// Re-checks that mic buffers still flow and the socket is still up.
    /// Everything else here is edge-triggered, so this is the only thing that
    /// catches a failure that never announced itself.
    private var watchdog: Task<Void, Never>?
    private var turnTimeout = VoiceTurnTimeout()
    nonisolated static let watchdogInterval: Duration = .seconds(1)
    /// User tap-stop / cancel / explicit voice off. Blocks auto-reconnect and
    /// auto `startListening` until the next Tap to talk.
    private var userWantsVoiceOff = false
    private var dropAssistantTranscript = false
    private var dropAssistantAudio = false
    private var verbatim = VerbatimSpeakGate()
    private var restoreAudioSuppressAfterVerbatim = false
    private var instructions = GrokRealtime.presenceInstructions

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
    }

    func startListening() async -> String {
        userWantsVoiceOff = false
        if session.state != .idle {
            // Already armed. Repair whatever is actually broken rather than
            // no-oping — a tap on a session with a dead mic must fix the mic.
            reconnectsUsed = 0
            if !client.isConnected, !isRecovering {
                await recoverAfterDrop(reason: "tap talk")
            }
            startAudioIfNeeded()
            startWatchdog()
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
            try await connectAndConfigure()
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
        if GrokRealtime.shouldSpeakViaRealtime(
            usesLiveLoop: usesLiveLoop,
            isConnected: client.isConnected,
            userWantsVoiceOff: userWantsVoiceOff
        ) {
            speakVerbatimViaGrok(trimmed)
            return
        }
        ClientVoiceSpeech.shared.speak(trimmed)
    }

    /// Eve reads the already-written local desk reply. Never mute this path —
    /// only leftover Grok handoff audio stays dropped until this response starts.
    private func speakVerbatimViaGrok(_ text: String) {
        ClientVoiceSpeech.shared.stop()
        verbatim.begin()
        restoreAudioSuppressAfterVerbatim = dropAssistantAudio || dropAssistantTranscript
        // Keep leftover Grok handoff muted until THIS verbatim response.created.
        dropAssistantAudio = true
        dropAssistantTranscript = true
        interruptAssistant(sendCancel: true)
        client.sendJSON(
            GrokRealtime.sessionUpdateObject(
                voice: voiceID,
                instructions: GrokRealtime.verbatimSpeakInstructions(text: text)
            )
        )
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
        teardown(sendCancel: true)
    }

    private func connectAndConfigure() async throws {
        // Never strand a waiter from a previous attempt on this continuation.
        failReady(GrokVoiceError.connectFailed("Superseded by a newer connect"))
        connectAttempt += 1
        let attempt = connectAttempt
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyContinuation = continuation
            client.connect(apiKey: apiKey, model: model)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard let self, self.connectAttempt == attempt else { return }
                self.failReady(GrokVoiceError.connectFailed("Session setup timeout"))
            }
        }
    }

    private func sendSessionUpdate() {
        client.sendJSON(GrokRealtime.sessionUpdateObject(voice: voiceID, instructions: instructions))
    }

    /// `isRunning` was the old guard, and it lies: an engine whose tap was
    /// detached by a route change still reports a running graph, so capture was
    /// never restarted and the user went unheard for the rest of the session.
    private func startAudioIfNeeded() {
        guard !userWantsVoiceOff, !audio.isCaptureHealthy else { return }
        let socket = client
        audio.onCaptureFailure = { [weak self] message in
            self?.eventHandler?(.failed(message))
        }
        _ = audio.start(echoCancellation: true) { base64 in
            socket.sendRaw(GrokRealtime.appendAudioJSON(base64: base64))
        }
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.watchdogInterval)
                guard !Task.isCancelled, let self else { return }
                self.watchdogTick()
            }
        }
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func watchdogTick() {
        guard !userWantsVoiceOff, !isTearingDown, session.state != .idle else { return }
        audio.checkCaptureHealth()

        // A silent desk turn produces no response at all. Hand the turn back
        // rather than sitting in `.thinking` until the user taps.
        if currentResponseID == nil, turnTimeout.hasStalled() {
            apply(.turnFinished)
        }

        guard !client.isConnected, !isRecovering else { return }
        Task { await recoverAfterDrop(reason: "watchdog") }
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
        stopWatchdog()
        if sendCancel, client.isConnected {
            interruptAssistant(sendCancel: true)
            client.sendJSON(GrokRealtime.clearBufferObject())
        }
        failReady(GrokVoiceError.connectFailed("Cancelled"))
        ClientVoiceSpeech.shared.stop()
        audio.interruptPlayback()
        audio.onCaptureFailure = nil
        audio.stop()
        client.disconnect()
        currentResponseID = nil
        audioDeltaCount = 0
        apply(.cancel)
        isTearingDown = false
    }

    private func apply(_ event: VoiceSessionEvent) {
        session.apply(event)
        turnTimeout.stateChanged(to: session.state)
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

    /// Retries with backoff until the budget runs out. A single attempt left a
    /// real conversation dead on the second blip of a cell handoff.
    private func recoverAfterDrop(reason: String) async {
        _ = reason
        guard !userWantsVoiceOff, !isTearingDown, !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }

        while !userWantsVoiceOff, !isTearingDown {
            let delay = VoiceSocketRecovery.reconnectDelay(attemptsUsed: reconnectsUsed)
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !userWantsVoiceOff, !isTearingDown else { return }
            }

            client.disconnect()
            audio.interruptPlayback()
            do {
                try await connectAndConfigure()
                guard !userWantsVoiceOff else {
                    audio.stop()
                    client.disconnect()
                    return
                }
                reconnectsUsed = 0
                eventHandler?(.recovered)
                if session.state == .idle {
                    apply(.tapTalk)
                }
                // The socket is new; make sure the mic is feeding it.
                startAudioIfNeeded()
                startWatchdog()
                return
            } catch {
                reconnectsUsed += 1
                guard !userWantsVoiceOff, !isTearingDown else { return }
                guard VoiceSocketRecovery.shouldReconnect(
                    kind: .transient,
                    attemptsUsed: reconnectsUsed,
                    userWantsVoiceOff: userWantsVoiceOff
                ) else {
                    eventHandler?(.failed(error.localizedDescription))
                    teardown(sendCancel: false)
                    return
                }
            }
        }
    }
}

extension GrokVoiceService: LiveGrokVoiceClientDelegate {
    func grokWebSocketDidOpen() {
        sendSessionUpdate()
        startAudioIfNeeded()
        startWatchdog()
    }

    func grokWebSocketDidClose(code: Int, reason: String?) {
        let detail = "Grok disconnected"
        // Failing the waiter immediately lets a reconnect retry now instead of
        // sitting out the full setup timeout first.
        failReady(GrokVoiceError.connectFailed("closed \(code) \(reason ?? "")"))
        guard !isTearingDown, !isRecovering, !userWantsVoiceOff else { return }
        guard session.state != .idle else { return }
        handleSocketFailure(detail: detail, kind: .transient)
    }

    func grokWebSocketDidFail(error: String, httpStatus: Int?) {
        let kind = VoiceSocketRecovery.classify(error: error, httpStatus: httpStatus)
        // Our own `disconnect()` on the way to a fresh socket is not a failure.
        guard kind != .intentionalCancel else { return }
        let detail = httpStatus.map { "\($0) \(error)" } ?? error
        failReady(GrokVoiceError.connectFailed(detail))
        guard !isTearingDown, !isRecovering, !userWantsVoiceOff else { return }
        handleSocketFailure(detail: detail, kind: kind)
    }

    private func handleSocketFailure(detail: String, kind: VoiceSocketRecovery.FailureKind) {
        guard VoiceSocketRecovery.shouldReconnect(
            kind: kind,
            attemptsUsed: reconnectsUsed,
            userWantsVoiceOff: userWantsVoiceOff
        ) else {
            eventHandler?(.failed(detail))
            teardown(sendCancel: false)
            return
        }
        Task { await recoverAfterDrop(reason: detail) }
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
            startWatchdog()
            finishReady()
        case .sessionUpdated:
            startAudioIfNeeded()
            startWatchdog()
            finishReady()
        case .speechStarted:
            interruptAssistant(sendCancel: true)
        case .speechStopped:
            if session.state == .listening {
                apply(.listenFinished)
            }
        case .audioCommitted:
            break
        case .userTranscript(let text, let itemID):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if GrokRealtime.isVerbatimSpeakPrompt(trimmed) { break }
            if !trimmed.isEmpty {
                eventHandler?(.userTranscript(trimmed, isFinal: true, itemID: itemID))
            }
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
                sendSessionUpdate()
                break
            }
            eventHandler?(.assistantTranscript("", isFinal: true))
        case .ping(let timestamp):
            client.sendJSON(GrokRealtime.pongObject(timestamp: timestamp))
        case .error(let code, let message):
            let detail = "\(code) \(message)".trimmingCharacters(in: .whitespaces)
            // A realtime session has a hard lifetime. Hitting it used to end
            // the conversation for good; reconnect and keep the desk live.
            if code == "timeout" || code == "max_duration" {
                guard !userWantsVoiceOff, session.state != .idle else {
                    eventHandler?(.failed(detail))
                    teardown(sendCancel: false)
                    break
                }
                reconnectsUsed = 0
                Task { await recoverAfterDrop(reason: detail) }
                break
            }
            eventHandler?(.failed(detail))
        case .ignored:
            break
        }
    }
}
