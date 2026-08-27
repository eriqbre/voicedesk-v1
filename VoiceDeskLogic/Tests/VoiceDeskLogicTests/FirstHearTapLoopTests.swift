import XCTest
@testable import VoiceDeskLogic

/// Tap-rate-during-playback is not first-hear. The third command PCM
/// after desk TTS drain must be a listen-path turn, or the walk is deaf.
/// fe1ffc8 / fa72e1c / 18d5878 / 415c955: tap detached, isRunning true,
/// startAudioIfNeeded no-ops — that walk must drop the third.
final class FirstHearTapLoopTests: XCTestCase {
    func testVersionThenGlanceWritePlayerThenThirdIsATurn() {
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.versionThenGlanceWritePlayerThenThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second, third])
        XCTAssertTrue(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertNotEqual(walk.close1000, .stayIdle, "close 1000 stayIdle after version/glance is a fail")
        XCTAssertEqual(walk.startCount, 1)
        XCTAssertFalse(ListenResumePolicy.shouldApplyGrokSpeakStarted(clientTTSSpeaking: true))
        XCTAssertFalse(ListenResumePolicy.shouldApplyGrokTurnFinished(clientTTSSpeaking: true))
        XCTAssertFalse(ListenInterrupt.isCommand("Can you hear me?"))
        XCTAssertFalse(ListenInterrupt.isCommand("and now the weather"))
        XCTAssertTrue(ListenInterrupt.isCommand("what's on my calendar"))
    }

    func testMixWithOthersAfterWritePlayerFails415c955AndProductLandsThird() {
        XCTAssertTrue(
            FirstHearTapLoop.sessionMixWithOthersDowngradesVPU(true),
            "415c955 startGraph mixWithOthers must fail this hole"
        )
        XCTAssertFalse(
            FirstHearTapLoop.sessionMixWithOthersDowngradesVPU(false),
            "product must not mixWithOthers after write→player"
        )
        XCTAssertFalse(
            FirstHearTapLoop.postTTSTapPCMIsAudible(
                mixWithOthers: true,
                sessionActive: true,
                tapInstalled: true
            ),
            "415c955 post-TTS tap PCM is zeros — tap stays, startCount stays 1"
        )
        XCTAssertTrue(
            FirstHearTapLoop.postTTSTapPCMIsAudible(
                mixWithOthers: false,
                sessionActive: true,
                tapInstalled: true
            ),
            "product exclusive session keeps post-TTS tap PCM audible"
        )
        XCTAssertFalse(
            FirstHearTapLoop.postTTSTapPCMIsAudible(
                mixWithOthers: false,
                sessionActive: false,
                tapInstalled: true
            ),
            "deferred setActive(false) after speak is a different hole"
        )
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let dead = FirstHearTapLoop.fe1ffc8Fa72e1c18d5878415c955MixWithOthersAfterWritePlayerDropsThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(
            dead.turns,
            [first, second],
            "415c955 mixWithOthers after write→player must drop the third"
        )
        XCTAssertTrue(dead.tapLive, "mixWithOthers is not a HAL yank — tap stays installed")
        XCTAssertEqual(dead.startCount, 1, "415c955 mixWithOthers must not audio.start")
        let walk = FirstHearTapLoop.noMixWithOthersAfterWritePlayerLandsThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second, third])
        XCTAssertTrue(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertEqual(walk.startCount, 1, "same live tap — no second engine.start")
    }

    func testProductThirdPCMAfterDrainIsATurnWithoutSecondStart() {
        // Product path: speakStarted slips during TTS, afterClientTTSFinished
        // returns to listen. Close 1000 stayIdle is a fail.
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.twoTurnsDeskTTSDrainThenThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second, third])
        XCTAssertTrue(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertNotEqual(walk.close1000, .stayIdle)
        XCTAssertEqual(walk.startCount, 1)
    }

    func testSpeakStartedDuringTTSThenDeafDropsTheThird() {
        let walk = FirstHearTapLoop.speakStartedDuringTTSDropsThird()
        XCTAssertEqual(walk.turns.count, 2, "first two land; after TTS the path is deaf")
        XCTAssertFalse(walk.listenArmed)
        XCTAssertEqual(walk.startCount, 1)
        XCTAssertNil(
            FirstHearTapLoop.accept(
                pcm: FirstHearTapLoop.commandPCM(3),
                tapLive: true,
                session: VoiceSession(state: .speaking),
                stayLive: true,
                startCount: 1
            ),
            "tap may still fire while session is speaking — that is not a turn"
        )
    }

    func testIdleClosedAfterTTSDropsTheThird() {
        let walk = FirstHearTapLoop.idleClosedAfterTTSDropsThird()
        XCTAssertEqual(walk.turns.count, 2, "keep-listen log is not hear proof")
        XCTAssertFalse(walk.stayLive)
        XCTAssertEqual(walk.close1000, .stayIdle)
        XCTAssertFalse(walk.listenArmed)
        XCTAssertEqual(walk.startCount, 1)
    }

    func testRearmAfterTTSWithoutSecondStartDropsTheThird() {
        let walk = FirstHearTapLoop.rearmAfterTTSDropsThird()
        XCTAssertEqual(walk.turns.count, 2)
        XCTAssertFalse(walk.tapLive)
        XCTAssertEqual(walk.startCount, 1, "second start was not taken; third must not land")
    }

    /// fe1ffc8 / fa72e1c / 18d5878 / 415c955: tap detached, isRunning
    /// true, startAudioIfNeeded no-ops. Third command PCM is not a turn.
    func testFe1ffc8Fa72e1c18d5878415c955DetachWhileRunningStartNoOpsDropsThird() {
        XCTAssertFalse(
            FirstHearTapLoop.startAudioIfNeededWouldStart(engineRunning: true),
            "415c955-class startAudioIfNeeded must no-op while isRunning"
        )
        XCTAssertTrue(FirstHearTapLoop.startAudioIfNeededWouldStart(engineRunning: false))
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.fe1ffc8Fa72e1c18d5878415c955DetachWhileRunningStartNoOpsDropsThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second], "detached tap + start no-op must drop the third")
        XCTAssertFalse(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertEqual(walk.startCount, 1)
        XCTAssertTrue(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: walk.tapLive, engineRunning: true)
        )
    }

    /// Product repair: same-engine reinstall, not a second audio.start.
    /// 415c955-class: close 1000 after TTS while listen was unarmed
    /// used stayLive=listenArmed → stayIdle. Third is not a turn.
    func testFe1ffc8Fa72e1c18d5878415c955Close1000AfterTTSStayIdleDropsThird() {
        XCTAssertFalse(
            ListenResumePolicy.sha415c955StayLiveAfterClose1000(
                userWantsVoiceOff: false,
                listenArmed: false
            ),
            "415c955 treated unarmed listen as stayLive=false"
        )
        let walk = FirstHearTapLoop.fe1ffc8Fa72e1c18d5878415c955Close1000AfterTTSStayIdleDropsThird()
        XCTAssertEqual(walk.turns.count, 2)
        XCTAssertFalse(walk.stayLive)
        XCTAssertEqual(walk.close1000, .stayIdle)
        XCTAssertFalse(walk.listenArmed)
        XCTAssertEqual(walk.startCount, 1)
    }

    /// Same close-1000-after-TTS event. Product must not stayIdle.
    func testFe1ffc8Fa72e1c18d5878415c955Close1000AfterTTSMustNotStayIdle() {
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.fe1ffc8Fa72e1c18d5878415c955Close1000AfterTTS(
            first: first,
            second: second,
            third: third
        )
        XCTAssertNotEqual(walk.close1000, .stayIdle, "close 1000 after desk TTS must not stayIdle")
        XCTAssertTrue(walk.stayLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.tapLive)
        XCTAssertEqual(walk.turns, [first, second, third])
        XCTAssertEqual(walk.startCount, 1)
        XCTAssertFalse(ListenResumePolicy.shouldApplyGrokSpeakStarted(clientTTSSpeaking: true))
        XCTAssertFalse(ListenResumePolicy.shouldApplyGrokTurnFinished(clientTTSSpeaking: true))
    }

    func testFe1ffc8Fa72e1c18d5878415c955DetachAfterTTSDrainNoInterruptionDropsThird() {
        XCTAssertFalse(
            FirstHearTapLoop.startAudioIfNeededWouldStart(engineRunning: true),
            "415c955-class startAudioIfNeeded must no-op while isRunning"
        )
        XCTAssertTrue(
            FirstHearTapLoop.shouldReinstallTapIfSilentWhileRunning(
                engineRunning: true,
                wantsCapture: true
            )
        )
        XCTAssertFalse(
            FirstHearTapLoop.bf0af19ShouldReinstallTapIfSilentWhileRunning(
                tapInstalled: true,
                engineRunning: true,
                wantsCapture: true
            ),
            "bf0af19 trusted tapInstalled and no-oped"
        )
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.fe1ffc8Fa72e1c18d5878415c955DetachAfterTTSDrainNoInterruptionDropsThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second], "415c955 waited for interruption and stayed deaf")
        XCTAssertFalse(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertEqual(walk.startCount, 1)
        XCTAssertTrue(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: walk.tapLive, engineRunning: true)
        )
    }

    func testBf0af19415c955FlagLiesAfterTTSDrainDropsThird() {
        XCTAssertFalse(
            FirstHearTapLoop.bf0af19ShouldReinstallTapIfSilentWhileRunning(
                tapInstalled: true,
                engineRunning: true,
                wantsCapture: true
            ),
            "bf0af19 / 415c955: flag still true after HAL yank"
        )
        XCTAssertTrue(
            FirstHearTapLoop.shouldReinstallTapIfSilentWhileRunning(
                engineRunning: true,
                wantsCapture: true
            ),
            "product must reinstall even when the flag still says installed"
        )
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.bf0af19415c955FlagLiesAfterTTSDrainDropsThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second], "bf0af19 trusted the flag and stayed deaf")
        XCTAssertFalse(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertEqual(walk.startCount, 1)
        XCTAssertTrue(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: walk.tapLive, engineRunning: true)
        )
    }

    func testFlagLiesAfterTTSDrainThenReinstallLandsThird() {
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.flagLiesAfterTTSDrainThenReinstallSameTap(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second, third])
        XCTAssertTrue(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertEqual(walk.startCount, 1, "reinstall must not audio.start")
        XCTAssertFalse(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: walk.tapLive, engineRunning: true)
        )
    }

    func testDrainOnly573f654DelayedYankAfterReturnToListenDropsThird() {
        XCTAssertFalse(
            FirstHearTapLoop.startAudioIfNeededWouldStart(engineRunning: true),
            "415c955-class startAudioIfNeeded must no-op while isRunning"
        )
        XCTAssertTrue(
            FirstHearTapLoop.shouldReinstallTapIfSilentWhileRunning(
                engineRunning: true,
                wantsCapture: true
            ),
            "573f654 drain-time repair would run while the tap is still live"
        )
        var interrupted = false
        XCTAssertEqual(
            AudioTapLifecycle.action(
                for: .engineConfigurationChanged,
                wantsCapture: true,
                isInterrupted: &interrupted
            ),
            .reinstallTap,
            "product recovery is configuration change, not a second drain repair"
        )
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.drainOnly573f654DelayedYankAfterReturnToListenDropsThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second], "drain-only 573f654 misses a yank after returnToListen")
        XCTAssertFalse(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertEqual(walk.startCount, 1)
        XCTAssertTrue(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: walk.tapLive, engineRunning: true)
        )
    }

    func testDelayedYankAfterReturnToListenThenConfigChangeLandsThird() {
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.delayedYankAfterReturnToListenThenConfigChangeReinstallsSameTap(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second, third])
        XCTAssertTrue(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertEqual(walk.startCount, 1, "config-change reinstall must not audio.start")
        XCTAssertFalse(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: walk.tapLive, engineRunning: true)
        )
    }

    func testDelayedYankAfterReturnToListenThenDelayedRepairLandsThird() {
        XCTAssertFalse(
            FirstHearTapLoop.shouldApplyDelayedSilentTapRepair(
                engineRunning: true,
                wantsCapture: true,
                tapObjectMissing: false
            ),
            "healthy tap must not be torn down — that raced leftover barge"
        )
        XCTAssertTrue(
            FirstHearTapLoop.shouldApplyDelayedSilentTapRepair(
                engineRunning: true,
                wantsCapture: true,
                tapObjectMissing: true
            ),
            "HAL yank leaves tap nil — demand-driven reinstall puts it back"
        )
        XCTAssertFalse(
            FirstHearTapLoop.shouldApplyDelayedSilentTapRepair(
                engineRunning: true,
                wantsCapture: true,
                tapObjectMissing: false,
                halTapMissing: false
            ),
            "healthy HAL tap must not be torn down — leftover barge"
        )
        XCTAssertTrue(
            FirstHearTapLoop.shouldApplyDelayedSilentTapRepair(
                engineRunning: true,
                wantsCapture: true,
                tapObjectMissing: false,
                halTapMissing: true
            ),
            "object-left-in-place silent yank — 453bda8 tap==nil only misses this"
        )
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.delayedYankAfterReturnToListenThenDelayedRepairLandsThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second, third])
        XCTAssertTrue(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertEqual(walk.startCount, 1, "delayed silent-tap reinstall must not audio.start")
        XCTAssertFalse(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: walk.tapLive, engineRunning: true)
        )
    }

    func testObjectLeftInPlaceSilentYankThenDemandRepairLandsThird() {
        XCTAssertFalse(
            FirstHearTapLoop.shouldApplyDelayedSilentTapRepair(
                engineRunning: true,
                wantsCapture: true,
                tapObjectMissing: false
            ),
            "453bda8 tap==nil-only repair must not green object-left-in-place silence"
        )
        XCTAssertFalse(
            FirstHearTapLoop.shouldApplyDelayedSilentTapRepair(
                engineRunning: true,
                wantsCapture: true,
                tapObjectMissing: false,
                halTapMissing: false
            ),
            "771f6f9 inject-storage-bit-only must fail this hole"
        )
        XCTAssertFalse(
            FirstHearTapLoop.startAudioIfNeededWouldStart(engineRunning: true),
            "415c955 start no-ops — that is not the repair"
        )
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let bitOnly = FirstHearTapLoop.objectLeftInPlace415c955BitOnly771f6f9RepairDropsThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(
            bitOnly.turns,
            [first, second],
            "415c955 / bit-only 771f6f9 repair must drop the third"
        )
        XCTAssertFalse(bitOnly.tapLive, "bit-only repair must leave the tap dead")
        XCTAssertEqual(bitOnly.startCount, 1, "415c955 start no-ops must not audio.start")
        let walk = FirstHearTapLoop.objectLeftInPlaceSilentYankThenDemandRepairLandsThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second, third])
        XCTAssertTrue(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertEqual(walk.startCount, 1, "object-left-in-place repair must not audio.start")
        XCTAssertFalse(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: walk.tapLive, engineRunning: true)
        )
    }

    func testDetachAfterTTSDrainNoInterruptionThenReinstallLandsThird() {
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.detachAfterTTSDrainNoInterruptionThenReinstallSameTap(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second, third])
        XCTAssertTrue(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertEqual(walk.startCount, 1, "reinstall must not audio.start")
        XCTAssertFalse(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: walk.tapLive, engineRunning: true)
        )
    }

    func testDetachWhileRunningThenReinstallSameTapLandsThird() {
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.detachWhileRunningThenReinstallSameTap(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second, third])
        XCTAssertTrue(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertEqual(walk.startCount, 1, "reinstall must not audio.start")
        XCTAssertFalse(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: walk.tapLive, engineRunning: true)
        )
    }

    func testSilentTapWhileEngineRunningIsTheLie() {
        XCTAssertTrue(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: false, engineRunning: true)
        )
        XCTAssertFalse(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: true, engineRunning: true)
        )
        XCTAssertFalse(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: false, engineRunning: false)
        )
    }

    func testAcceptRequiresListenArmedStayLiveAndOneStart() {
        var session = VoiceSession()
        session.apply(.tapTalk)
        let pcm = FirstHearTapLoop.commandPCM(9)
        XCTAssertEqual(
            FirstHearTapLoop.accept(
                pcm: pcm,
                tapLive: true,
                session: session,
                stayLive: true,
                startCount: 1
            ),
            pcm
        )
        XCTAssertNil(
            FirstHearTapLoop.accept(
                pcm: pcm,
                tapLive: true,
                session: session,
                stayLive: true,
                startCount: 2
            )
        )
        XCTAssertNil(
            FirstHearTapLoop.accept(
                pcm: pcm,
                tapLive: false,
                session: session,
                stayLive: true,
                startCount: 1
            )
        )
        XCTAssertNil(
            FirstHearTapLoop.accept(
                pcm: pcm,
                tapLive: true,
                session: session,
                stayLive: false,
                startCount: 1
            )
        )
    }
}
