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
    /// The response that actually scheduled player buffers. Barge-in
    /// cancel must target this id, not the next `response.created`.
    private var playingResponseID: String?
    /// Latched when that answer first scheduled (or on speech_started).
    /// A late transcript must not cancel a newer created already playing.
    private var interruptTargetID: String?
    /// Last id that scheduled buffers. Survives `response.done` so
    /// speech_started can latch the old answer after its id was cleared.
    private var lastScheduledResponseID: String?
    /// `response.created` while the player was empty. Used only to tag
    /// the first buffer of that answer — not the next created.
    private var createdAwaitingAudioID: String?
    /// Server VAD heard speech. Keep the latched target across done.
    private var speechStartedBarge = false
    /// First barge-in already dropped local / cancelled the old answer.
    /// claimLocal and a late second transcript must not fire again.
    private var bargeConsumed = false
    /// Interrupt-answer audio arrived after the barge. Reset consumed
    /// only after this drains — R1 `response.done` must not unlock
    /// a second cancel of the new created.
    private var interruptAnswerScheduled = false
    /// `response.created` count when the barge target was latched.
    /// A later created is the interrupt answer — do not cancel it.
    private var createdCountAtBarge = 0
    private var audioDeltaCount = 0
    /// Last live created / scheduled / barge-cancel ids. Proof only.
    private var lastCreatedResponseID: String?
    private var lastBargeCancelSentID: String?
    /// First-answer id dropped on barge. Leftover deltas with this id
    /// must not raise pending after `interruptPlayback`.
    private var cancelledPlaybackResponseID: String?
    /// Leftover first-answer deltas rejected after barge. Tests only.
    private var rejectedCancelledDeltaCount = 0
    private var assistantGate = AssistantTranscriptGate()
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var isTearingDown = false
    private var isRecovering = false
    private var reconnectsUsed = 0
    /// User tap-stop / cancel / explicit voice off. Blocks auto-reconnect and
    /// auto `startListening` until the next Tap to talk.
    private var userWantsVoiceOff = false
    private var dropAssistantTranscript = false
    private var instructions = GrokRealtime.presenceInstructions
    /// In-flight `connectAndConfigure` so warmup and first tap share one handshake.
    private var connectingTask: Task<Void, Error>?
    /// True once the live socket opened during this process lifetime.
    private var didConnectThisLaunch = false
    /// First Tap to talk armed this live loop. Cleared only on user stop.
    /// Independent of VoiceSession flipping idle after TTS / timeout.
    private var liveSessionArmed = false
    /// True only while offline `speak()` is writing and the player is draining.
    /// Cleared in `returnToListenAfterDeskTTS`. Live Talk never sets this —
    /// Eve PCM is the mouth. stayLive after drain is armed + running audio.
    private var clientTTSInFlight = false
    /// Live Talk told Eve to say a desk line. Restore presence listen
    /// instructions on that response.done. Not a tap rearm.
    private var restorePresenceAfterEveSpeak = false
    /// How many times socket recover ran. Tests only — not a second loop.
    private var recoverAfterDropCount = 0
    /// Live `response.created` events. Tests only — not a second loop.
    private var responseCreatedCountForTests = 0
    /// Live `response.done` events. Tests only — not a second loop.
    private var responseDoneCountForTests = 0
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
        if GrokRealtime.shouldSpeakViaRealtime(
            usesLiveLoop: usesLiveLoop,
            isConnected: client.isConnected && liveSessionArmed,
            userWantsVoiceOff: userWantsVoiceOff
        ) {
            speakLiveReplyViaEve(trimmed)
            return
        }
        if !audio.isRunning, !userWantsVoiceOff {
            startAudioIfNeeded()
        }
        clientTTSInFlight = true
        await ClientVoiceSpeech.shared.speak(trimmed) { [weak self] pcm in
            guard let self else { return }
            self.audio.playPCM16(pcm)
            self.noteFirstAnswerPlaying()
        }
        await waitUntilPlaybackDrained()
        returnToListenAfterDeskTTS()
    }

    /// Socket up + live Talk: Eve says the line. Do not write desk TTS.
    /// Do not emit after-desk-tts-drain. Cards stay with AppModel.
    private func speakLiveReplyViaEve(_ text: String) {
        guard client.isConnected else { return }
        client.sendJSON(GrokRealtime.verbatimSpeakSessionUpdateObject(voice: voiceID, text: text))
        client.sendJSON(GrokRealtime.textItemObject(GrokRealtime.verbatimSpeakUserText(text: text)))
        client.sendJSON(GrokRealtime.responseCreateObject())
        restorePresenceAfterEveSpeak = true
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
        // One tap. Do not rearm after drain. 552ef0c's drain-time
        // reinstall left the live tap silent (no PCM, no sendRaw)
        // while stayLive stayed true. Best part is no part.
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
        // Latch leftover only after an answer scheduled on the player.
        // lastCreated at pending 0 is first-answer audio about to
        // arrive — claimLocal must not stamp that as cancelled.
        // Drop buffers only if something is still on the player.
        // Do not send response.cancel.
        guard !bargeConsumed else { return }
        let hasPending = audio.hasPendingPlayback
        guard GrokRealtime.shouldArmCommandBargeLatch(
            alreadyBarged: false,
            hasPendingPlayback: hasPending,
            lastScheduledResponseID: lastScheduledResponseID,
            playingResponseID: playingResponseID
        ) else { return }
        let knownCancelled = GrokRealtime.cancelledPlaybackResponseID(
            interruptTargetID: interruptTargetID,
            lastScheduledResponseID: lastScheduledResponseID,
            playingResponseID: playingResponseID,
            lastCreatedResponseID: lastCreatedResponseID
        )
        let decision = GrokRealtime.bargeInDecision(
            hasPendingPlayback: hasPending,
            alreadyBarged: false,
            playingResponseID: playingResponseID,
            interruptTargetID: interruptTargetID,
            currentResponseID: currentResponseID,
            createdCountAtLatch: createdCountAtBarge,
            createdCountNow: responseCreatedCountForTests
        )
        bargeConsumed = true
        lastBargeCancelSentID = decision.cancelResponseID
        cancelledPlaybackResponseID = GrokRealtime.nonemptyID(lastScheduledResponseID)
            ?? knownCancelled
            ?? GrokRealtime.playbackEpochLatch(audio.playbackEpoch)
        if decision.dropLocal {
            interruptAssistant(sendCancel: false)
        }
    }

    func suppressAssistantOutput(_ suppress: Bool) {
        dropAssistantTranscript = suppress
    }

    func cancel() {
        userWantsVoiceOff = true
        liveSessionArmed = false
        clientTTSInFlight = false
        restorePresenceAfterEveSpeak = false
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

    private func shouldPlayBargeAudio(deltaResponseID: String?) -> Bool {
        let answerID = GrokRealtime.interruptAnswerID(
            createdAwaitingAudioID: createdAwaitingAudioID,
            lastCreatedResponseID: lastCreatedResponseID,
            cancelledResponseID: cancelledPlaybackResponseID
        )
        let allow = GrokRealtime.shouldScheduleAfterBarge(
            bargeConsumed: bargeConsumed,
            deltaResponseID: deltaResponseID,
            cancelledResponseID: cancelledPlaybackResponseID,
            interruptAnswerID: answerID,
            playingResponseID: playingResponseID,
            lastScheduledResponseID: lastScheduledResponseID,
            hasPendingPlayback: audio.hasPendingPlayback
        )
        if !allow, GrokRealtime.nonemptyID(deltaResponseID) != nil {
            rejectedCancelledDeltaCount += 1
        }
        return allow
    }

    private func noteScheduledResponse(_ id: String?) {
        guard let id = GrokRealtime.nonemptyID(id) else { return }
        lastScheduledResponseID = id
        if bargeConsumed {
            if id != cancelledPlaybackResponseID {
                interruptAnswerScheduled = true
            }
            return
        }
        if interruptTargetID == nil {
            createdCountAtBarge = responseCreatedCountForTests
        }
        interruptTargetID = GrokRealtime.latchedInterruptTarget(
            existing: interruptTargetID,
            scheduledResponseID: id
        )
    }

    /// Grok PCM often omits `response_id`. Copy `response.created` (or
    /// the playback epoch) onto lastScheduled while the first answer
    /// is on the player so barge can latch leftover. If the play path
    /// raised pending without a tag (`nil != nil` skip), still write.
    private func noteFirstAnswerPlaying() {
        guard GrokRealtime.shouldWriteScheduledLatchOnPlay(
            existingScheduledID: lastScheduledResponseID,
            bargeConsumed: bargeConsumed
        ) else { return }
        let id = GrokRealtime.latchWhenFirstAnswerPlaying(
            existingScheduledID: lastScheduledResponseID,
            createdID: lastCreatedResponseID ?? createdAwaitingAudioID ?? currentResponseID,
            playbackEpoch: audio.playbackEpoch
        )
        noteScheduledResponse(id)
    }

    private func interruptAssistant(sendCancel: Bool, responseID: String? = nil) {
        let target = responseID ?? playingResponseID
        if sendCancel, let id = GrokRealtime.responseIDToCancel(playingResponseID: target) {
            lastBargeCancelSentID = id
            client.sendJSON(GrokRealtime.responseCancelObject(responseID: id))
        }
        ClientVoiceSpeech.shared.stop()
        audio.interruptPlayback()
        playingResponseID = nil
        currentResponseID = nil
        createdAwaitingAudioID = nil
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
        client.dropOutbound()
        playingResponseID = nil
        currentResponseID = nil
        interruptTargetID = nil
        lastScheduledResponseID = nil
        createdAwaitingAudioID = nil
        speechStartedBarge = false
        bargeConsumed = false
        interruptAnswerScheduled = false
        createdCountAtBarge = 0
        cancelledPlaybackResponseID = nil
        rejectedCancelledDeltaCount = 0
        audioDeltaCount = 0
        restorePresenceAfterEveSpeak = false
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
        sendListenResumeSessionUpdate()
        startAudioIfNeeded()
    }

    func grokWebSocketDidClose(code: Int, reason: String?) {
        failReady(GrokVoiceError.connectFailed("closed \(code) \(reason ?? "")"))
        let stayLive = ListenResumePolicy.sha415c955StayLiveAfterClose1000(
            userWantsVoiceOff: userWantsVoiceOff,
            listenArmed: ListenResumePolicy.isListenArmed(state: session.state)
        )
        let decision = ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: userWantsVoiceOff,
            sessionShouldStayLive: stayLive,
            closeCode: code,
            voiceState: session.state,
            liveSessionArmed: liveSessionArmed
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
        // Wire binary has no response_id. Do not fill lastCreated —
        // after barge that is still the first answer, and the gate
        // would reject R2. Only JSON leftover inject carries the
        // cancelled id.
        guard shouldPlayBargeAudio(deltaResponseID: nil) else { return }
        if playingResponseID == nil {
            let tagged = GrokRealtime.scheduledResponseID(
                deltaResponseID: nil,
                createdAwaitingAudioID: createdAwaitingAudioID,
                lastCreatedResponseID: lastCreatedResponseID
            )
            if GrokRealtime.shouldOverwriteScheduledLatch(
                existingScheduledID: lastScheduledResponseID,
                taggedID: tagged,
                deltaResponseID: nil,
                cancelledResponseID: cancelledPlaybackResponseID
            ) {
                playingResponseID = tagged
                noteScheduledResponse(tagged)
            }
        }
        audio.playPCM16(data)
        noteFirstAnswerPlaying()
    }

    func grokWebSocketDidReceive(json: [String: Any], type: String) {
        switch GrokRealtime.parse(type: type, json: json) {
        case .sessionCreated:
            startAudioIfNeeded()
            finishReady()
        case .sessionUpdated:
            startAudioIfNeeded()
            finishReady()
            client.markSessionReadyAndFlush()
        case .speechStarted:
            // Latch only. Energy must not cancel — radio / other-room
            // stays ignored. Use lastScheduled, not playing — playing
            // may already be the next created.
            if !bargeConsumed {
                if interruptTargetID == nil {
                    createdCountAtBarge = responseCreatedCountForTests
                }
                interruptTargetID = GrokRealtime.latchedInterruptTarget(
                    existing: interruptTargetID,
                    scheduledResponseID: lastScheduledResponseID
                )
            }
            speechStartedBarge = true
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
            responseCreatedCountForTests += 1
            currentResponseID = GrokRealtime.nonemptyID(id)
            lastCreatedResponseID = GrokRealtime.nonemptyID(id)
            assistantGate.reset()
            if audio.hasPendingPlayback {
                // First-answer PCM already scheduled without response_id.
                noteFirstAnswerPlaying()
            } else if playingResponseID == nil {
                createdAwaitingAudioID = lastCreatedResponseID
            }
            // Leftover Grok-created used to park VoiceSession speaking
            // and disarm listen — 415c955 first-hear-then-deaf on the
            // next close 1000. Audio plays on the one-engine player.
        case .assistantTranscriptDelta(let delta, let source):
            guard !dropAssistantTranscript, !delta.isEmpty, assistantGate.shouldAccept(source) else { break }
            eventHandler?(.assistantTranscript(delta, isFinal: false))
        case .assistantTranscriptDone:
            break
        case .outputAudioDelta(let delta):
            // Live Grok PCM on the one-engine player. After barge,
            // reject leftover that carries the cancelled first-answer
            // id. Deltas without response_id are R2 — do not eat them.
            let deltaID = GrokRealtime.responseID(in: json)
            guard shouldPlayBargeAudio(deltaResponseID: deltaID) else { break }
            if playingResponseID == nil {
                let tagged = GrokRealtime.scheduledResponseID(
                    deltaResponseID: deltaID,
                    createdAwaitingAudioID: createdAwaitingAudioID,
                    lastCreatedResponseID: lastCreatedResponseID
                )
                if GrokRealtime.shouldOverwriteScheduledLatch(
                    existingScheduledID: lastScheduledResponseID,
                    taggedID: tagged,
                    deltaResponseID: deltaID,
                    cancelledResponseID: cancelledPlaybackResponseID
                ) {
                    playingResponseID = tagged
                    noteScheduledResponse(tagged)
                }
            }
            audio.playAudioDelta(base64: delta)
            audioDeltaCount += 1
            noteFirstAnswerPlaying()
        case .outputAudioDone:
            break
        case .responseDone(let doneID):
            if restorePresenceAfterEveSpeak {
                restorePresenceAfterEveSpeak = false
                sendListenResumeSessionUpdate()
            }
            responseDoneCountForTests += 1
            if ListenResumePolicy.shouldApplyGrokTurnFinished(
                clientTTSSpeaking: audio.hasPendingPlayback || clientTTSInFlight
            ) {
                apply(.turnFinished)
            } else {
                ListenResumePolicy.applySessionAfterDeskSpeak(&session)
                eventHandler?(.state(session.state))
            }
            playingResponseID = nil
            currentResponseID = nil
            createdAwaitingAudioID = nil
            audioDeltaCount = 0
            if !audio.hasPendingPlayback {
                if bargeConsumed {
                    if GrokRealtime.shouldResetBargeAfterResponseDone(
                        bargeConsumed: true,
                        interruptAnswerScheduled: interruptAnswerScheduled,
                        lastScheduledResponseID: lastScheduledResponseID,
                        cancelledResponseID: cancelledPlaybackResponseID,
                        doneResponseID: doneID
                    ) {
                        // A different id scheduled as the interrupt
                        // answer. Do not nil cancelledPlaybackResponseID
                        // or lastScheduled — leftover inject and 1529
                        // still need the first-answer latch. First-answer
                        // done with pending 0 must not take this branch.
                        bargeConsumed = false
                        interruptAnswerScheduled = false
                        interruptTargetID = nil
                        createdCountAtBarge = 0
                        speechStartedBarge = false
                    }
                } else {
                    interruptTargetID = nil
                    lastScheduledResponseID = GrokRealtime.keepScheduledLatchAfterResponseDone(
                        existingScheduledID: lastScheduledResponseID
                    )
                    createdCountAtBarge = 0
                    speechStartedBarge = false
                }
            }
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
            sessionShouldStayLive: ListenResumePolicy.sha415c955StayLiveAfterClose1000(
                userWantsVoiceOff: userWantsVoiceOff,
                listenArmed: ListenResumePolicy.isListenArmed(state: session.state)
            ),
            closeCode: 1000,
            voiceState: session.state,
            liveSessionArmed: liveSessionArmed
        )
    }

    /// 415c955 / 18d5878 phone stayLive: listen-armed only.
    var listenLoopPhoneStayLive: Bool {
        ListenResumePolicy.sha415c955StayLiveAfterClose1000(
            userWantsVoiceOff: userWantsVoiceOff,
            listenArmed: ListenResumePolicy.isListenArmed(state: session.state)
        )
    }

    /// Phone log after version TTS: `state=idle`. User did not tap stop.
    func simulateListenLoopIdleAfterDeskTTSPhoneLog() {
        apply(.speakStarted)
        apply(.speakFinished)
    }

    /// Same `startAudioIfNeeded` `speak()` uses. Not a second engine.
    func startListenLoopAudioForTests() {
        liveSessionArmed = true
        apply(.tapTalk)
        startAudioIfNeeded()
    }

    /// Real first-listen handshake. Not recover. Not DidClose 1000.
    func connectListenLoopProductionForTests() async throws {
        try await connectIfNeeded()
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

    /// Live send path. A zombie URLSession task that never opened is false.
    var listenLoopSocketHasSendTask: Bool { client.hasSendTask }

    /// Phone sendRaw: `opened && task`, not the testSendSink paper.
    var listenLoopHasProductionSendTask: Bool { client.hasProductionSendTask }

    var listenLoopProductionWebSocketTask: URLSessionWebSocketTask? {
        client.productionWebSocketTaskForTests
    }

    var listenLoopUsesTestSendSink: Bool { client.usesTestSendSinkForTests }

    func setListenLoopRealtimeURLOverrideForTests(_ url: URL?) {
        client.setRealtimeURLOverrideForTests(url)
    }

    var listenLoopDeliveredSendCount: Int { client.deliveredSendCount }

    var listenLoopDeliveredAudioPCM: [Data] { client.deliveredAppendPCM }

    var listenLoopDeliveredSendTypes: [String] { client.deliveredSendTypes }

    var listenLoopDeliveredSends: [String] { client.deliveredSends }

    /// Tiny hook. Not a mock Grok client. Flushes the dead-socket queue.
    func attachListenLoopSendTaskForTests() {
        client.attachTestSendTask()
    }

    /// Real DidOpen + session.updated. Not attach-send-task flush.
    /// 19c1b33 flushed appends on notifyOpen before session.update.
    func simulateListenLoopSocketDidOpenThenSessionReady() {
        client.attachTestSendRecorder()
        client.notifyOpen()
        grokWebSocketDidOpen()
        grokWebSocketDidReceive(json: ["type": "session.updated"], type: "session.updated")
    }

    /// Quiet-close after a flushed command. Not a second listen loop.
    func waitUntilListenLoopQueuedTurnClosed() async {
        for _ in 0..<160 {
            if listenLoopDeliveredSendTypes.contains("input_audio_buffer.commit") {
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Live Grok (or a protocol-complete peer) created a response.
    var listenLoopResponseCreatedCount: Int { responseCreatedCountForTests }

    /// First barge-in already dropped local. claimLocal must not own
    /// that turn — Grok's interrupt answer schedules on the player.
    var listenLoopBargeConsumed: Bool { bargeConsumed }

    var listenLoopLastCreatedResponseID: String? { lastCreatedResponseID }

    var listenLoopLastScheduledResponseID: String? { lastScheduledResponseID }

    var listenLoopLastCancelResponseID: String? { lastBargeCancelSentID }

    var listenLoopCancelledResponseID: String? { cancelledPlaybackResponseID }

    var listenLoopRejectedCancelledDeltaCount: Int { rejectedCancelledDeltaCount }

    var listenLoopAudioDeltaCount: Int { audioDeltaCount }

    /// Same `output_audio.delta` path live Grok uses. Leftover first-answer
    /// PCM after barge must go through `shouldScheduleAfterBarge`.
    func playListenLoopOutputAudioDeltaForTests(responseID: String, pcm: Data) {
        grokWebSocketDidReceive(
            json: [
                "type": "response.output_audio.delta",
                "response_id": responseID,
                "delta": pcm.base64EncodedString()
            ],
            type: "response.output_audio.delta"
        )
    }

    var listenLoopBargeProof: String {
        GrokRealtime.bargeProofLine(
            createdID: lastCreatedResponseID,
            scheduledID: lastScheduledResponseID,
            cancelID: lastBargeCancelSentID,
            audioDeltaCount: audioDeltaCount
        )
    }

    func waitUntilListenLoopHasProductionSendTask(timeoutSeconds: Double = 12) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            if listenLoopHasProductionSendTask { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return listenLoopHasProductionSendTask
    }

    func waitUntilListenLoopResponseCreated(after: Int, timeoutSeconds: Double = 45) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            if listenLoopResponseCreatedCount > after { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return listenLoopResponseCreatedCount > after
    }

    var listenLoopResponseDoneCount: Int { responseDoneCountForTests }

    func waitUntilListenLoopResponseDone(after: Int, timeoutSeconds: Double = 45) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            if listenLoopResponseDoneCount > after { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return listenLoopResponseDoneCount > after
    }

    /// Live Grok (or write→player) scheduled buffers on the one engine.
    /// `isPlayerPlaying` is true from `audio.start` — pending must rise.
    func waitUntilListenLoopPendingPlayback(
        notScheduled cancelledID: String? = nil,
        timeoutSeconds: Double = 45
    ) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            if audio.hasPendingPlayback {
                if let cancelled = GrokRealtime.nonemptyID(cancelledID),
                   lastScheduledResponseID == cancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        if audio.hasPendingPlayback,
           let cancelled = GrokRealtime.nonemptyID(cancelledID),
           lastScheduledResponseID == cancelled {
            return false
        }
        return audio.hasPendingPlayback
    }

    /// Same one-engine player `speak()` drains. Not `synthesizer.speak()`.
    func waitUntilListenLoopPlaybackDrained(timeoutSeconds: Double = 45) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while audio.hasPendingPlayback, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return !audio.hasPendingPlayback
    }

    /// After a zero-notification yank the first feed is deaf.
    /// Put the HAL tap back here — no 400ms Task, no config change.
    /// `claimLocal` / leftover barge must not own this repair.
    func waitUntilListenLoopDelayedSilentTapRepair() async {
        audio.reinstallTapIfYankedWhileRunning()
    }
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
