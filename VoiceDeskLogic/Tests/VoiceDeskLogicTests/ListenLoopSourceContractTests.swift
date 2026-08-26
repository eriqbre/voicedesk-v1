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
        XCTAssertTrue(service.contains("func simulateListenLoopSocketDidOpenThenSessionReady()"), service)
        XCTAssertTrue(service.contains("dropOutbound"), service)
        XCTAssertTrue(service.contains("markSessionReadyAndFlush"), service)
        let updated = speakSlice(service, from: "case .sessionUpdated:", to: "case .speechStarted:")
        XCTAssertTrue(updated.contains("markSessionReadyAndFlush"), updated)
        let didOpenService = speakSlice(service, from: "func grokWebSocketDidOpen()", to: "func grokWebSocketDidClose")
        XCTAssertTrue(didOpenService.contains("sendSessionUpdate"), didOpenService)
        XCTAssertFalse(
            didOpenService.contains("markSessionReadyAndFlush"),
            "DidOpen is not session-ready — 19c1b33 flushed too early"
        )
        let client = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoice.swift"))
        XCTAssertTrue(client.contains("outboundQueue"), client)
        XCTAssertTrue(client.contains("func attachTestSendTask()"), client)
        XCTAssertTrue(client.contains("func attachTestSendRecorder()"), client)
        XCTAssertTrue(client.contains("func markSessionReadyAndFlush()"), client)
        XCTAssertTrue(client.contains("func dropOutbound()"), client)
        let sendRaw = speakSlice(client, from: "func sendRaw(_ string: String) {", to: "func attachTestSendTask()")
        XCTAssertTrue(sendRaw.contains("sessionReady"), sendRaw)
        XCTAssertTrue(sendRaw.contains("isAudioAppend"), sendRaw)
        XCTAssertFalse(sendRaw.contains("task?.send"), sendRaw)
        let didOpen = speakSlice(client, from: "nonisolated func notifyOpen()", to: "nonisolated func notifyClose")
        XCTAssertFalse(
            didOpen.contains("outboundQueue"),
            "19c1b33 flushed the queue on notifyOpen before session.update"
        )
        XCTAssertFalse(didOpen.contains("task?.send"), didOpen)
        XCTAssertTrue(didOpen.contains("grokWebSocketDidOpen"), didOpen)
        let didClose = speakSlice(
            service,
            from: "func grokWebSocketDidClose",
            to: "func grokWebSocketDidFail"
        )
        XCTAssertTrue(didClose.contains("recoverAfterDrop"), didClose)
        XCTAssertFalse(
            didClose.contains("teardown"),
            "DidClose 1000 after desk TTS must not kill the one engine"
        )
        let recover = speakSlice(
            service,
            from: "private func recoverAfterDrop",
            to: "extension GrokVoiceService: LiveGrokVoiceClientDelegate"
        )
        XCTAssertTrue(recover.contains("connectAndConfigure"), recover)
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
            live.contains("testLiveConversationLoopDidClose1000AfterDrainNextCommandIsATurn"),
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
            to: "func testLiveConversationLoopDidClose1000AfterDrainNextCommandIsATurn"
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
        let close1000 = speakSlice(
            live,
            from: "func testLiveConversationLoopDidClose1000AfterDrainNextCommandIsATurn",
            to: "func testLiveConversationLoopDidClose1000DeadSocketWindowSendsQueuedCommand"
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
            to: "private func waitUntilPending"
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
