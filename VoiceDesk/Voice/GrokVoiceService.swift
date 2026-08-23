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
    private var restoreAudioSuppressAfterVerbatim = false
    private var instructions = GrokRealtime.presenceInstructions
    private var echo = EchoBargeInGate()
    private let captureGate = MicrophoneCaptureGate()
    private var unmuteTask: Task<Void, Never>?
    private var speakingWatchdog: Task<Void, Never>?
    private var speakingStartedAt: Date?

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
        if session.state == .speaking || session.state == .thinking {
            recoverToListening(playedAudio: audioDeltaCount > 0)
        }
        if session.state != .idle {
            if !client.isConnected, !isRecovering {
                await recoverAfterDrop(reason: "tap talk")
            }
            return ""
        }
        isTearingDown = false
        reconnectsUsed = 0
        echo.reset()
        captureGate.setMuted(false)
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
        beginHalfDuplex()
        // Keep leftover Grok handoff muted until THIS verbatim response.created.
        // Do not restore desk-claim mute after Eve finishes — weather / trivia
        // must play on the next turn.
        dropAssistantAudio = true
        dropAssistantTranscript = true
        restoreAudioSuppressAfterVerbatim = AssistantPlaybackPolicy.restoreSuppressAfterVerbatim
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
        if !verbatim.isSpeaking {
            dropAssistantAudio = false
            dropAssistantTranscript = false
        }
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
        VoiceEarcon.listenEnded()
        teardown(sendCancel: true)
    }

    private func connectAndConfigure() async throws {
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

    private func startAudioIfNeeded() {
        guard !userWantsVoiceOff, !audio.isRunning else { return }
        let socket = client
        let gate = captureGate
        _ = audio.start(echoCancellation: true) { base64 in
            guard !gate.isMuted() else { return }
            socket.sendRaw(GrokRealtime.appendAudioJSON(base64: base64))
        }
    }

    private func beginHalfDuplex() {
        echo.assistantStarted()
        captureGate.setMuted(true)
        unmuteTask?.cancel()
        if client.isConnected {
            client.sendJSON(GrokRealtime.clearBufferObject())
        }
    }

    private func endHalfDuplex(playedAudio: Bool) {
        speakingWatchdog?.cancel()
        speakingWatchdog = nil
        speakingStartedAt = nil
        if playedAudio {
            echo.assistantFinished()
        } else {
            echo.assistantAborted()
        }
        unmuteTask?.cancel()
        unmuteTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self, !Task.isCancelled else { return }
            guard !self.echo.assistantSpeaking, !self.verbatim.isSpeaking else { return }
            self.captureGate.setMuted(false)
            if self.client.isConnected, !self.userWantsVoiceOff {
                self.client.sendJSON(GrokRealtime.clearBufferObject())
            }
        }
    }

    /// Never leave `.speaking` after error, cancel leftover, or a silent response.
    private func recoverToListening(playedAudio: Bool) {
        if verbatim.isSpeaking {
            verbatim.cancel()
        }
        endHalfDuplex(playedAudio: playedAudio)
        currentResponseID = nil
        audioDeltaCount = 0
        if session.state == .speaking || session.state == .thinking {
            apply(.turnFinished)
        }
    }

    private func scheduleSpeakingWatchdog() {
        speakingWatchdog?.cancel()
        let expectedID = currentResponseID
        speakingStartedAt = Date()
        speakingWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AssistantPlaybackPolicy.silentSpeakingTimeout))
            guard let self, !Task.isCancelled else { return }
            guard self.session.state == .speaking else { return }
            guard self.currentResponseID == expectedID else { return }
            let elapsed = self.speakingStartedAt.map { Date().timeIntervalSince($0) } ?? AssistantPlaybackPolicy.silentSpeakingTimeout
            guard AssistantPlaybackPolicy.shouldForceEndSpeaking(
                audioDeltaCount: self.audioDeltaCount,
                elapsed: elapsed
            ) else { return }
            self.recoverToListening(playedAudio: false)
        }
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
        speakingWatchdog?.cancel()
        speakingWatchdog = nil
        speakingStartedAt = nil
        unmuteTask?.cancel()
        if verbatim.isSpeaking {
            verbatim.cancel()
        }
        captureGate.setMuted(true)
        echo.reset()
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
            isRecovering = false
            eventHandler?(.recovered)
            if session.state == .idle {
                apply(.tapTalk)
            }
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
        sendSessionUpdate()
        startAudioIfNeeded()
    }

    func grokWebSocketDidClose(code: Int, reason: String?) {
        failReady(GrokVoiceError.connectFailed("closed \(code) \(reason ?? "")"))
        guard !isTearingDown, !isRecovering else { return }
        guard !userWantsVoiceOff else { return }
        let detail = "Grok disconnected"
        if session.state != .idle,
           VoiceSocketRecovery.shouldReconnect(
            error: detail,
            alreadyTried: reconnectsUsed >= VoiceSocketRecovery.maxAutomaticReconnects,
            userWantsVoiceOff: userWantsVoiceOff
           ) {
            reconnectsUsed += 1
            Task { await recoverAfterDrop(reason: detail) }
            return
        }
        guard session.state != .idle else { return }
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
            guard echo.shouldAcceptUserInput() else { break }
            // New user utterance: clear leftover desk-claim mute so weather
            // after inbox can create a playable Grok response (VAD races transcript).
            if !verbatim.isSpeaking {
                dropAssistantAudio = false
                dropAssistantTranscript = false
                restoreAudioSuppressAfterVerbatim = false
            }
            interruptAssistant(sendCancel: true)
        case .speechStopped:
            if session.state == .listening {
                apply(.listenFinished)
            }
        case .audioCommitted:
            break
        case .userTranscript(let text, let itemID):
            guard echo.shouldAcceptUserInput() else { break }
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
                dropAssistantTranscript = false
            }
            if AssistantPlaybackPolicy.shouldEnterHalfDuplex(
                dropAssistantAudio: dropAssistantAudio,
                verbatimSpeaking: verbatim.isSpeaking
            ) {
                beginHalfDuplex()
                apply(.speakStarted)
                scheduleSpeakingWatchdog()
            }
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
            let playedAudio = audioDeltaCount > 0
            apply(.turnFinished)
            let finishedID = currentResponseID
            currentResponseID = nil
            audioDeltaCount = 0
            assistantGate.reset()
            endHalfDuplex(playedAudio: playedAudio)
            if verbatim.finishDone(eventID: doneID, currentID: finishedID) {
                dropAssistantAudio = AssistantPlaybackPolicy.restoreSuppressAfterVerbatim
                dropAssistantTranscript = AssistantPlaybackPolicy.restoreSuppressAfterVerbatim
                restoreAudioSuppressAfterVerbatim = false
                sendSessionUpdate()
                break
            }
            eventHandler?(.assistantTranscript("", isFinal: true))
        case .ping(let timestamp):
            client.sendJSON(GrokRealtime.pongObject(timestamp: timestamp))
        case .error(let code, let message):
            let detail = GrokRealtime.formatError(code: code, message: message)
            eventHandler?(.failed(detail))
            recoverToListening(playedAudio: audioDeltaCount > 0)
            if code == "timeout" || code == "max_duration" {
                teardown(sendCancel: false)
            }
        case .ignored:
            break
        }
    }
}
