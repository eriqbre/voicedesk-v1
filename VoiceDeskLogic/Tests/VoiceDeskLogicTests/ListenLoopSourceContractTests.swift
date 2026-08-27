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
        XCTAssertTrue(tts.contains("usesApplicationAudioSession = false"), tts)
        XCTAssertFalse(tts.contains("usesApplicationAudioSession = true"), tts)
        XCTAssertFalse(tts.contains("setCategory"), tts)
        XCTAssertFalse(tts.contains("setActive"), tts)
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
        let speakFn = speakSlice(speak, from: "func speak(_ text: String) async {", to: "private func returnToListenAfterDeskTTS")
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
        let afterDrain = speakSlice(
            speak,
            from: "private func returnToListenAfterDeskTTS()",
            to: "private func waitUntilPlaybackDrained"
        )
        XCTAssertTrue(
            afterDrain.contains("clientTTSInFlight = false"),
            "stayLive after drain is armed+running, not a stuck TTS flag"
        )
        XCTAssertFalse(
            afterDrain.contains("disconnect"),
            "desk TTS is write→player — drain must not kill the live socket"
        )
        XCTAssertFalse(
            afterDrain.contains("dropOutbound"),
            "drain must not empty the live send path"
        )
        XCTAssertFalse(
            afterDrain.contains("sessionReady"),
            "clearing sessionReady queues the next command forever"
        )
        XCTAssertFalse(afterDrain.contains("quietCommitMaxPostponeMs"), afterDrain)
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
        XCTAssertFalse(tests.contains("simulateHALTapYankLeavingInstalledFlagTrue"), tests)
        XCTAssertFalse(tests.contains("AVAudioEngineConfigurationChange"), tests)
        XCTAssertFalse(tests.contains("GrokVoiceService("), tests)
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
        XCTAssertTrue(
            sim.contains("testDetachAfterTTSDrainSilentTapWhileRunningReinstallsWithoutInterruption"),
            sim
        )
        XCTAssertTrue(
            sim.contains("testFlagLiesAfterTTSDrainSilentTapWhileRunningReinstallsSameTap"),
            sim
        )
        XCTAssertTrue(
            sim.contains("testDelayedYankAfterReturnToListenConfigChangeReinstallsSameTap"),
            sim
        )
        XCTAssertFalse(sim.contains("AppModel("), sim)
        XCTAssertFalse(sim.contains("GrokVoiceService("), sim)
        let noInterrupt = speakSlice(
            sim,
            from: "func testDetachAfterTTSDrainSilentTapWhileRunningReinstallsWithoutInterruption",
            to: "func testFlagLiesAfterTTSDrainSilentTapWhileRunningReinstallsSameTap"
        )
        XCTAssertFalse(noInterrupt.contains("postInterruption"), noInterrupt)
        XCTAssertTrue(noInterrupt.contains("reinstallTapIfSilentWhileRunning"), noInterrupt)
        XCTAssertTrue(noInterrupt.contains("simulateSystemTapDetachLeavingEngineRunning"), noInterrupt)
        XCTAssertTrue(noInterrupt.contains("415c955"), noInterrupt)
        let flagLies = speakSlice(
            sim,
            from: "func testFlagLiesAfterTTSDrainSilentTapWhileRunningReinstallsSameTap",
            to: "func testDelayedYankAfterReturnToListenConfigChangeReinstallsSameTap"
        )
        XCTAssertFalse(flagLies.contains("postInterruption"), flagLies)
        XCTAssertTrue(flagLies.contains("simulateHALTapYankLeavingInstalledFlagTrue"), flagLies)
        XCTAssertTrue(flagLies.contains("bf0af19ShouldReinstallTapIfSilentWhileRunning"), flagLies)
        XCTAssertTrue(flagLies.contains("reinstallTapIfSilentWhileRunning"), flagLies)
        XCTAssertTrue(flagLies.contains("returnToListenAfterDeskTTS"), flagLies)
        let delayedYank = speakSlice(
            sim,
            from: "func testDelayedYankAfterReturnToListenConfigChangeReinstallsSameTap",
            to: "private func waitUntilDrained"
        )
        XCTAssertFalse(delayedYank.contains("postInterruption"), delayedYank)
        XCTAssertTrue(delayedYank.contains("simulateHALTapYankLeavingInstalledFlagTrue"), delayedYank)
        XCTAssertTrue(delayedYank.contains("returnToListenAfterDeskTTS"), delayedYank)
        XCTAssertTrue(delayedYank.contains("postEngineConfigurationChange"), delayedYank)
        XCTAssertTrue(sim.contains("AVAudioEngineConfigurationChange"), sim)
        let configPost = speakSlice(
            sim,
            from: "private func postEngineConfigurationChange()",
            to: "private func settleLifecycle()"
        )
        XCTAssertTrue(configPost.contains("AVAudioEngineConfigurationChange"), configPost)
        XCTAssertFalse(configPost.contains("postInterruption"), configPost)
        if let listenAt = delayedYank.range(of: "returnToListenAfterDeskTTS"),
           let yankAt = delayedYank.range(of: "simulateHALTapYankLeavingInstalledFlagTrue") {
            XCTAssertLessThan(
                listenAt.lowerBound,
                yankAt.lowerBound,
                "573f654 drain-time repair must run before the delayed yank"
            )
        } else {
            XCTFail("delayed-yank gate must returnToListen then yank")
        }
        if let repairAt = delayedYank.range(of: "reinstallTapIfSilentWhileRunning"),
           let yankAt = delayedYank.range(of: "simulateHALTapYankLeavingInstalledFlagTrue") {
            XCTAssertLessThan(
                repairAt.lowerBound,
                yankAt.lowerBound,
                "drain-only reinstall must not run after the delayed yank"
            )
        } else {
            XCTFail("delayed-yank gate must allow 573f654 repair before the yank")
        }
        XCTAssertEqual(
            delayedYank.components(separatedBy: "reinstallTapIfSilentWhileRunning").count,
            2,
            "only the drain-time 573f654 repair; config change is the delayed-yank recovery"
        )
        if let yankAt = delayedYank.range(of: "simulateHALTapYankLeavingInstalledFlagTrue"),
           let configAt = delayedYank.range(of: "postEngineConfigurationChange") {
            XCTAssertLessThan(
                yankAt.lowerBound,
                configAt.lowerBound,
                "configuration change must arrive after the delayed yank"
            )
        } else {
            XCTFail("delayed-yank gate must post configuration change after the yank")
        }
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
        XCTAssertTrue(loop.contains("shouldReinstallTapIfSilentWhileRunning"), loop)
        XCTAssertTrue(loop.contains("bf0af19ShouldReinstallTapIfSilentWhileRunning"), loop)
        XCTAssertTrue(loop.contains("fe1ffc8Fa72e1c18d5878415c955DetachAfterTTSDrainNoInterruptionDropsThird"), loop)
        XCTAssertTrue(loop.contains("detachAfterTTSDrainNoInterruptionThenReinstallSameTap"), loop)
        XCTAssertTrue(loop.contains("bf0af19415c955FlagLiesAfterTTSDrainDropsThird"), loop)
        XCTAssertTrue(loop.contains("flagLiesAfterTTSDrainThenReinstallSameTap"), loop)
        XCTAssertTrue(loop.contains("drainOnly573f654DelayedYankAfterReturnToListenDropsThird"), loop)
        XCTAssertTrue(loop.contains("delayedYankAfterReturnToListenThenConfigChangeReinstallsSameTap"), loop)
        XCTAssertTrue(
            loopTests.contains("testDrainOnly573f654DelayedYankAfterReturnToListenDropsThird"),
            loopTests
        )
        XCTAssertTrue(
            loopTests.contains("testDelayedYankAfterReturnToListenThenConfigChangeLandsThird"),
            loopTests
        )
        XCTAssertTrue(
            loopTests.contains("testFe1ffc8Fa72e1c18d5878415c955DetachAfterTTSDrainNoInterruptionDropsThird"),
            loopTests
        )
        XCTAssertTrue(loopTests.contains("testBf0af19415c955FlagLiesAfterTTSDrainDropsThird"), loopTests)
        XCTAssertTrue(loop.contains("startAudioIfNeededWouldStart"), loop)
        XCTAssertTrue(loop.contains("415c955"), loop)
        XCTAssertTrue(loop.contains("18d5878"), loop)
        XCTAssertTrue(loop.contains("fa72e1c"), loop)
        XCTAssertTrue(loop.contains("fe1ffc8"), loop)
        let service = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        let start = speakSlice(service, from: "private func startAudioIfNeeded() {", to: "private func armListenIfSessionLive")
        XCTAssertTrue(start.contains("!audio.isRunning"), start)
        XCTAssertFalse(start.contains("self?.onMicFrame"), start)
        XCTAssertTrue(start.contains("frames.emit"), start)
        XCTAssertTrue(service.contains("returnToListenAfterDeskTTS"), service)
        XCTAssertTrue(service.contains("reinstallTapIfSilentWhileRunning"), service)
        XCTAssertTrue(service.contains("var listenLoopEngine"), service)
        XCTAssertTrue(service.contains("onMicFrame"), service)
        XCTAssertTrue(service.contains("func startListenLoopAudioForTests()"), service)
        XCTAssertTrue(service.contains("startAudioIfNeeded()"), service)
        XCTAssertTrue(service.contains("ListenLoopMicFrames"), service)
        XCTAssertFalse(service.contains("MicLivenessMonitor"), service)
        XCTAssertFalse(service.contains("watchdog"), service)
        XCTAssertTrue(service.contains("clientTTSSpeaking: audio.hasPendingPlayback || clientTTSInFlight"), service)
        XCTAssertTrue(service.contains("shouldApplyGrokTurnFinished"), service)
        XCTAssertTrue(service.contains("clientTTSInFlight: clientTTSInFlight"), service)
        XCTAssertTrue(service.contains("func simulateListenLoopSocketClose1000()"), service)
        XCTAssertTrue(service.contains("grokWebSocketDidClose(code: 1000, reason: nil)"), service)
        XCTAssertTrue(service.contains("listenLoopRecoverCount"), service)
        XCTAssertTrue(service.contains("listenLoopSocketHasSendTask"), service)
        XCTAssertTrue(service.contains("func attachListenLoopSendTaskForTests()"), service)
        XCTAssertTrue(service.contains("listenLoopDeliveredAudioPCM"), service)
        XCTAssertTrue(service.contains("listenLoopDeliveredSendTypes"), service)
        XCTAssertTrue(service.contains("listenLoopDeliveredSends"), service)
        XCTAssertTrue(service.contains("func simulateListenLoopSocketDidOpenThenSessionReady()"), service)
        XCTAssertTrue(service.contains("func setListenLoopRealtimeURLOverrideForTests"), service)
        XCTAssertTrue(service.contains("listenLoopProductionWebSocketTask"), service)
        XCTAssertTrue(service.contains("listenLoopUsesTestSendSink"), service)
        XCTAssertTrue(service.contains("listenLoopHasProductionSendTask"), service)
        XCTAssertTrue(service.contains("func waitUntilListenLoopQueuedTurnClosed()"), service)
        XCTAssertTrue(service.contains("listenLoopResponseCreatedCount"), service)
        XCTAssertTrue(service.contains("func waitUntilListenLoopResponseCreated"), service)
        XCTAssertTrue(service.contains("func waitUntilListenLoopHasProductionSendTask"), service)
        let waitUntil = speakSlice(
            service,
            from: "func waitUntilListenLoopQueuedTurnClosed() async {",
            to: "/// Same-thread tap observer"
        )
        XCTAssertFalse(
            waitUntil.contains("for _ in 0..<20"),
            "3c7524b waitUntil was 400ms — shorter than a 1–2s grace"
        )
        XCTAssertTrue(service.contains("dropOutbound"), service)
        XCTAssertTrue(service.contains("markSessionReadyAndFlush"), service)
        let realtime = try XCTUnwrap(repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/GrokRealtime.swift"))
        XCTAssertTrue(realtime.contains("func commitAudioBufferObject()"), realtime)
        XCTAssertTrue(realtime.contains("input_audio_buffer.commit"), realtime)
        XCTAssertTrue(realtime.contains("func createResponse(inSessionUpdate"), realtime)
        let updated = speakSlice(service, from: "case .sessionUpdated:", to: "case .speechStarted:")
        XCTAssertTrue(updated.contains("markSessionReadyAndFlush"), updated)
        let didOpenService = speakSlice(service, from: "func grokWebSocketDidOpen()", to: "func grokWebSocketDidClose")
        XCTAssertTrue(didOpenService.contains("sendListenResumeSessionUpdate"), didOpenService)
        XCTAssertFalse(
            didOpenService.contains("sendSessionUpdate"),
            "e89d443 DidOpen sent sessionUpdateObject — create_response omitted, Grok never answers"
        )
        XCTAssertFalse(
            didOpenService.contains("markSessionReadyAndFlush"),
            "DidOpen is not session-ready — 19c1b33 flushed too early"
        )
        let created = speakSlice(service, from: "case .sessionCreated:", to: "case .sessionUpdated:")
        XCTAssertFalse(
            created.contains("sendSessionUpdate"),
            "a second no-flag session.update wipes DidOpen create_response:true"
        )
        XCTAssertFalse(created.contains("sendListenResumeSessionUpdate"), created)
        let hook = speakSlice(
            service,
            from: "func simulateListenLoopSocketDidOpenThenSessionReady()",
            to: "func waitUntilListenLoopQueuedTurnClosed()"
        )
        XCTAssertTrue(hook.contains("grokWebSocketDidOpen"), hook)
        XCTAssertFalse(
            hook.contains("sendListenResumeSessionUpdate"),
            "the hook must not paper-green e89d443 — DidOpen sends the one session.update"
        )
        let client = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoice.swift"))
        XCTAssertTrue(client.contains("outboundQueue"), client)
        XCTAssertTrue(client.contains("func attachTestSendTask()"), client)
        XCTAssertTrue(client.contains("func attachTestSendRecorder()"), client)
        XCTAssertTrue(client.contains("realtimeURLOverrideForTests"), client)
        XCTAssertTrue(client.contains("func setRealtimeURLOverrideForTests"), client)
        XCTAssertTrue(client.contains("hasProductionSendTask"), client)
        let connectFn = speakSlice(client, from: "func connect(apiKey:", to: "func disconnect()")
        XCTAssertTrue(connectFn.contains("realtimeURLOverrideForTests"), connectFn)
        XCTAssertTrue(connectFn.contains("webSocketTask"), connectFn)
        XCTAssertTrue(client.contains("func markSessionReadyAndFlush()"), client)
        XCTAssertTrue(client.contains("func dropOutbound()"), client)
        let flush = speakSlice(client, from: "func markSessionReadyAndFlush()", to: "private func scheduleQuietCommit")
        XCTAssertTrue(flush.contains("pendingQuietCommit"), flush)
        XCTAssertTrue(flush.contains("isAudioAppend"), flush)
        XCTAssertFalse(
            flush.contains("sendJSON(GrokRealtime.commitAudioBufferObject())"),
            "6b5f0ee committed on flush — mid-utterance if they are still talking"
        )
        XCTAssertTrue(client.contains("func commitIfStillQuiet"), client)
        XCTAssertTrue(client.contains("commitAudioBufferObject"), client)
        let sendRaw = speakSlice(client, from: "func sendRaw(_ string: String) {", to: "func attachTestSendTask()")
        XCTAssertTrue(sendRaw.contains("sessionReady"), sendRaw)
        XCTAssertTrue(sendRaw.contains("isAudioAppend"), sendRaw)
        XCTAssertFalse(sendRaw.contains("task?.send"), sendRaw)
        XCTAssertFalse(
            sendRaw.contains("TapSpeechEnergy"),
            "2679792 postponed quiet-commit on RMS — radio never closed the turn"
        )
        XCTAssertFalse(
            sendRaw.contains("QueuedTurnClose"),
            "6264a07 QueuedTurnClose was a 120–220 Hz sine detector, not speech"
        )
        XCTAssertFalse(sendRaw.contains("shouldPostpone"), sendRaw)
        XCTAssertFalse(sendRaw.contains("zeroCrossing"), sendRaw)
        XCTAssertFalse(sendRaw.contains("commandBandHz"), sendRaw)
        XCTAssertFalse(sendRaw.contains("pcmFromAppendJSON"), sendRaw)
        XCTAssertTrue(client.contains("quietCommitGeneration"), client)
        XCTAssertTrue(flush.contains("pendingQuietCommit"), flush)
        XCTAssertFalse(
            sendRaw.contains("quietCommitGeneration"),
            "one-shot close is armed at flush, not rescheduled on every live append"
        )
        XCTAssertFalse(sendRaw.contains("pendingQuietCommit"), sendRaw)
        XCTAssertFalse(sendRaw.contains("scheduleQuietCommit"), sendRaw)
        XCTAssertFalse(
            sendRaw.contains("quietCommitMaxPostponeMs"),
            "5078dff flush-clock postponed every live append until a magic ms"
        )
        XCTAssertFalse(sendRaw.contains("quietCommitArmedAt"), sendRaw)
        XCTAssertFalse(client.contains("quietCommitMaxPostponeMs"), client)
        XCTAssertFalse(client.contains("quietCommitArmedAt"), client)
        XCTAssertTrue(sendRaw.contains("isAudioAppend"), sendRaw)
        XCTAssertNil(
            repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/TapSpeechEnergy.swift"),
            "RMS quiet-commit was the wrong part"
        )
        XCTAssertNil(
            repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/QueuedTurnClose.swift"),
            "Hz-band postpone was a fixture-tone detector"
        )
        XCTAssertFalse(client.contains("TapSpeechEnergy"), client)
        XCTAssertFalse(client.contains("QueuedTurnClose"), client)
        let interrupt = try XCTUnwrap(repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/ListenInterrupt.swift"))
        XCTAssertTrue(interrupt.contains("no energy-only interrupt"), interrupt)
        XCTAssertFalse(interrupt.contains("TapSpeechEnergy"), interrupt)
        let didOpen = speakSlice(client, from: "nonisolated func notifyOpen()", to: "nonisolated func notifyClose")
        XCTAssertFalse(
            didOpen.contains("outboundQueue"),
            "19c1b33 flushed the queue on notifyOpen before session.update"
        )
        XCTAssertFalse(didOpen.contains("task?.send"), didOpen)
        XCTAssertTrue(didOpen.contains("grokWebSocketDidOpen"), didOpen)
        XCTAssertTrue(
            didOpen.contains("task != nil"),
            "paper DidOpen must not mark opened without a real URLSessionWebSocketTask"
        )
        XCTAssertFalse(
            didOpen.contains("opened = true"),
            "notifyOpen must not set opened unless a real task exists"
        )
        let didClose = speakSlice(
            service,
            from: "func grokWebSocketDidClose",
            to: "func grokWebSocketDidFail"
        )
        XCTAssertTrue(didClose.contains("recoverAfterDrop"), didClose)
        XCTAssertTrue(didClose.contains("sha415c955StayLiveAfterClose1000"), didClose)
        XCTAssertTrue(didClose.contains("liveSessionArmed"), didClose)
        XCTAssertFalse(
            didClose.contains("teardown"),
            "DidClose 1000 after desk TTS must not kill the one engine"
        )
        let policyClose = speakSlice(
            try XCTUnwrap(repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/ListenResumePolicy.swift")),
            from: "public static func afterSocketClose(",
            to: "public static func afterRealtimeTimeout"
        )
        XCTAssertTrue(policyClose.contains("liveSessionArmed"), policyClose)
        XCTAssertTrue(
            policyClose.contains("sessionShouldStayLive || liveSessionArmed"),
            "415c955 stayIdle skipped recover when listen was unarmed"
        )
        let recover = speakSlice(
            service,
            from: "private func recoverAfterDrop",
            to: "extension GrokVoiceService: LiveGrokVoiceClientDelegate"
        )
        XCTAssertTrue(recover.contains("connectAndConfigure"), recover)
        XCTAssertFalse(
            recover.contains("sendListenResumeSessionUpdate"),
            "e89d443 sent listen-resume after connectAndConfigure — after the first session.updated, often after commit"
        )
        XCTAssertFalse(
            recover.contains("interruptPlayback"),
            "socket recover is not a command and must not drop player buffers"
        )
        XCTAssertTrue(recover.contains("sessionShouldStayLive"), recover)
        XCTAssertTrue(recover.contains("audio.isRunning"), recover)
        let stayLiveClose = speakSlice(
            loop,
            from: "case .close1000AfterTTSStayLive:",
            to: "take(third)"
        )
        XCTAssertTrue(stayLiveClose.contains("clientTTSInFlight: false"), stayLiveClose)
        XCTAssertFalse(stayLiveClose.contains("clientTTSInFlight: true"), stayLiveClose)
    }

    func testEngineDoesNotTreatIsRunningAsTapLiveness() throws {
        let engine = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceAudioEngine.swift"))
        XCTAssertTrue(engine.contains("AVAudioConverter"), engine)
        XCTAssertTrue(engine.contains("generation == stopped"), engine)
        XCTAssertTrue(engine.contains("reinstallTap"), engine)
        XCTAssertTrue(engine.contains("reinstallTapIfSilentWhileRunning"), engine)
        XCTAssertTrue(engine.contains("simulateSystemTapDetachLeavingEngineRunning"), engine)
        XCTAssertTrue(engine.contains("simulateHALTapYankLeavingInstalledFlagTrue"), engine)
        XCTAssertTrue(engine.contains("AVAudioEngineConfigurationChange"), engine)
        XCTAssertTrue(engine.contains("guard tap != nil, tapInstalled"), engine)
        XCTAssertTrue(engine.contains("interruptionNotification"), engine)
        XCTAssertTrue(engine.contains("mediaServicesWereResetNotification"), engine)
        let stop = engineSlice(engine, from: "func stop() {", to: "func interruptPlayback()")
        XCTAssertTrue(stop.contains("setActive(false"), stop)
        XCTAssertTrue(stop.contains("!self.wantsCapture"), stop)
        let speak = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        let speakFn = speakSlice(speak, from: "func speak(_ text: String) async {", to: "func sendTextTurn")
        XCTAssertFalse(speakFn.contains("setCategory"), speakFn)
        XCTAssertFalse(speakFn.contains("setActive(false"), speakFn)
        XCTAssertFalse(speakFn.contains("VoiceEarcon"), speakFn)
        let tts = try XCTUnwrap(repoFile("VoiceDesk/Voice/ClientVoiceSpeech.swift"))
        XCTAssertFalse(tts.contains("setCategory"), tts)
        XCTAssertFalse(tts.contains("setActive"), tts)
        let reinstall = engineSlice(engine, from: "private func reinstallTap() {", to: "private func teardownGraph()")
        XCTAssertFalse(reinstall.contains("setCategory"), reinstall)
        XCTAssertFalse(reinstall.contains("setActive(false"), reinstall)
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

    func testLivePathDelayedYankDrivesAppModelAndGrokVoiceService() throws {
        let live = try XCTUnwrap(repoFile("VoiceDeskTests/AppModelListenLoopTests.swift"))
        XCTAssertTrue(
            live.contains("testVersionThenGlanceLivePathDelayedYankConfigChangeThirdCommandIsATurn"),
            live
        )
        XCTAssertTrue(
            live.contains("testVersionThenGlanceWritePlayerDoesNotFlickerAudioSession"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopTalkAnswerTalkAgainWithoutRepeat"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopAfterDeskTTSWithoutSocketCloseNextCommandIsATurn"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000AfterDrainNextCommandIsATurn"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000StayLiveFalseIdleAfterDeskTTSRecoversNextCommand"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000StayLiveFalseIdleAfterDeskTTSGrokCreatesResponse"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000DeadSocketWindowSendsQueuedCommand"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000SessionReadyFlushSendsQueuedCommand"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000FlushClosesQueuedTurn"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000StillTalkingDoesNotCommitMidUtterance"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000SilenceTapStillClosesQueuedTurn"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000AmbientTapStillClosesQueuedTurn"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000QueuedCommandRequestsResponse"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000StillTalkingLongerThanQuietCommitDoesNotTruncate"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000RealSpeechStillTalkingDoesNotTruncate"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000RealSpeechLongerThanMaxPostponeDoesNotTruncate"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000DelayedCommandAfterRecoverIsNotTruncated"),
            live
        )
        XCTAssertTrue(
            live.contains("testLiveConversationLoopDidClose1000ThinkThenTalkAfterRecoverIsNotTruncated"),
            live
        )
        XCTAssertTrue(live.contains("mixedHarmonicSpeechPCM"), live)
        XCTAssertFalse(live.contains("TapSpeechEnergy"), live)
        XCTAssertTrue(live.contains("convenience init(session: VoiceSession, command: Data)"), live)
        XCTAssertTrue(live.contains("GrokVoiceService("), live)
        XCTAssertTrue(live.contains("AppModel("), live)
        XCTAssertTrue(live.contains("applyUserTurn(\"what version are we on\")"), live)
        XCTAssertTrue(live.contains("applyUserTurn(\"show me my emails\")"), live)
        XCTAssertTrue(live.contains("listenLoopEngine"), live)
        XCTAssertTrue(live.contains("simulateHALTapYankLeavingInstalledFlagTrue"), live)
        XCTAssertTrue(live.contains("AVAudioEngineConfigurationChange"), live)
        XCTAssertTrue(live.contains("postEngineConfigurationChange"), live)
        XCTAssertTrue(live.contains("feedTapPCM16"), live)
        XCTAssertTrue(live.contains("FirstHearTapLoop.accept"), live)
        XCTAssertTrue(live.contains("listenLoopClose1000"), live)
        XCTAssertTrue(live.contains("stayIdle"), live)
        XCTAssertFalse(live.contains("FakeLiveVoiceService"), live)
        XCTAssertFalse(live.contains("emitUser"), live)
        XCTAssertFalse(live.contains("func rearmTap"), live)
        XCTAssertFalse(live.contains("watchdog"), live)
        XCTAssertFalse(live.contains("MicLivenessMonitor"), live)
        if let glanceAt = live.range(of: "applyUserTurn(\"show me my emails\")"),
           let yankAt = live.range(of: "simulateHALTapYankLeavingInstalledFlagTrue") {
            XCTAssertLessThan(
                glanceAt.lowerBound,
                yankAt.lowerBound,
                "delayed yank must be after live version/glance returnToListen"
            )
        } else {
            XCTFail("live-path gate must glance then yank")
        }
        if let yankAt = live.range(of: "simulateHALTapYankLeavingInstalledFlagTrue"),
           let configAt = live.range(of: "postEngineConfigurationChange") {
            XCTAssertLessThan(
                yankAt.lowerBound,
                configAt.lowerBound,
                "configuration change must arrive after the delayed yank"
            )
        } else {
            XCTFail("live-path gate must post configuration change after the yank")
        }
        XCTAssertFalse(
            live.contains("shouldReinstallTapIfSilentWhileRunning"),
            "do not add another engine-only shouldX helper for this slice"
        )
        let delayed = speakSlice(
            live,
            from: "func testVersionThenGlanceLivePathDelayedYankConfigChangeThirdCommandIsATurn",
            to: "func testVersionThenGlanceWritePlayerDoesNotFlickerAudioSession"
        )
        XCTAssertTrue(delayed.contains("postEngineConfigurationChange"), delayed)
        let prevent = speakSlice(
            live,
            from: "func testVersionThenGlanceWritePlayerDoesNotFlickerAudioSession",
            to: "func testLiveConversationLoopTalkAnswerTalkAgainWithoutRepeat"
        )
        XCTAssertFalse(prevent.contains("postEngineConfigurationChange"), prevent)
        XCTAssertFalse(prevent.contains("postInterruption"), prevent)
        XCTAssertTrue(prevent.contains("playAndRecord"), prevent)
        XCTAssertTrue(prevent.contains("voiceChat"), prevent)
        XCTAssertTrue(prevent.contains("simulateHALTapYankLeavingInstalledFlagTrue"), prevent)
        XCTAssertTrue(prevent.contains("zero-notification yank must not be paper-greened"), prevent)
        XCTAssertTrue(prevent.contains("feedTapPCM16"), prevent)
        let conversation = speakSlice(
            live,
            from: "func testLiveConversationLoopTalkAnswerTalkAgainWithoutRepeat",
            to: "func testLiveConversationLoopAfterDeskTTSWithoutSocketCloseNextCommandIsATurn"
        )
        XCTAssertTrue(conversation.contains("GrokVoiceService("), conversation)
        XCTAssertTrue(conversation.contains("AppModel("), conversation)
        XCTAssertTrue(conversation.contains("startListenLoopAudioForTests"), conversation)
        XCTAssertTrue(conversation.contains("feedTapPCM16"), conversation)
        XCTAssertTrue(conversation.contains("voice.speak"), conversation)
        XCTAssertTrue(conversation.contains("ListenInterrupt.isCommand"), conversation)
        XCTAssertTrue(conversation.contains("interruptResponse"), conversation)
        XCTAssertTrue(conversation.contains("415c955"), conversation)
        XCTAssertFalse(conversation.contains("simulateHALTapYankLeavingInstalledFlagTrue"), conversation)
        XCTAssertFalse(conversation.contains("postEngineConfigurationChange"), conversation)
        XCTAssertFalse(conversation.contains("emitUser"), conversation)
        XCTAssertFalse(conversation.contains("FakeLiveVoiceService"), conversation)
        XCTAssertFalse(conversation.contains("EchoBargeIn"), conversation)
        XCTAssertFalse(conversation.contains("EarlyFinalHold"), conversation)
        XCTAssertFalse(conversation.contains("leftover-echo"), conversation)
        if let firstSpeak = conversation.range(of: "voice.speak"),
           let secondFeed = conversation.range(of: "feedTapPCM16(command2)") {
            XCTAssertLessThan(
                firstSpeak.lowerBound,
                secondFeed.lowerBound,
                "command PCM 2 must be after write→player drain"
            )
        } else {
            XCTFail("conversation loop must answer then take PCM 2")
        }
        let openSocket = speakSlice(
            live,
            from: "func testLiveConversationLoopAfterDeskTTSWithoutSocketCloseNextCommandIsATurn",
            to: "func testLiveConversationLoopDidClose1000AfterDrainNextCommandIsATurn"
        )
        XCTAssertTrue(openSocket.contains("GrokVoiceService("), openSocket)
        XCTAssertTrue(openSocket.contains("AppModel("), openSocket)
        XCTAssertTrue(openSocket.contains("startListenLoopAudioForTests"), openSocket)
        XCTAssertTrue(openSocket.contains("simulateListenLoopSocketDidOpenThenSessionReady"), openSocket)
        XCTAssertTrue(openSocket.contains("feedTapPCM16(command1)"), openSocket)
        XCTAssertTrue(openSocket.contains("voice.speak"), openSocket)
        XCTAssertTrue(openSocket.contains("feedTapPCM16(command2)"), openSocket)
        XCTAssertTrue(openSocket.contains("listenLoopDeliveredAudioPCM"), openSocket)
        XCTAssertTrue(openSocket.contains("input_audio_buffer.append"), openSocket)
        XCTAssertTrue(openSocket.contains("listenLoopSocketHasSendTask"), openSocket)
        XCTAssertTrue(openSocket.contains("listenLoopRecoverCount"), openSocket)
        XCTAssertTrue(openSocket.contains("engine.startCount"), openSocket)
        XCTAssertTrue(openSocket.contains("interruptResponse"), openSocket)
        XCTAssertTrue(openSocket.contains("415c955"), openSocket)
        XCTAssertTrue(openSocket.contains("4dc589f"), openSocket)
        XCTAssertFalse(
            openSocket.contains("attachListenLoopSendTaskForTests"),
            "4dc589f attach is a fake send task — sendRaw is a no-op when the real task is nil"
        )
        XCTAssertFalse(openSocket.contains("simulateListenLoopSocketClose1000"), openSocket)
        XCTAssertFalse(openSocket.contains("waitUntilListenLoopQueuedTurnClosed"), openSocket)
        XCTAssertFalse(openSocket.contains("applyUserTurn"), openSocket)
        XCTAssertFalse(openSocket.contains("emitUser"), openSocket)
        XCTAssertFalse(openSocket.contains("FakeLiveVoiceService"), openSocket)
        XCTAssertFalse(openSocket.contains("quietCommitMaxPostponeMs"), openSocket)
        if let openAt = openSocket.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let firstFeed = openSocket.range(of: "feedTapPCM16(command1)"),
           let speakAt = openSocket.range(of: "InboxGlance.spokenListAck"),
           let secondFeed = openSocket.range(of: "feedTapPCM16(command2)") {
            XCTAssertLessThan(
                openAt.lowerBound,
                firstFeed.lowerBound,
                "DidOpen + session.updated must arm the real client before command 1"
            )
            XCTAssertLessThan(
                firstFeed.lowerBound,
                speakAt.lowerBound,
                "command PCM 1 must be before write→player drain"
            )
            XCTAssertLessThan(
                speakAt.lowerBound,
                secondFeed.lowerBound,
                "command PCM 2 must be after write→player drain"
            )
            let afterSpeak = String(openSocket[speakAt.upperBound..<secondFeed.lowerBound])
            XCTAssertFalse(
                afterSpeak.contains("simulateListenLoopSocketDidOpenThenSessionReady"),
                "DidOpen after drain paper-greens a dead client"
            )
            XCTAssertFalse(
                afterSpeak.contains("attachListenLoopSendTaskForTests"),
                "do not attach after drain to flush a queue this gate must fail"
            )
            XCTAssertFalse(
                afterSpeak.contains("session.updated"),
                "do not session.updated after drain"
            )
        } else {
            XCTFail("open-socket gate must DidOpen once before command 1, drain, then take PCM 2")
        }
        let close1000 = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000AfterDrainNextCommandIsATurn",
            to: "func testLiveConversationLoopDidClose1000StayLiveFalseIdleAfterDeskTTSRecoversNextCommand"
        )
        XCTAssertTrue(close1000.contains("GrokVoiceService("), close1000)
        XCTAssertTrue(close1000.contains("AppModel("), close1000)
        XCTAssertTrue(close1000.contains("startListenLoopAudioForTests"), close1000)
        XCTAssertTrue(close1000.contains("simulateListenLoopSocketClose1000"), close1000)
        XCTAssertTrue(close1000.contains("listenLoopRecoverCount"), close1000)
        XCTAssertTrue(close1000.contains("listenLoopSocketHasSendTask"), close1000)
        XCTAssertTrue(close1000.contains("feedTapPCM16(command2)"), close1000)
        XCTAssertTrue(close1000.contains("interruptResponse"), close1000)
        XCTAssertTrue(close1000.contains("ListenInterrupt.isCommand"), close1000)
        XCTAssertTrue(close1000.contains("415c955"), close1000)
        XCTAssertFalse(close1000.contains("emitUser"), close1000)
        XCTAssertFalse(close1000.contains("FakeLiveVoiceService"), close1000)
        XCTAssertFalse(close1000.contains("simulateHALTapYankLeavingInstalledFlagTrue"), close1000)
        XCTAssertFalse(close1000.contains("postEngineConfigurationChange"), close1000)
        XCTAssertFalse(close1000.contains("EchoBargeIn"), close1000)
        XCTAssertFalse(close1000.contains("EarlyFinalHold"), close1000)
        if let firstSpeak = close1000.range(of: "voice.speak"),
           let closeAt = close1000.range(of: "simulateListenLoopSocketClose1000"),
           let secondFeed = close1000.range(of: "feedTapPCM16(command2)") {
            XCTAssertLessThan(
                firstSpeak.lowerBound,
                closeAt.lowerBound,
                "DidClose 1000 must fire after write→player drain"
            )
            XCTAssertLessThan(
                closeAt.lowerBound,
                secondFeed.lowerBound,
                "command PCM 2 must be after the live DidClose 1000"
            )
        } else {
            XCTFail("DidClose 1000 gate must drain, fire close, then take PCM 2")
        }
        let idleClose = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000StayLiveFalseIdleAfterDeskTTSRecoversNextCommand",
            to: "func testLiveConversationLoopDidClose1000StayLiveFalseIdleAfterDeskTTSGrokCreatesResponse"
        )
        XCTAssertTrue(idleClose.contains("GrokVoiceService("), idleClose)
        XCTAssertTrue(idleClose.contains("AppModel("), idleClose)
        XCTAssertTrue(idleClose.contains("startListenLoopAudioForTests"), idleClose)
        XCTAssertTrue(idleClose.contains("simulateListenLoopIdleAfterDeskTTSPhoneLog"), idleClose)
        XCTAssertTrue(idleClose.contains("listenLoopPhoneStayLive"), idleClose)
        XCTAssertTrue(idleClose.contains("listenLoopArmed"), idleClose)
        XCTAssertTrue(idleClose.contains("simulateListenLoopSocketClose1000"), idleClose)
        XCTAssertTrue(idleClose.contains("listenLoopRecoverCount"), idleClose)
        XCTAssertTrue(idleClose.contains("feedTapPCM16(command2)"), idleClose)
        XCTAssertTrue(idleClose.contains("ListenLoopWebSocketLoopback"), idleClose)
        XCTAssertTrue(idleClose.contains("setListenLoopRealtimeURLOverrideForTests"), idleClose)
        XCTAssertTrue(idleClose.contains("listenLoopProductionWebSocketTask"), idleClose)
        XCTAssertTrue(idleClose.contains("URLSessionWebSocketTask"), idleClose)
        XCTAssertTrue(idleClose.contains("listenLoopUsesTestSendSink"), idleClose)
        XCTAssertTrue(idleClose.contains("listenLoopHasProductionSendTask"), idleClose)
        XCTAssertTrue(idleClose.contains("createResponse(inSessionUpdate"), idleClose)
        XCTAssertTrue(idleClose.contains("receivedAppendPCM"), idleClose)
        XCTAssertTrue(idleClose.contains("415c955"), idleClose)
        XCTAssertTrue(idleClose.contains("interruptResponse"), idleClose)
        XCTAssertTrue(idleClose.contains("engine.startCount"), idleClose)
        XCTAssertFalse(
            idleClose.contains("simulateListenLoopSocketDidOpenThenSessionReady"),
            "re-arming a recorder after recover paper-greens a dead sendRaw"
        )
        XCTAssertFalse(idleClose.contains("attachTestSendRecorder"), idleClose)
        XCTAssertFalse(idleClose.contains("attachListenLoopSendTaskForTests"), idleClose)
        XCTAssertFalse(
            idleClose.contains("listenLoopDeliveredAudioPCM"),
            "delivered PCM is the testSendSink recorder — command 2 must hit the loopback"
        )
        XCTAssertFalse(idleClose.contains("applyUserTurn"), idleClose)
        XCTAssertFalse(idleClose.contains("emitUser"), idleClose)
        XCTAssertFalse(idleClose.contains("FakeLiveVoiceService"), idleClose)
        XCTAssertFalse(idleClose.contains("quietCommitMaxPostponeMs"), idleClose)
        let loopbackSource = try XCTUnwrap(repoFile("VoiceDeskTests/ListenLoopWebSocketLoopback.swift"))
        XCTAssertTrue(loopbackSource.contains("@testable import VoiceDesk"), loopbackSource)
        XCTAssertTrue(loopbackSource.contains("LiveGrokVoiceClient.pcmFromAppendJSON"), loopbackSource)
        XCTAssertFalse(
            loopbackSource.contains("func pcmFromAppendJSON"),
            "do not copy the append parser into the loopback"
        )
        XCTAssertTrue(loopbackSource.contains("import Network"), loopbackSource)
        XCTAssertTrue(loopbackSource.contains("NWListener"), loopbackSource)
        XCTAssertTrue(loopbackSource.contains("NWProtocolWebSocket"), loopbackSource)
        XCTAssertTrue(loopbackSource.contains("session.updated"), loopbackSource)
        XCTAssertTrue(loopbackSource.contains("127.0.0.1"), loopbackSource)
        XCTAssertFalse(loopbackSource.contains("socket(AF_INET"), loopbackSource)
        XCTAssertFalse(loopbackSource.contains("Thread.detachNewThread"), loopbackSource)
        XCTAssertFalse(loopbackSource.contains("serveQueue"), loopbackSource)
        XCTAssertFalse(loopbackSource.contains("Sec-WebSocket-Accept"), loopbackSource)
        XCTAssertFalse(loopbackSource.contains("testSendSink"), loopbackSource)
        let connectFn = speakSlice(
            try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoice.swift")),
            from: "func connect(apiKey:",
            to: "func disconnect()"
        )
        XCTAssertTrue(connectFn.contains("override != nil"), connectFn)
        XCTAssertTrue(connectFn.contains("webSocketTask(with: url)"), connectFn)
        if let loopAt = idleClose.range(of: "ListenLoopWebSocketLoopback"),
           let idleAt = idleClose.range(of: "simulateListenLoopIdleAfterDeskTTSPhoneLog"),
           let closeAt = idleClose.range(of: "simulateListenLoopSocketClose1000"),
           let taskAt = idleClose.range(of: "listenLoopProductionWebSocketTask"),
           let secondFeed = idleClose.range(of: "feedTapPCM16(command2)") {
            XCTAssertLessThan(
                loopAt.lowerBound,
                closeAt.lowerBound,
                "loopback must listen before recover connect"
            )
            XCTAssertLessThan(
                idleAt.lowerBound,
                closeAt.lowerBound,
                "phone-log idle must come before DidClose 1000"
            )
            XCTAssertLessThan(
                closeAt.lowerBound,
                taskAt.lowerBound,
                "recover must prove a real URLSessionWebSocketTask before command 2"
            )
            XCTAssertLessThan(
                taskAt.lowerBound,
                secondFeed.lowerBound,
                "if recover never creates a task, command 2 must not be fed as a paper send"
            )
            XCTAssertLessThan(
                closeAt.lowerBound,
                secondFeed.lowerBound,
                "command PCM 2 must be after the stayLive=false close"
            )
        } else {
            XCTFail("stayLive=false close must idle, DidClose, prove a real task, then feed PCM 2")
        }
        let grokCreates = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000StayLiveFalseIdleAfterDeskTTSGrokCreatesResponse",
            to: "func testLiveConversationLoopDidClose1000DeadSocketWindowSendsQueuedCommand"
        )
        XCTAssertTrue(grokCreates.contains("GrokVoiceService("), grokCreates)
        XCTAssertTrue(grokCreates.contains("AppModel("), grokCreates)
        XCTAssertTrue(grokCreates.contains("startListenLoopAudioForTests"), grokCreates)
        XCTAssertTrue(grokCreates.contains("VoiceTape.shouldSkipLive"), grokCreates)
        XCTAssertTrue(grokCreates.contains("VoiceDeskSecrets.xaiAPIKey"), grokCreates)
        XCTAssertTrue(grokCreates.contains("voiceTapePCM16"), grokCreates)
        XCTAssertTrue(grokCreates.contains("mint-voice-tapes.sh"), grokCreates)
        XCTAssertTrue(grokCreates.contains("feedVoiceTapeThroughLiveTap"), grokCreates)
        XCTAssertTrue(grokCreates.contains("simulateListenLoopIdleAfterDeskTTSPhoneLog"), grokCreates)
        XCTAssertTrue(grokCreates.contains("listenLoopPhoneStayLive"), grokCreates)
        XCTAssertTrue(grokCreates.contains("simulateListenLoopSocketClose1000"), grokCreates)
        XCTAssertTrue(grokCreates.contains("listenLoopRecoverCount"), grokCreates)
        XCTAssertTrue(grokCreates.contains("listenLoopHasProductionSendTask"), grokCreates)
        XCTAssertTrue(grokCreates.contains("waitUntilListenLoopHasProductionSendTask"), grokCreates)
        XCTAssertTrue(grokCreates.contains("listenLoopResponseCreatedCount"), grokCreates)
        XCTAssertTrue(grokCreates.contains("waitUntilListenLoopResponseCreated"), grokCreates)
        XCTAssertTrue(grokCreates.contains("response.created"), grokCreates)
        XCTAssertTrue(grokCreates.contains("415c955"), grokCreates)
        XCTAssertTrue(grokCreates.contains("engine.startCount"), grokCreates)
        XCTAssertTrue(grokCreates.contains("transcript injects do not count"), grokCreates)
        XCTAssertFalse(
            grokCreates.contains("simulateListenLoopSocketDidOpenThenSessionReady"),
            "paper DidOpen is not live Grok"
        )
        XCTAssertFalse(grokCreates.contains("attachTestSendRecorder"), grokCreates)
        XCTAssertFalse(grokCreates.contains("attachListenLoopSendTaskForTests"), grokCreates)
        XCTAssertFalse(
            grokCreates.contains("ListenLoopWebSocketLoopback"),
            "f2fb4f5 loopback only proves we talk to ourselves"
        )
        XCTAssertFalse(
            grokCreates.contains("setListenLoopRealtimeURLOverrideForTests"),
            "do not point recover at a loopback we control"
        )
        XCTAssertFalse(
            grokCreates.contains("listenLoopDeliveredAudioPCM"),
            "delivered PCM is the testSendSink recorder — live Grok must create a response"
        )
        XCTAssertFalse(grokCreates.contains("applyUserTurn"), grokCreates)
        XCTAssertFalse(grokCreates.contains("emitUser"), grokCreates)
        XCTAssertFalse(grokCreates.contains("FakeLiveVoiceService"), grokCreates)
        XCTAssertFalse(grokCreates.contains("quietCommitMaxPostponeMs"), grokCreates)
        if let firstFeed = grokCreates.range(of: "feedTapPCM16(command1)"),
           let speakAt = grokCreates.range(of: "InboxGlance.spokenListAck"),
           let secondFeed = grokCreates.range(of: "feedTapPCM16(command2)"),
           let idleAt = grokCreates.range(of: "simulateListenLoopIdleAfterDeskTTSPhoneLog"),
           let closeAt = grokCreates.range(of: "simulateListenLoopSocketClose1000"),
           let taskAt = grokCreates.range(of: "waitUntilListenLoopHasProductionSendTask"),
           let beforeAt = grokCreates.range(of: "createdBeforeCommand3"),
           let tapeAt = grokCreates.range(of: "feedVoiceTapeThroughLiveTap"),
           let createdAt = grokCreates.range(of: "waitUntilListenLoopResponseCreated") {
            XCTAssertLessThan(
                firstFeed.lowerBound,
                speakAt.lowerBound,
                "command PCM 1 must be before write→player drain"
            )
            XCTAssertLessThan(
                speakAt.lowerBound,
                secondFeed.lowerBound,
                "talk again must be after write→player drain"
            )
            XCTAssertLessThan(
                secondFeed.lowerBound,
                idleAt.lowerBound,
                "two PCM turns must land before the phone-log idle"
            )
            XCTAssertLessThan(
                idleAt.lowerBound,
                closeAt.lowerBound,
                "phone-log idle must come before DidClose 1000"
            )
            XCTAssertLessThan(
                closeAt.lowerBound,
                taskAt.lowerBound,
                "recover must prove opened && task before the third command"
            )
            XCTAssertLessThan(
                taskAt.lowerBound,
                beforeAt.lowerBound,
                "snapshot response.created after recover, not before"
            )
            XCTAssertLessThan(
                beforeAt.lowerBound,
                tapeAt.lowerBound,
                "415c955 flushed leftovers must not count as the third-command response"
            )
            XCTAssertLessThan(
                tapeAt.lowerBound,
                createdAt.lowerBound,
                "response.created must be asserted after the VoiceTape third command"
            )
        } else {
            XCTFail("live Grok gate must talk, answer, talk again, idle, DidClose, recover, then require response.created")
        }
        let sendTask = speakSlice(
            try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoice.swift")),
            from: "var hasProductionSendTask: Bool {",
            to: "var productionWebSocketTaskForTests"
        )
        XCTAssertTrue(sendTask.contains("opened && task != nil && !testSendSink"), sendTask)
        let deadSocket = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000DeadSocketWindowSendsQueuedCommand",
            to: "func testLiveConversationLoopDidClose1000SessionReadyFlushSendsQueuedCommand"
        )
        XCTAssertTrue(deadSocket.contains("GrokVoiceService("), deadSocket)
        XCTAssertTrue(deadSocket.contains("AppModel("), deadSocket)
        XCTAssertTrue(deadSocket.contains("startListenLoopAudioForTests"), deadSocket)
        XCTAssertTrue(deadSocket.contains("simulateListenLoopSocketClose1000"), deadSocket)
        XCTAssertTrue(deadSocket.contains("listenLoopSocketHasSendTask"), deadSocket)
        XCTAssertTrue(deadSocket.contains("feedTapPCM16(command2)"), deadSocket)
        XCTAssertTrue(deadSocket.contains("attachListenLoopSendTaskForTests"), deadSocket)
        XCTAssertTrue(deadSocket.contains("listenLoopDeliveredAudioPCM"), deadSocket)
        XCTAssertTrue(deadSocket.contains("15dcc7d"), deadSocket)
        XCTAssertTrue(deadSocket.contains("interruptResponse"), deadSocket)
        XCTAssertFalse(deadSocket.contains("emitUser"), deadSocket)
        XCTAssertFalse(deadSocket.contains("FakeLiveVoiceService"), deadSocket)
        XCTAssertFalse(deadSocket.contains("simulateHALTapYankLeavingInstalledFlagTrue"), deadSocket)
        XCTAssertFalse(deadSocket.contains("postEngineConfigurationChange"), deadSocket)
        if let closeAt = deadSocket.range(of: "simulateListenLoopSocketClose1000"),
           let secondFeed = deadSocket.range(of: "feedTapPCM16(command2)"),
           let attachAt = deadSocket.range(of: "attachListenLoopSendTaskForTests") {
            XCTAssertLessThan(
                closeAt.lowerBound,
                secondFeed.lowerBound,
                "command PCM 2 must be fed in the dead-socket window"
            )
            XCTAssertLessThan(
                secondFeed.lowerBound,
                attachAt.lowerBound,
                "15dcc7d dropped command 2 before a send task existed"
            )
        } else {
            XCTFail("dead-socket gate must DidClose, feed PCM 2, then attach-send-task")
        }
        let sessionReady = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000SessionReadyFlushSendsQueuedCommand",
            to: "func testLiveConversationLoopDidClose1000FlushClosesQueuedTurn"
        )
        XCTAssertTrue(sessionReady.contains("GrokVoiceService("), sessionReady)
        XCTAssertTrue(sessionReady.contains("AppModel("), sessionReady)
        XCTAssertTrue(sessionReady.contains("simulateListenLoopSocketClose1000"), sessionReady)
        XCTAssertTrue(sessionReady.contains("feedTapPCM16(command2)"), sessionReady)
        XCTAssertTrue(sessionReady.contains("simulateListenLoopSocketDidOpenThenSessionReady"), sessionReady)
        XCTAssertTrue(sessionReady.contains("listenLoopDeliveredSendTypes"), sessionReady)
        XCTAssertTrue(sessionReady.contains("session.update"), sessionReady)
        XCTAssertTrue(sessionReady.contains("19c1b33"), sessionReady)
        XCTAssertTrue(sessionReady.contains("interruptResponse"), sessionReady)
        XCTAssertFalse(sessionReady.contains("emitUser"), sessionReady)
        XCTAssertFalse(sessionReady.contains("FakeLiveVoiceService"), sessionReady)
        XCTAssertFalse(sessionReady.contains("attachListenLoopSendTaskForTests"), sessionReady)
        XCTAssertFalse(sessionReady.contains("simulateHALTapYankLeavingInstalledFlagTrue"), sessionReady)
        if let closeAt = sessionReady.range(of: "simulateListenLoopSocketClose1000"),
           let secondFeed = sessionReady.range(of: "feedTapPCM16(command2)"),
           let openAt = sessionReady.range(of: "simulateListenLoopSocketDidOpenThenSessionReady") {
            XCTAssertLessThan(
                closeAt.lowerBound,
                secondFeed.lowerBound,
                "command PCM 2 must be fed in the dead-socket window"
            )
            XCTAssertLessThan(
                secondFeed.lowerBound,
                openAt.lowerBound,
                "19c1b33 flushed those appends on DidOpen before session.update"
            )
        } else {
            XCTFail("session-ready gate must DidClose, feed PCM 2, then DidOpen + session.updated")
        }
        let closeTurn = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000FlushClosesQueuedTurn",
            to: "func testLiveConversationLoopDidClose1000StillTalkingDoesNotCommitMidUtterance"
        )
        XCTAssertTrue(closeTurn.contains("GrokVoiceService("), closeTurn)
        XCTAssertTrue(closeTurn.contains("AppModel("), closeTurn)
        XCTAssertTrue(closeTurn.contains("simulateListenLoopSocketClose1000"), closeTurn)
        XCTAssertTrue(closeTurn.contains("feedTapPCM16(command2)"), closeTurn)
        XCTAssertTrue(closeTurn.contains("simulateListenLoopSocketDidOpenThenSessionReady"), closeTurn)
        XCTAssertTrue(closeTurn.contains("waitUntilListenLoopQueuedTurnClosed"), closeTurn)
        XCTAssertTrue(closeTurn.contains("input_audio_buffer.commit"), closeTurn)
        XCTAssertTrue(closeTurn.contains("listenLoopDeliveredAudioPCM"), closeTurn)
        XCTAssertTrue(closeTurn.contains("command2At"), closeTurn)
        XCTAssertTrue(closeTurn.contains("48eb875"), closeTurn)
        XCTAssertTrue(closeTurn.contains("interruptResponse"), closeTurn)
        XCTAssertFalse(
            closeTurn.contains("types.lastIndex(of: \"input_audio_buffer.append\")"),
            "a5646b0 lastIndex(append) is a later live-tap frame, not the queued command"
        )
        XCTAssertFalse(closeTurn.contains("emitUser"), closeTurn)
        XCTAssertFalse(closeTurn.contains("FakeLiveVoiceService"), closeTurn)
        XCTAssertFalse(closeTurn.contains("attachListenLoopSendTaskForTests"), closeTurn)
        XCTAssertFalse(closeTurn.contains("simulateHALTapYankLeavingInstalledFlagTrue"), closeTurn)
        if let secondFeed = closeTurn.range(of: "feedTapPCM16(command2)"),
           let openAt = closeTurn.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let commitAt = closeTurn.range(of: "input_audio_buffer.commit") {
            XCTAssertLessThan(
                secondFeed.lowerBound,
                openAt.lowerBound,
                "command PCM 2 must be fed before the session-ready flush"
            )
            XCTAssertLessThan(
                openAt.lowerBound,
                commitAt.lowerBound,
                "turn close is asserted after flush, not by feeding more PCM"
            )
        } else {
            XCTFail("flush-commit gate must DidClose, feed PCM 2, flush, then require commit")
        }
        if let openAt = closeTurn.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let noiseAt = closeTurn.range(of: "feedTapPCM16(noise)") {
            let afterFlush = String(closeTurn[openAt.upperBound..<noiseAt.lowerBound])
            XCTAssertFalse(
                afterFlush.contains("feedTapPCM16(command"),
                "do not feed command PCM after flush to paper-green VAD"
            )
        }
        let stillTalking = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000StillTalkingDoesNotCommitMidUtterance",
            to: "func testLiveConversationLoopDidClose1000SilenceTapStillClosesQueuedTurn"
        )
        XCTAssertTrue(stillTalking.contains("GrokVoiceService("), stillTalking)
        XCTAssertTrue(stillTalking.contains("AppModel("), stillTalking)
        XCTAssertTrue(stillTalking.contains("simulateListenLoopSocketClose1000"), stillTalking)
        XCTAssertTrue(stillTalking.contains("feedTapPCM16(command2)"), stillTalking)
        XCTAssertTrue(stillTalking.contains("simulateListenLoopSocketDidOpenThenSessionReady"), stillTalking)
        XCTAssertTrue(stillTalking.contains("feedTapPCM16(continued)"), stillTalking)
        XCTAssertTrue(stillTalking.contains("6b5f0ee"), stillTalking)
        XCTAssertTrue(stillTalking.contains("interruptResponse"), stillTalking)
        XCTAssertFalse(stillTalking.contains("emitUser"), stillTalking)
        XCTAssertFalse(stillTalking.contains("FakeLiveVoiceService"), stillTalking)
        XCTAssertFalse(stillTalking.contains("attachListenLoopSendTaskForTests"), stillTalking)
        if let openAt = stillTalking.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let continuedAt = stillTalking.range(of: "feedTapPCM16(continued)") {
            XCTAssertLessThan(
                openAt.lowerBound,
                continuedAt.lowerBound,
                "still-talking PCM must arrive after the session-ready flush"
            )
        } else {
            XCTFail("still-talking gate must flush, then feed more speech-shaped PCM")
        }
        let silenceTap = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000SilenceTapStillClosesQueuedTurn",
            to: "func testLiveConversationLoopDidClose1000AmbientTapStillClosesQueuedTurn"
        )
        XCTAssertTrue(silenceTap.contains("GrokVoiceService("), silenceTap)
        XCTAssertTrue(silenceTap.contains("AppModel("), silenceTap)
        XCTAssertTrue(silenceTap.contains("simulateListenLoopSocketClose1000"), silenceTap)
        XCTAssertTrue(silenceTap.contains("feedTapPCM16(command2)"), silenceTap)
        XCTAssertTrue(silenceTap.contains("simulateListenLoopSocketDidOpenThenSessionReady"), silenceTap)
        XCTAssertTrue(silenceTap.contains("feedTapPCM16(continued)"), silenceTap)
        XCTAssertTrue(silenceTap.contains("feedTapPCM16(silence)"), silenceTap)
        XCTAssertTrue(silenceTap.contains("nearSilentPCM"), silenceTap)
        XCTAssertTrue(silenceTap.contains("00297ee"), silenceTap)
        XCTAssertTrue(silenceTap.contains("input_audio_buffer.commit"), silenceTap)
        XCTAssertTrue(silenceTap.contains("interruptResponse"), silenceTap)
        XCTAssertTrue(silenceTap.contains("closedDuringSilence"), silenceTap)
        XCTAssertFalse(silenceTap.contains("emitUser"), silenceTap)
        XCTAssertFalse(silenceTap.contains("FakeLiveVoiceService"), silenceTap)
        XCTAssertFalse(silenceTap.contains("attachListenLoopSendTaskForTests"), silenceTap)
        XCTAssertFalse(
            silenceTap.contains("waitUntilListenLoopQueuedTurnClosed"),
            "00297ee paper-greens if we stop feeding and then wait — silence must keep arriving"
        )
        if let openAt = silenceTap.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let continuedAt = silenceTap.range(of: "feedTapPCM16(continued)"),
           let silenceAt = silenceTap.range(of: "feedTapPCM16(silence)") {
            XCTAssertLessThan(
                openAt.lowerBound,
                continuedAt.lowerBound,
                "speech-shaped PCM must arrive after the session-ready flush"
            )
            XCTAssertLessThan(
                continuedAt.lowerBound,
                silenceAt.lowerBound,
                "silence frames follow the still-talking tail, like a live tap"
            )
        } else {
            XCTFail("silence-tap gate must flush, feed speech, then keep feeding silence")
        }
        let ambientTap = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000AmbientTapStillClosesQueuedTurn",
            to: "func testLiveConversationLoopDidClose1000QueuedCommandRequestsResponse"
        )
        XCTAssertTrue(ambientTap.contains("GrokVoiceService("), ambientTap)
        XCTAssertTrue(ambientTap.contains("AppModel("), ambientTap)
        XCTAssertTrue(ambientTap.contains("simulateListenLoopSocketClose1000"), ambientTap)
        XCTAssertTrue(ambientTap.contains("feedTapPCM16(command2)"), ambientTap)
        XCTAssertTrue(ambientTap.contains("simulateListenLoopSocketDidOpenThenSessionReady"), ambientTap)
        XCTAssertTrue(ambientTap.contains("feedTapPCM16(continued)"), ambientTap)
        XCTAssertTrue(ambientTap.contains("feedTapPCM16(noise)"), ambientTap)
        XCTAssertTrue(ambientTap.contains("speechShapedPCM(hertz: 90)"), ambientTap)
        XCTAssertTrue(ambientTap.contains("2679792"), ambientTap)
        XCTAssertTrue(ambientTap.contains("input_audio_buffer.commit"), ambientTap)
        XCTAssertTrue(ambientTap.contains("interruptResponse"), ambientTap)
        XCTAssertTrue(ambientTap.contains("closedDuringAmbient"), ambientTap)
        XCTAssertTrue(ambientTap.contains("ListenInterrupt.isCommand"), ambientTap)
        XCTAssertFalse(ambientTap.contains("nearSilentPCM"), ambientTap)
        XCTAssertFalse(ambientTap.contains("emitUser"), ambientTap)
        XCTAssertFalse(ambientTap.contains("FakeLiveVoiceService"), ambientTap)
        XCTAssertFalse(ambientTap.contains("attachListenLoopSendTaskForTests"), ambientTap)
        XCTAssertFalse(
            ambientTap.contains("waitUntilListenLoopQueuedTurnClosed"),
            "2679792 paper-greens if we stop feeding radio and then wait"
        )
        if let openAt = ambientTap.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let continuedAt = ambientTap.range(of: "feedTapPCM16(continued)"),
           let noiseAt = ambientTap.range(of: "feedTapPCM16(noise)") {
            XCTAssertLessThan(
                openAt.lowerBound,
                continuedAt.lowerBound,
                "command-shaped PCM must arrive after the session-ready flush"
            )
            XCTAssertLessThan(
                continuedAt.lowerBound,
                noiseAt.lowerBound,
                "ambient / radio follows the still-talking tail, like a live tap"
            )
        } else {
            XCTFail("ambient-tap gate must flush, feed command PCM, then keep feeding radio")
        }
        let requestResponse = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000QueuedCommandRequestsResponse",
            to: "func testLiveConversationLoopDidClose1000StillTalkingLongerThanQuietCommitDoesNotTruncate"
        )
        XCTAssertTrue(requestResponse.contains("GrokVoiceService("), requestResponse)
        XCTAssertTrue(requestResponse.contains("AppModel("), requestResponse)
        XCTAssertTrue(requestResponse.contains("simulateListenLoopSocketClose1000"), requestResponse)
        XCTAssertTrue(requestResponse.contains("feedTapPCM16(command2)"), requestResponse)
        XCTAssertTrue(requestResponse.contains("simulateListenLoopSocketDidOpenThenSessionReady"), requestResponse)
        XCTAssertTrue(requestResponse.contains("waitUntilListenLoopQueuedTurnClosed"), requestResponse)
        XCTAssertTrue(requestResponse.contains("listenLoopDeliveredSends"), requestResponse)
        XCTAssertTrue(requestResponse.contains("createResponse(inSessionUpdate"), requestResponse)
        XCTAssertTrue(requestResponse.contains("e89d443"), requestResponse)
        XCTAssertTrue(requestResponse.contains("input_audio_buffer.commit"), requestResponse)
        XCTAssertTrue(requestResponse.contains("interruptResponse"), requestResponse)
        XCTAssertFalse(requestResponse.contains("emitUser"), requestResponse)
        XCTAssertFalse(requestResponse.contains("FakeLiveVoiceService"), requestResponse)
        XCTAssertFalse(requestResponse.contains("attachListenLoopSendTaskForTests"), requestResponse)
        XCTAssertFalse(requestResponse.contains("sendListenResumeSessionUpdate"), requestResponse)
        if let openAt = requestResponse.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let commitAt = requestResponse.range(of: "input_audio_buffer.commit"),
           let createAt = requestResponse.range(of: "createResponse(inSessionUpdate") {
            XCTAssertLessThan(
                openAt.lowerBound,
                createAt.lowerBound,
                "create_response is asserted after the real DidOpen recover"
            )
            XCTAssertLessThan(
                openAt.lowerBound,
                commitAt.lowerBound,
                "commit is asserted after flush, not by feeding more PCM"
            )
        } else {
            XCTFail("response-request gate must DidClose, feed PCM 2, DidOpen, then require create_response before commit")
        }
        let stillTalkingLong = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000StillTalkingLongerThanQuietCommitDoesNotTruncate",
            to: "func testLiveConversationLoopDidClose1000RealSpeechStillTalkingDoesNotTruncate"
        )
        XCTAssertTrue(stillTalkingLong.contains("GrokVoiceService("), stillTalkingLong)
        XCTAssertTrue(stillTalkingLong.contains("AppModel("), stillTalkingLong)
        XCTAssertTrue(stillTalkingLong.contains("simulateListenLoopSocketClose1000"), stillTalkingLong)
        XCTAssertTrue(stillTalkingLong.contains("feedTapPCM16(command2)"), stillTalkingLong)
        XCTAssertTrue(stillTalkingLong.contains("simulateListenLoopSocketDidOpenThenSessionReady"), stillTalkingLong)
        XCTAssertTrue(stillTalkingLong.contains("feedTapPCM16(continued)"), stillTalkingLong)
        XCTAssertTrue(stillTalkingLong.contains("7350153"), stillTalkingLong)
        XCTAssertTrue(stillTalkingLong.contains("quietCommitMs"), stillTalkingLong)
        XCTAssertTrue(stillTalkingLong.contains("lastContinuedAt"), stillTalkingLong)
        XCTAssertTrue(stillTalkingLong.contains("command2At"), stillTalkingLong)
        XCTAssertTrue(stillTalkingLong.contains("input_audio_buffer.commit"), stillTalkingLong)
        XCTAssertTrue(stillTalkingLong.contains("interruptResponse"), stillTalkingLong)
        XCTAssertFalse(stillTalkingLong.contains("emitUser"), stillTalkingLong)
        XCTAssertFalse(stillTalkingLong.contains("FakeLiveVoiceService"), stillTalkingLong)
        XCTAssertFalse(stillTalkingLong.contains("TapSpeechEnergy"), stillTalkingLong)
        XCTAssertFalse(
            stillTalkingLong.contains("commit belongs after the still-talking tail"),
            "7350153 commit-after-tail is the flush-clock; queued command 2 is already in the buffer"
        )
        if let openAt = stillTalkingLong.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let continuedAt = stillTalkingLong.range(of: "feedTapPCM16(continued)"),
           let waitAt = stillTalkingLong.range(of: "waitUntilListenLoopQueuedTurnClosed") {
            XCTAssertLessThan(
                openAt.lowerBound,
                continuedAt.lowerBound,
                "command-shaped PCM must keep arriving after the session-ready flush"
            )
            XCTAssertLessThan(
                continuedAt.lowerBound,
                waitAt.lowerBound,
                "7350153 paper-greens if we feed one frame and then wait"
            )
        } else {
            XCTFail("long still-talking gate must flush, keep feeding command PCM, then require the queued command before commit")
        }
        let realSpeech = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000RealSpeechStillTalkingDoesNotTruncate",
            to: "func testLiveConversationLoopDidClose1000RealSpeechLongerThanMaxPostponeDoesNotTruncate"
        )
        XCTAssertTrue(realSpeech.contains("GrokVoiceService("), realSpeech)
        XCTAssertTrue(realSpeech.contains("AppModel("), realSpeech)
        XCTAssertTrue(realSpeech.contains("simulateListenLoopSocketClose1000"), realSpeech)
        XCTAssertTrue(realSpeech.contains("feedTapPCM16(command2)"), realSpeech)
        XCTAssertTrue(realSpeech.contains("simulateListenLoopSocketDidOpenThenSessionReady"), realSpeech)
        XCTAssertTrue(realSpeech.contains("mixedHarmonicSpeechPCM"), realSpeech)
        XCTAssertTrue(realSpeech.contains("feedTapPCM16(continued)"), realSpeech)
        XCTAssertTrue(realSpeech.contains("6264a07"), realSpeech)
        XCTAssertTrue(realSpeech.contains("quietCommitMs"), realSpeech)
        XCTAssertTrue(realSpeech.contains("lastContinuedAt"), realSpeech)
        XCTAssertTrue(realSpeech.contains("input_audio_buffer.commit"), realSpeech)
        XCTAssertTrue(realSpeech.contains("interruptResponse"), realSpeech)
        XCTAssertTrue(realSpeech.contains("let continued = Self.mixedHarmonicSpeechPCM()"), realSpeech)
        XCTAssertFalse(realSpeech.contains("let continued = Self.speechShapedPCM"), realSpeech)
        XCTAssertFalse(realSpeech.contains("emitUser"), realSpeech)
        XCTAssertFalse(realSpeech.contains("FakeLiveVoiceService"), realSpeech)
        XCTAssertFalse(realSpeech.contains("TapSpeechEnergy"), realSpeech)
        XCTAssertFalse(realSpeech.contains("QueuedTurnClose.shouldPostpone"), realSpeech)
        if let openAt = realSpeech.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let continuedAt = realSpeech.range(of: "feedTapPCM16(continued)"),
           let waitAt = realSpeech.range(of: "waitUntilListenLoopQueuedTurnClosed") {
            XCTAssertLessThan(
                openAt.lowerBound,
                continuedAt.lowerBound,
                "real-speech PCM must keep arriving after the session-ready flush"
            )
            XCTAssertLessThan(
                continuedAt.lowerBound,
                waitAt.lowerBound,
                "6264a07 paper-greens if we feed a sine and then wait"
            )
        } else {
            XCTFail("real-speech still-talking gate must flush, keep feeding mixed-harmonic PCM, then require the queued command before commit")
        }
        let realSpeechLong = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000RealSpeechLongerThanMaxPostponeDoesNotTruncate",
            to: "func testLiveConversationLoopDidClose1000DelayedCommandAfterRecoverIsNotTruncated"
        )
        XCTAssertTrue(realSpeechLong.contains("GrokVoiceService("), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("AppModel("), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("simulateListenLoopSocketClose1000"), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("feedTapPCM16(command2)"), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("simulateListenLoopSocketDidOpenThenSessionReady"), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("mixedHarmonicSpeechPCM"), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("feedTapPCM16(continued)"), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("3c7524b"), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("flush-clock"), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("lastContinuedAt"), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("command2At"), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("input_audio_buffer.commit"), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("interruptResponse"), realSpeechLong)
        XCTAssertTrue(realSpeechLong.contains("let continued = Self.mixedHarmonicSpeechPCM()"), realSpeechLong)
        XCTAssertFalse(realSpeechLong.contains("let continued = Self.speechShapedPCM"), realSpeechLong)
        XCTAssertFalse(realSpeechLong.contains("quietCommitMaxPostponeMs"), realSpeechLong)
        XCTAssertFalse(realSpeechLong.contains("emitUser"), realSpeechLong)
        XCTAssertFalse(realSpeechLong.contains("FakeLiveVoiceService"), realSpeechLong)
        XCTAssertFalse(realSpeechLong.contains("TapSpeechEnergy"), realSpeechLong)
        XCTAssertFalse(realSpeechLong.contains("QueuedTurnClose.shouldPostpone"), realSpeechLong)
        XCTAssertFalse(
            realSpeechLong.contains("commit belongs after the still-talking tail"),
            "3c7524b commit-after-tail is the flush-clock; later PCM is a new server-VAD turn"
        )
        if let openAt = realSpeechLong.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let continuedAt = realSpeechLong.range(of: "feedTapPCM16(continued)"),
           let waitAt = realSpeechLong.range(of: "waitUntilListenLoopQueuedTurnClosed") {
            XCTAssertLessThan(
                openAt.lowerBound,
                continuedAt.lowerBound,
                "long real-speech PCM must keep arriving after the session-ready flush"
            )
            XCTAssertLessThan(
                continuedAt.lowerBound,
                waitAt.lowerBound,
                "3c7524b paper-greens if we feed one frame and then wait"
            )
        } else {
            XCTFail("long real-speech gate must flush, keep feeding mixed-harmonic PCM, then require the queued command before commit")
        }
        let delayedCommand = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000DelayedCommandAfterRecoverIsNotTruncated",
            to: "func testLiveConversationLoopDidClose1000ThinkThenTalkAfterRecoverIsNotTruncated"
        )
        XCTAssertTrue(delayedCommand.contains("GrokVoiceService("), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("AppModel("), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("simulateListenLoopSocketClose1000"), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("feedTapPCM16(command2)"), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("simulateListenLoopSocketDidOpenThenSessionReady"), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("feedTapPCM16(noise)"), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("mixedHarmonicSpeechPCM"), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("feedTapPCM16(delayed)"), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("12a60a5"), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("firstDelayedAt"), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("lastDelayedAt"), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("input_audio_buffer.commit"), delayedCommand)
        XCTAssertTrue(delayedCommand.contains("interruptResponse"), delayedCommand)
        XCTAssertFalse(delayedCommand.contains("let delayed = Self.speechShapedPCM"), delayedCommand)
        XCTAssertFalse(delayedCommand.contains("emitUser"), delayedCommand)
        XCTAssertFalse(delayedCommand.contains("FakeLiveVoiceService"), delayedCommand)
        XCTAssertFalse(delayedCommand.contains("TapSpeechEnergy"), delayedCommand)
        XCTAssertFalse(delayedCommand.contains("QueuedTurnClose.shouldPostpone"), delayedCommand)
        if let openAt = delayedCommand.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let noiseAt = delayedCommand.range(of: "feedTapPCM16(noise)"),
           let delayedAt = delayedCommand.range(of: "feedTapPCM16(delayed)") {
            XCTAssertLessThan(
                openAt.lowerBound,
                noiseAt.lowerBound,
                "think / radio must follow the session-ready flush"
            )
            XCTAssertLessThan(
                noiseAt.lowerBound,
                delayedAt.lowerBound,
                "delayed command must follow ~2s of think / radio, not start at flush"
            )
        } else {
            XCTFail("delayed-command gate must flush, feed radio, then feed mixed-harmonic PCM")
        }
        let thinkThenTalk = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000ThinkThenTalkAfterRecoverIsNotTruncated",
            to: "private func waitUntilPending"
        )
        XCTAssertTrue(thinkThenTalk.contains("GrokVoiceService("), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("AppModel("), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("simulateListenLoopSocketClose1000"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("feedTapPCM16(command2)"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("simulateListenLoopSocketDidOpenThenSessionReady"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("feedTapPCM16(noise)"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("speechShapedPCM(hertz: 90)"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("mixedHarmonicSpeechPCM"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("feedTapPCM16(delayed)"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("5078dff"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("firstDelayedAt"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("lastDelayedAt"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("input_audio_buffer.commit"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("interruptResponse"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("engine.startCount"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("for _ in 0..<50"), thinkThenTalk)
        XCTAssertTrue(thinkThenTalk.contains("for _ in 0..<75"), thinkThenTalk)
        XCTAssertFalse(thinkThenTalk.contains("let delayed = Self.speechShapedPCM"), thinkThenTalk)
        XCTAssertFalse(thinkThenTalk.contains("applyUserTurn"), thinkThenTalk)
        XCTAssertFalse(thinkThenTalk.contains("emitUser"), thinkThenTalk)
        XCTAssertFalse(thinkThenTalk.contains("FakeLiveVoiceService"), thinkThenTalk)
        XCTAssertFalse(thinkThenTalk.contains("TapSpeechEnergy"), thinkThenTalk)
        XCTAssertFalse(thinkThenTalk.contains("QueuedTurnClose.shouldPostpone"), thinkThenTalk)
        XCTAssertFalse(thinkThenTalk.contains("quietCommitMaxPostponeMs"), thinkThenTalk)
        XCTAssertFalse(thinkThenTalk.contains("quietCommitArmedAt"), thinkThenTalk)
        if let openAt = thinkThenTalk.range(of: "simulateListenLoopSocketDidOpenThenSessionReady"),
           let noiseAt = thinkThenTalk.range(of: "feedTapPCM16(noise)"),
           let delayedAt = thinkThenTalk.range(of: "feedTapPCM16(delayed)") {
            XCTAssertLessThan(
                openAt.lowerBound,
                noiseAt.lowerBound,
                "think / radio must follow the session-ready flush"
            )
            XCTAssertLessThan(
                noiseAt.lowerBound,
                delayedAt.lowerBound,
                "think-then-talk must follow ~1s of think / radio, not start at flush"
            )
        } else {
            XCTFail("think-then-talk gate must flush, feed ~1s radio, then feed ≥1.5s mixed-harmonic PCM")
        }
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
