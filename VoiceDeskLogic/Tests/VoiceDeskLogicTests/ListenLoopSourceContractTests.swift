import XCTest
@testable import VoiceDeskLogic

/// 18d5878 went green on transcript injects and still failed. Hear proof
/// is write→playPCM16 on the live player, not leftover-echo or rearm.
final class ListenLoopSourceContractTests: XCTestCase {
    func testClientVoiceSpeechWritesPCMToPlayerNotSpeak() throws {
        let tts = try XCTUnwrap(repoFile("VoiceDesk/Voice/ClientVoiceSpeech.swift"))
        XCTAssertTrue(tts.contains("synthesizer.write"), tts)
        XCTAssertTrue(tts.contains("playPCM16") || tts.contains("pcm16LE"), tts)
        XCTAssertFalse(tts.contains("synthesizer.speak("), tts)
        XCTAssertFalse(tts.contains("synthesizer.speak(utterance)"), tts)
        XCTAssertFalse(tts.contains("AVSpeechSynthesizerDelegate"), tts)
    }

    func testSpeakPathDoesNotEchoGateRearmOrStartAfterTTS() throws {
        let speak = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        XCTAssertTrue(speak.contains("ClientVoiceSpeech.shared.speak"), speak)
        XCTAssertTrue(speak.contains("playPCM16"), speak)
        XCTAssertFalse(speak.contains("echoGate"), speak)
        XCTAssertFalse(speak.contains("keepListeningAfterClientTTS"), speak)
        XCTAssertFalse(speak.contains("EchoBargeIn"), speak)
        XCTAssertFalse(speak.contains("resumeCaptureAfterDeskSpeak"), speak)
        XCTAssertFalse(speak.contains("armListenIfSessionLive(reason: \"client tts\")"), speak)
        XCTAssertFalse(speak.contains("EarlyFinalHold"), speak)
        let speakFn = speakSlice(speak, from: "func speak(_ text: String) async {", to: "func sendTextTurn")
        XCTAssertFalse(speakFn.contains("echoGate.beginSpeaking"), speakFn)
        XCTAssertTrue(speakFn.contains("waitUntilPlaybackDrained"), speakFn)
        XCTAssertTrue(speakFn.contains("returnToListenAfterDeskTTS"), speakFn)
        XCTAssertTrue(speak.contains("afterClientTTSFinished"), speak)
        XCTAssertTrue(speak.contains("applyLeftoverGrokDuringClientTTS"), speak)
        XCTAssertTrue(speak.contains("clientTTSInFlight"), speak)
        if let writeAt = speakFn.range(of: "ClientVoiceSpeech.shared.speak") {
            let afterWrite = String(speakFn[writeAt.upperBound...])
            XCTAssertTrue(afterWrite.contains("returnToListenAfterDeskTTS"), afterWrite)
            XCTAssertFalse(afterWrite.contains("clientTTSInFlight = false"), afterWrite)
            XCTAssertFalse(afterWrite.contains("startAudioIfNeeded"), afterWrite)
            XCTAssertFalse(afterWrite.contains("audio.start"), afterWrite)
            XCTAssertFalse(afterWrite.contains("keepListeningAfterClientTTS"), afterWrite)
            XCTAssertFalse(afterWrite.contains("armListenIfSessionLive"), afterWrite)
        } else {
            XCTFail("speak() must call ClientVoiceSpeech.shared.speak")
        }
    }

    func testInterruptPlaybackDoesNotRemoveTap() throws {
        let engine = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceAudioEngine.swift"))
        XCTAssertTrue(engine.contains("func interruptPlayback()"), engine)
        XCTAssertFalse(engine.contains("func resumeCapture"), engine)
        XCTAssertFalse(engine.contains("func rearmTap"), engine)
        let interrupt = engineSlice(engine, from: "func interruptPlayback() {", to: "func feedTapPCM16")
        XCTAssertFalse(interrupt.contains("removeTap"), interrupt)
        XCTAssertTrue(interrupt.contains("playerNode?.play()"), interrupt)
    }

    func testLiveIngressDoesNotLeftoverMatch() throws {
        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        XCTAssertFalse(app.contains("echoGate"), app)
        XCTAssertFalse(app.contains("EchoBargeIn.acceptedUserTranscript"), app)
        XCTAssertFalse(app.contains("EarlyFinalHold"), app)
        XCTAssertFalse(app.contains("preemptGrokIfDeskTurn"), app)
        XCTAssertFalse(app.contains("dropLeadingLeftoverStem"), app)
        XCTAssertTrue(app.contains("ListenInterrupt.isCommand"), app)
        XCTAssertTrue(app.contains("voice.hasPendingPlayback"), app)
        XCTAssertTrue(app.contains("shouldTakeLiveTurn"), app)
        XCTAssertTrue(app.contains("voice.interruptResponse()"), app)
        XCTAssertTrue(app.contains("handleLiveUser(event.text, itemID: event.itemID)"), app)
        XCTAssertFalse(app.contains("speakStarted"), app)
        XCTAssertFalse(app.contains("stayIdle"), app)
        XCTAssertFalse(app.contains("resumeCapture"), app)
        XCTAssertFalse(app.contains("applyLeftoverGrokDuringClientTTS"), app)
        XCTAssertFalse(app.contains("afterClientTTSFinished"), app)
        XCTAssertFalse(app.contains("armListenIfSessionLive"), app)
        let live = speakSlice(app, from: "private func handleLiveTranscript", to: "private func handleLiveUser")
        XCTAssertTrue(live.contains("guard event.isFinal else { return }"), live)
        XCTAssertFalse(live.contains("voice.interruptResponse()"), live)
        XCTAssertTrue(live.contains("shouldTakeLiveTurn"), live)
    }

    func testFakeLiveInterruptCountOnlyTicksWhenPlaybackIsPending() throws {
        let tests = try XCTUnwrap(repoFile("VoiceDeskTests/AppModelTests.swift"))
        let interrupt = speakSlice(tests, from: "func interruptResponse() {", to: "func suppressAssistantOutput")
        XCTAssertTrue(interrupt.contains("guard hasPendingPlayback else { return }"), interrupt)
        XCTAssertTrue(interrupt.contains("interruptCount += 1"), interrupt)
        let speak = speakSlice(tests, from: "func speak(_ text: String) async {", to: "func sendTextTurn")
        XCTAssertTrue(speak.contains("applyLeftoverGrokDuringClientTTS"), speak)
        XCTAssertTrue(speak.contains("afterClientTTSFinished"), speak)
        XCTAssertFalse(speak.contains("afterDeskSpeak"), speak)
        XCTAssertTrue(tests.contains("testVersionThenGlanceWritePlayerStayLiveThirdCommandIsATurn"), tests)
    }

    func testSpeechStartedAndTranscriptDoNotCancelPlayback() throws {
        let speak = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        XCTAssertFalse(speak.contains("applyBargeInIfNeeded"), speak)
        XCTAssertTrue(speak.contains("shouldApplyGrokSpeakStarted"), speak)
        let speech = speakSlice(speak, from: "case .speechStarted:", to: "case .speechStopped:")
        XCTAssertFalse(speech.contains("interruptAssistant"), speech)
        XCTAssertFalse(speech.contains("interruptPlayback"), speech)
        XCTAssertFalse(speech.contains("ClientVoiceSpeech.shared.stop"), speech)
        let transcript = speakSlice(speak, from: "case .userTranscript", to: "case .responseCreated")
        XCTAssertFalse(transcript.contains("interruptPlayback"), transcript)
        XCTAssertFalse(transcript.contains("ClientVoiceSpeech.shared.stop"), transcript)
        XCTAssertTrue(transcript.contains("eventHandler?(.userTranscript"), transcript)
    }

    func testSimGateCancelsPlaybackOnlyOnCommand() throws {
        let sim = try XCTUnwrap(repoFile("VoiceDeskTests/GrokVoiceAudioEngineListenLoopTests.swift"))
        XCTAssertTrue(sim.contains("ListenInterrupt.isCommand"), sim)
        XCTAssertTrue(sim.contains("must not interruptPlayback"), sim)
        XCTAssertTrue(sim.contains("feedTapPCM16"), sim)
        XCTAssertFalse(sim.contains("synthesizer.speak("), sim)
        XCTAssertTrue(sim.contains("FirstHearTapLoop.accept"), sim)
        XCTAssertTrue(sim.contains("listen.onTap"), sim)
        XCTAssertFalse(sim.contains("func acceptIfTurn"), sim)
        XCTAssertTrue(sim.contains("waitUntilDrained"), sim)
        XCTAssertTrue(sim.contains("spokenListAck"), sim)
        XCTAssertTrue(sim.contains("turns.last"), sim)
        XCTAssertTrue(sim.contains("turns.count, 3"), sim)
        XCTAssertTrue(sim.contains("silentTapWhileEngineRunning"), sim)
        XCTAssertTrue(sim.contains("firesAfterDrain"), sim)
        XCTAssertTrue(sim.contains("simulateSystemTapDetachLeavingEngineRunning"), sim)
        XCTAssertTrue(sim.contains("interruptionNotification"), sim)
        XCTAssertTrue(sim.contains("postInterruption(.began)"), sim)
        XCTAssertTrue(sim.contains("postInterruption(.ended)"), sim)
        XCTAssertTrue(sim.contains("categoryChange"), sim)
        XCTAssertTrue(sim.contains("engine.startCount, 1"), sim)
        XCTAssertTrue(sim.contains("fe1ffc8"), sim)
        XCTAssertTrue(sim.contains("fa72e1c"), sim)
        XCTAssertTrue(sim.contains("18d5878"), sim)
        XCTAssertTrue(sim.contains("415c955"), sim)
        XCTAssertTrue(sim.contains("testTapStaysLiveAcrossPlayerPlaybackBargeInAndWriteTTS"), sim)
        XCTAssertTrue(sim.contains("testIOSDetachAfterTTSDrainSilentTapWhileRunningThenSameEngineReinstall"), sim)
        XCTAssertTrue(sim.contains("testProductPathAfterTTSDrainStayLiveThirdCommandIsATurn"), sim)
        XCTAssertTrue(sim.contains("returnToListenAfterDeskTTS"), sim)
        XCTAssertTrue(sim.contains("plantSpeakStarted"), sim)
        let product = speakSlice(
            sim,
            from: "func testProductPathAfterTTSDrainStayLiveThirdCommandIsATurn",
            to: "func testIOSDetachAfterTTSDrainSilentTapWhileRunningThenSameEngineReinstall"
        )
        XCTAssertFalse(product.contains("simulateSystemTapDetachLeavingEngineRunning"), product)
        XCTAssertTrue(product.contains("stayIdle"), product)
        XCTAssertTrue(product.contains("returnToListenAfterDeskTTS"), product)
        XCTAssertTrue(sim.contains("afterClientTTSFinished"), sim)
        XCTAssertFalse(sim.contains("keepListeningAfterClientTTS"), sim)
        XCTAssertFalse(sim.contains("resumeCapture"), sim)
        XCTAssertFalse(sim.contains("rearmTap"), sim)
        XCTAssertFalse(sim.contains("synthesizer.speak("), sim)
    }

    func testFirstHearTapLoopEncodes415c955ClassDetach() throws {
        let loop = try XCTUnwrap(repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/FirstHearTapLoop.swift"))
        let loopTests = try XCTUnwrap(repoFile("VoiceDeskLogic/Tests/VoiceDeskLogicTests/FirstHearTapLoopTests.swift"))
        XCTAssertTrue(loopTests.contains("testFe1ffc8Fa72e1c18d5878415c955DetachWhileRunningStartNoOpsDropsThird"), loopTests)
        XCTAssertTrue(loop.contains("fe1ffc8Fa72e1c18d5878415c955DetachWhileRunningStartNoOpsDropsThird"), loop)
        XCTAssertTrue(loop.contains("fe1ffc8Fa72e1c18d5878415c955Close1000AfterTTS"), loop)
        XCTAssertTrue(loop.contains("fe1ffc8Fa72e1c18d5878415c955Close1000AfterTTSStayIdleDropsThird"), loop)
        XCTAssertTrue(loop.contains("close1000AfterTTSStayLiveThenThird"), loop)
        XCTAssertTrue(loop.contains("versionThenGlanceWritePlayerThenThird"), loop)
        XCTAssertTrue(loop.contains("applyLeftoverGrokDuringClientTTS"), loop)
        XCTAssertTrue(loopTests.contains("testFe1ffc8Fa72e1c18d5878415c955Close1000AfterTTSMustNotStayIdle"), loopTests)
        XCTAssertTrue(loop.contains("detachWhileRunningThenReinstallSameTap"), loop)
        XCTAssertTrue(loop.contains("startAudioIfNeededWouldStart"), loop)
        XCTAssertTrue(loop.contains("415c955"), loop)
        XCTAssertTrue(loop.contains("18d5878"), loop)
        XCTAssertTrue(loop.contains("fa72e1c"), loop)
        XCTAssertTrue(loop.contains("fe1ffc8"), loop)
        let service = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        let start = speakSlice(service, from: "private func startAudioIfNeeded() {", to: "private func armListenIfSessionLive")
        XCTAssertTrue(start.contains("!audio.isRunning"), start)
        XCTAssertTrue(service.contains("returnToListenAfterDeskTTS"), service)
        XCTAssertTrue(service.contains("clientTTSSpeaking: audio.hasPendingPlayback || clientTTSInFlight"), service)
        XCTAssertTrue(service.contains("shouldApplyGrokTurnFinished"), service)
        XCTAssertTrue(service.contains("clientTTSInFlight: clientTTSInFlight"), service)
    }

    func testEngineDoesNotTreatIsRunningAsTapLiveness() throws {
        let engine = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceAudioEngine.swift"))
        XCTAssertTrue(engine.contains("AVAudioConverter"), engine)
        XCTAssertTrue(engine.contains("generation == stopped"), engine)
        XCTAssertTrue(engine.contains("reinstallTap"), engine)
        XCTAssertTrue(engine.contains("simulateSystemTapDetachLeavingEngineRunning"), engine)
        XCTAssertTrue(engine.contains("interruptionNotification"), engine)
        XCTAssertTrue(engine.contains("mediaServicesWereResetNotification"), engine)
        let detach = engineSlice(
            engine,
            from: "func simulateSystemTapDetachLeavingEngineRunning()",
            to: "func playAudioDelta"
        )
        XCTAssertTrue(detach.contains("removeTap"), detach)
        XCTAssertTrue(detach.contains("tapInstalled = false"), detach)
        XCTAssertFalse(detach.contains("startCount +="), detach)
        XCTAssertFalse(detach.contains("engine.stop"), detach)
        XCTAssertFalse(engine.contains(".mixWithOthers"), engine)
        XCTAssertFalse(engine.contains("MicLivenessMonitor"), engine)
        XCTAssertFalse(engine.contains("MicRepairBackoff"), engine)
        XCTAssertFalse(engine.contains("func rearmTap"), engine)
        let service = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        XCTAssertFalse(service.contains("watchdog"), service)
        XCTAssertFalse(service.contains("armListenIfSessionLive(reason: \"client tts\")"), service)
        let policy = try XCTUnwrap(repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/ListenResumePolicy.swift"))
        XCTAssertFalse(policy.contains("case resumeCapture"), policy)
        XCTAssertFalse(policy.contains("func afterClientTTS("), policy)
        XCTAssertFalse(policy.contains("shouldArmListenAfterClientTTS"), policy)
        XCTAssertFalse(policy.contains("isCaptureArmed"), policy)
        XCTAssertFalse(policy.contains("leftover-echo"), policy)
        XCTAssertFalse(policy.contains("droppedTranscript"), policy)
        let fixture = try XCTUnwrap(repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/DeskSpeakListenResume.swift"))
        XCTAssertFalse(fixture.contains("EchoTranscriptGate"), fixture)
        XCTAssertFalse(fixture.contains("EchoBargeIn"), fixture)
        XCTAssertTrue(fixture.contains("ListenInterrupt.isCommand"), fixture)
    }

    private func speakSlice(_ source: String, from: String, to: String) -> String {
        guard let start = source.range(of: from), let end = source.range(of: to, range: start.upperBound..<source.endIndex) else {
            return source
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func engineSlice(_ source: String, from: String, to: String) -> String {
        speakSlice(source, from: from, to: to)
    }

    private func repoFile(_ relative: String) -> String? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try? String(contentsOf: candidate, encoding: .utf8)
            }
        }
        return nil
    }
}
