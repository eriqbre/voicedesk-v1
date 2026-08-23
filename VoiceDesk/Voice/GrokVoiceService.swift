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
    private var heldVerbatimAudio: [Data] = []
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
    /// leftover Grok handoff stays dropped until the verbatim digest is playable
    /// (non-refusal transcript), not merely `response.created`.
    private func speakVerbatimViaGrok(_ text: String) {
        ClientVoiceSpeech.shared.stop()
        verbatim.begin()
        heldVerbatimAudio.removeAll()
        restoreAudioSuppressAfterVerbatim = dropAssistantAudio || dropAssistantTranscript
        // Keep leftover Grok handoff muted. Unmute only when heard text is the digest.
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
        heldVerbatimAudio.removeAll()
    }

    private func flushHeldVerbatimAudio() {
        for chunk in heldVerbatimAudio {
            audio.playPCM16(chunk)
        }
        heldVerbatimAudio.removeAll()
    }

    private func playOrHoldAssistantAudio(_ data: Data) {
        if verbatim.isSpeaking {
            if verbatim.allowsAudio(deskClaimed: dropAssistantTranscript) {
                dropAssistantAudio = false
                flushHeldVerbatimAudio()
                audio.playPCM16(data)
                return
            }
            if !verbatim.awaitingCreated {
                heldVerbatimAudio.append(data)
            }
            return
        }
        guard !dropAssistantAudio else { return }
        audio.playPCM16(data)
    }

    func cancel() {
        userWantsVoiceOff = true
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
        _ = audio.start(echoCancellation: true) { base64 in
            socket.sendRaw(GrokRealtime.appendAudioJSON(base64: base64))
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
        ClientVoiceSpeech.shared.stop()
        audio.interruptPlayback()
        audio.stop()
        client.disconnect()
        currentResponseID = nil
        audioDeltaCount = 0
        heldVerbatimAudio.removeAll()
        verbatim.cancel()
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
        playOrHoldAssistantAudio(data)
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
                // Do not unmute here. Grok may still prepend “I can’t help”.
                heldVerbatimAudio.removeAll()
            }
            apply(.speakStarted)
        case .assistantTranscriptDelta(let delta, let source):
            if verbatim.isSpeaking {
                verbatim.hear(delta)
                if verbatim.allowsAudio(deskClaimed: true) {
                    dropAssistantAudio = false
                    flushHeldVerbatimAudio()
                } else if DeskSpokenPath.shouldDiscardHeldAudio(assistantText: verbatim.heard) {
                    heldVerbatimAudio.removeAll()
                }
                break
            }
            if DeskSpokenPath.isForbiddenLiveSpeech(delta) {
                audio.interruptPlayback()
                break
            }
            guard !dropAssistantTranscript, !delta.isEmpty, assistantGate.shouldAccept(source) else { break }
            eventHandler?(.assistantTranscript(delta, isFinal: false))
        case .assistantTranscriptDone:
            break
        case .outputAudioDelta(let delta):
            if json["response_id"] as? String == currentResponseID || currentResponseID == nil {
                if let data = Data(base64Encoded: delta) {
                    playOrHoldAssistantAudio(data)
                    audioDeltaCount += 1
                }
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
            let heard = verbatim.heard
            if verbatim.finishDone(eventID: doneID, currentID: finishedID) {
                if DeskSpokenPath.allowsLiveGrokAudio(
                    deskClaimed: true,
                    verbatimSpeaking: true,
                    assistantText: heard
                ) || heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    flushHeldVerbatimAudio()
                } else {
                    heldVerbatimAudio.removeAll()
                }
                dropAssistantAudio = restoreAudioSuppressAfterVerbatim
                dropAssistantTranscript = restoreAudioSuppressAfterVerbatim
                sendSessionUpdate()
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
