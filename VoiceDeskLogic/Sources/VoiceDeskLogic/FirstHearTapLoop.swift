import Foundation

/// Hear-proof first-hear: command PCM through the tap is a turn only
/// while listen is still armed. Tap-rate-during-playback is not enough.
/// After desk TTS drain, the next PCM must be accepted without a second start.
public struct FirstHearTapLoop: Equatable, Sendable {
    public var turns: [Data]
    public var tapLive: Bool
    public var listenArmed: Bool
    public var stayLive: Bool
    public var close1000: ListenResumeDecision
    public var startCount: Int

    public init(
        turns: [Data],
        tapLive: Bool,
        listenArmed: Bool,
        stayLive: Bool,
        close1000: ListenResumeDecision,
        startCount: Int
    ) {
        self.turns = turns
        self.tapLive = tapLive
        self.listenArmed = listenArmed
        self.stayLive = stayLive
        self.close1000 = close1000
        self.startCount = startCount
    }

    /// `engine.isRunning` with no buffers after TTS is first-hear-then-deaf.
    public static func silentTapWhileEngineRunning(tapEmitting: Bool, engineRunning: Bool) -> Bool {
        engineRunning && !tapEmitting
    }

    /// After drain. Silent tap while running must reinstall the same tap.
    /// Do not trust `tapInstalled` — real iOS yanks the HAL tap and
    /// leaves the flag true. Do not wait for interruption. Do not start
    /// a second engine.
    public static func shouldReinstallTapIfSilentWhileRunning(
        engineRunning: Bool,
        wantsCapture: Bool
    ) -> Bool {
        wantsCapture && engineRunning
    }

    /// Zero-notification HAL yank. Reinstall if the Swift tap object
    /// is gone *or* HAL released the installTap block (object stays).
    /// `tapObjectMissing` only is 453bda8 — that misses the phone.
    /// `halTapMissing` is install-block released, not an inject
    /// storage bit (771f6f9). A healthy HAL tap must not be torn
    /// down. Not a timer.
    public static func shouldApplyDelayedSilentTapRepair(
        engineRunning: Bool,
        wantsCapture: Bool,
        tapObjectMissing: Bool,
        halTapMissing: Bool = false
    ) -> Bool {
        wantsCapture && engineRunning && (tapObjectMissing || halTapMissing)
    }

    /// bf0af19 / 415c955: trusted `tapInstalled`. HAL yank left the
    /// flag true, so the repair no-oped and the third never landed.
    public static func bf0af19ShouldReinstallTapIfSilentWhileRunning(
        tapInstalled: Bool,
        engineRunning: Bool,
        wantsCapture: Bool
    ) -> Bool {
        wantsCapture && engineRunning && !tapInstalled
    }

    /// Command-shaped PCM is a turn only if the listen path can still hear.
    /// A live tap callback with session idle / speaking is first-hear-then-deaf.
    public static func accept(
        pcm: Data,
        tapLive: Bool,
        session: VoiceSession,
        stayLive: Bool,
        startCount: Int
    ) -> Data? {
        guard tapLive, stayLive, startCount == 1 else { return nil }
        guard ListenResumePolicy.isListenArmed(state: session.state) else { return nil }
        return pcm
    }

    public static func commandPCM(_ tag: UInt8) -> Data {
        Data([tag, 0x24, 0xC0, 0xDE, tag])
    }

    /// Product: two tap turns, write→player drain, return to listen
    /// (`afterClientTTSFinished`). A slipped `speakStarted` must not leave
    /// the third unarmed. Close 1000 stayIdle is a fail. No second start.
    public static func twoTurnsDeskTTSDrainThenThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .applySpeakStarted,
            afterDrain: .returnToListenAfterTTS
        )
    }

    /// speakStarted during TTS, no keep-listen after drain. Third PCM is not a turn.
    public static func speakStartedDuringTTSDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .applySpeakStarted,
            afterDrain: .doNothing
        )
    }

    /// Session idle-closed after TTS. Tap may still fire; third PCM is not a turn.
    public static func idleClosedAfterTTSDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .idleClose
        )
    }

    /// Rearm / second start after TTS. Without that start, third PCM is not a turn.
    public static func rearmAfterTTSDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .rearmWithoutStart
        )
    }

    /// Same guard as 415c955 / 18d5878 / fa72e1c / fe1ffc8 `startAudioIfNeeded`:
    /// `guard !userWantsVoiceOff, !audio.isRunning else { return }`.
    /// Used by the SHA fixture so a revert to that loop drops the third.
    public static func startAudioIfNeededWouldStart(
        engineRunning: Bool,
        userWantsVoiceOff: Bool = false
    ) -> Bool {
        !userWantsVoiceOff && !engineRunning
    }

    /// fe1ffc8 / fa72e1c / 18d5878 / 415c955: iOS detached the tap,
    /// `engine.isRunning` stayed true, `startAudioIfNeeded` no-ops.
    /// Third command PCM is not a turn. Trees are not replayed; this
    /// is the failure mode those SHAs paper-greened.
    public static func fe1ffc8Fa72e1c18d5878415c955DetachWhileRunningStartNoOpsDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .detachWhileRunningStartNoOps
        )
    }

    /// fe1ffc8 / fa72e1c / 18d5878 / 415c955: close 1000 after desk TTS
    /// while listen was unarmed. stayLive was listen-armed → stayIdle.
    /// Third command PCM is not a turn.
    public static func fe1ffc8Fa72e1c18d5878415c955Close1000AfterTTSStayIdleDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .applySpeakStarted,
            afterDrain: .close1000AfterTTSStayIdle
        )
    }

    /// Product path for the 415c955-class close-1000-after-TTS event.
    /// Leftover response.created/done must not park speaking. Close 1000
    /// must stayLive and re-listen on the same tap. stayIdle is a fail.
    public static func fe1ffc8Fa72e1c18d5878415c955Close1000AfterTTS(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        close1000AfterTTSStayLiveThenThird(first: first, second: second, third: third)
    }

    /// AppModel version then glance write→player, then the next command.
    /// Same live loop as `GrokVoiceService.returnToListenAfterDeskTTS`.
    /// Close 1000 stayIdle is a fail. `startCount` stays 1.
    public static func versionThenGlanceWritePlayerThenThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3),
        mixWithOthersAfterWritePlayer: Bool = false,
        deferredSetActiveFalseAfterWritePlayer: Bool = false,
        a2dpOnlyAfterWritePlayer: Bool = false
    ) -> FirstHearTapLoop {
        var session = VoiceSession()
        session.apply(.tapTalk)
        var tapLive = true
        var stayLive = true
        var startCount = 1
        var turns: [Data] = []
        var close1000 = ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: false,
            sessionShouldStayLive: true,
            closeCode: 1000,
            voiceState: session.state
        )

        func take(_ pcm: Data) {
            if let accepted = accept(
                pcm: pcm,
                tapLive: tapLive,
                session: session,
                stayLive: stayLive,
                startCount: startCount
            ) {
                turns.append(accepted)
            }
        }

        take(first)
        var after = ListenResumePolicy.afterClientTTSFinished(
            session: &session,
            userWantsVoiceOff: false,
            liveSessionArmed: true,
            captureRunning: tapLive
        )
        stayLive = after.stayLive
        close1000 = after.close1000
        if after.startAgain {
            startCount += 1
        }

        take(second)
        after = ListenResumePolicy.afterClientTTSFinished(
            session: &session,
            userWantsVoiceOff: false,
            liveSessionArmed: true,
            captureRunning: tapLive
        )
        stayLive = after.stayLive
        close1000 = after.close1000
        if after.startAgain {
            startCount += 1
        }

        if postTTSTapPCMIsAudible(
            mixWithOthers: mixWithOthersAfterWritePlayer,
            sessionActive: !deferredSetActiveFalseAfterWritePlayer,
            tapInstalled: tapLive,
            a2dpOnly: a2dpOnlyAfterWritePlayer
        ) {
            take(third)
        }
        return FirstHearTapLoop(
            turns: turns,
            tapLive: tapLive,
            listenArmed: ListenResumePolicy.isListenArmed(state: session.state),
            stayLive: stayLive,
            close1000: close1000,
            startCount: startCount
        )
    }

    /// 415c955 `startGraph` activated with `.mixWithOthers`. After
    /// write→player the VPU is downgraded. The tap stays installed,
    /// `startCount` stays 1, session stays playAndRecord — post-TTS
    /// tap PCM is zeros. Not a HAL yank. Third is not a turn.
    public static func sessionMixWithOthersDowngradesVPU(_ mixWithOthers: Bool) -> Bool {
        mixWithOthers
    }

    /// voiceChat category/mode is not AEC. VP must be enabled while
    /// the engine is stopped, before installTap / start.
    public static func voiceChatWithoutVoiceProcessingIsNotAEC(
        voiceChat: Bool,
        voiceProcessingEnabledWhileStopped: Bool
    ) -> Bool {
        voiceChat && !voiceProcessingEnabledWhileStopped
    }

    /// Command PCM after write→player is audible only while the
    /// session stays exclusive. `.mixWithOthers` leaves the tap up
    /// and feeds zeros.
    public static func postTTSTapPCMIsAudible(
        mixWithOthers: Bool,
        sessionActive: Bool,
        tapInstalled: Bool,
        a2dpOnly: Bool = false,
        tapEmitting: Bool = true
    ) -> Bool {
        tapInstalled && sessionActive && !mixWithOthers && !a2dpOnly && tapEmitting
    }

    /// 552ef0c after first write→player (version line): `isRunning` +
    /// listenArmed/stayLive stayed true while the tap rate was zero.
    /// That lie must fail. ~21s later DidClose 1000 stayIdle.
    public static func stayLiveFlagsLieWhenTapSilentAfterVersionTTS(
        engineRunning: Bool,
        listenArmed: Bool,
        stayLive: Bool,
        tapEmitting: Bool
    ) -> Bool {
        silentTapWhileEngineRunning(tapEmitting: tapEmitting, engineRunning: engineRunning)
            && listenArmed
            && stayLive
    }

    /// First write→player desk TTS (version line), then the next command.
    /// Silent tap after drain while flags stay live is 552ef0c: next is
    /// not a turn, then DidClose 1000 stayIdle. Product keeps the same
    /// tap emitting. `startCount` stays 1. Not a HAL yank.
    public static func versionWritePlayerThenNextCommand(
        first: Data = commandPCM(1),
        next: Data = commandPCM(2),
        silentTapAfterWritePlayer: Bool = false
    ) -> FirstHearTapLoop {
        var session = VoiceSession()
        session.apply(.tapTalk)
        var tapLive = true
        var stayLive = true
        var startCount = 1
        var turns: [Data] = []
        var close1000 = ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: false,
            sessionShouldStayLive: true,
            closeCode: 1000,
            voiceState: session.state
        )

        func take(_ pcm: Data) {
            if let accepted = accept(
                pcm: pcm,
                tapLive: tapLive,
                session: session,
                stayLive: stayLive,
                startCount: startCount
            ) {
                turns.append(accepted)
            }
        }

        take(first)
        let after = ListenResumePolicy.afterClientTTSFinished(
            session: &session,
            userWantsVoiceOff: false,
            liveSessionArmed: true,
            captureRunning: tapLive
        )
        stayLive = after.stayLive
        close1000 = after.close1000
        if after.startAgain {
            startCount += 1
        }

        if silentTapAfterWritePlayer {
            close1000 = .stayIdle
        } else if postTTSTapPCMIsAudible(
            mixWithOthers: false,
            sessionActive: true,
            tapInstalled: tapLive,
            tapEmitting: true
        ) {
            take(next)
        }
        return FirstHearTapLoop(
            turns: turns,
            tapLive: tapLive,
            listenArmed: ListenResumePolicy.isListenArmed(state: session.state),
            stayLive: stayLive,
            close1000: close1000,
            startCount: startCount
        )
    }

    /// 552ef0c: version write→player, flags stay live, tap rate zero.
    /// Next command is not a turn. Then DidClose 1000 stayIdle.
    public static func sha552ef0cSilentTapAfterVersionWritePlayerDropsNext(
        first: Data = commandPCM(1),
        next: Data = commandPCM(2)
    ) -> FirstHearTapLoop {
        versionWritePlayerThenNextCommand(
            first: first,
            next: next,
            silentTapAfterWritePlayer: true
        )
    }

    /// Product: same version write→player, one tap still emitting.
    /// Next command PCM through that tap is the next turn. Not stayIdle.
    public static func noSilentTapAfterVersionWritePlayerLandsNext(
        first: Data = commandPCM(1),
        next: Data = commandPCM(2)
    ) -> FirstHearTapLoop {
        versionWritePlayerThenNextCommand(
            first: first,
            next: next,
            silentTapAfterWritePlayer: false
        )
    }

    /// 415c955 `startGraph` used `.allowBluetoothA2DP` without
    /// `.allowBluetooth`. A2DP is output-only. After write→player a
    /// headset / VPU route can leave input silent — tap stays,
    /// `startCount` stays 1, post-TTS tap PCM is zeros. Not a HAL yank.
    public static func sessionA2DPOnlySilencesInput(
        allowBluetoothA2DP: Bool,
        allowBluetooth: Bool
    ) -> Bool {
        allowBluetoothA2DP && !allowBluetooth
    }

    /// 415c955: version + glance write→player, mixWithOthers still on
    /// the session. Tap stays. `startCount` stays 1. Third is zeros.
    public static func fe1ffc8Fa72e1c18d5878415c955MixWithOthersAfterWritePlayerDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        versionThenGlanceWritePlayerThenThird(
            first: first,
            second: second,
            third: third,
            mixWithOthersAfterWritePlayer: true
        )
    }

    /// Product: same write→player walk without mixWithOthers. Third
    /// command PCM through the same live tap is the next turn.
    public static func noMixWithOthersAfterWritePlayerLandsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        versionThenGlanceWritePlayerThenThird(
            first: first,
            second: second,
            third: third,
            mixWithOthersAfterWritePlayer: false
        )
    }

    /// 415c955 `stop()` deferred `setActive(false)` 100ms later with
    /// no wantsCapture guard. AVSpeech `usesApplicationAudioSession
    /// = true` is the same teardown after write. Tap stays.
    /// `startCount` stays 1. Session inactive — third PCM is zeros.
    /// Not a HAL yank. Not mixWithOthers.
    public static func sessionDeferredDeactivateAfterSpeakSilencesLive(
        _ deactivated: Bool
    ) -> Bool {
        deactivated
    }

    /// 415c955: version + glance write→player, then deferred
    /// setActive(false) (or AVSpeech equivalent) mutes the live
    /// session. Tap stays. `startCount` stays 1. Third is zeros.
    public static func fe1ffc8Fa72e1c18d5878415c955DeferredSetActiveFalseAfterWritePlayerDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        versionThenGlanceWritePlayerThenThird(
            first: first,
            second: second,
            third: third,
            deferredSetActiveFalseAfterWritePlayer: true
        )
    }

    /// Product: same write→player walk without a deferred deactivate.
    /// Third command PCM through the same live tap is the next turn.
    public static func noDeferredSetActiveFalseAfterWritePlayerLandsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        versionThenGlanceWritePlayerThenThird(
            first: first,
            second: second,
            third: third,
            deferredSetActiveFalseAfterWritePlayer: false
        )
    }

    /// 415c955: version + glance write→player, A2DP-only (no HFP).
    /// Tap stays. `startCount` stays 1. Third is zeros. Not mixWithOthers.
    /// Not deferred deactivate. Not a HAL yank.
    public static func fe1ffc8Fa72e1c18d5878415c955A2DPOnlyAfterWritePlayerDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        versionThenGlanceWritePlayerThenThird(
            first: first,
            second: second,
            third: third,
            a2dpOnlyAfterWritePlayer: true
        )
    }

    /// Product: same write→player walk with HFP (`.allowBluetooth`), no
    /// A2DP-only. Third command PCM through the same live tap is the next turn.
    public static func noA2DPOnlyAfterWritePlayerLandsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        versionThenGlanceWritePlayerThenThird(
            first: first,
            second: second,
            third: third,
            a2dpOnlyAfterWritePlayer: false
        )
    }

    /// Product: leftover response.created/done during TTS, then close 1000.
    /// stayLive after drain is armed + running, not a stuck TTS flag.
    /// Listen is re-armed on the same tap. Third lands. stayIdle is a fail.
    public static func close1000AfterTTSStayLiveThenThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .leftoverGrokSpeakAndDone,
            afterDrain: .close1000AfterTTSStayLive
        )
    }

    /// fe1ffc8 / fa72e1c / 18d5878 / 415c955 after write→player drain:
    /// tap yanked, `isRunning` true, no interruption, start no-ops.
    /// Third command PCM is not a turn.
    public static func fe1ffc8Fa72e1c18d5878415c955DetachAfterTTSDrainNoInterruptionDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .detachAfterTTSDrainNoInterruption
        )
    }

    /// After write→player drain, silent tap while running, no interruption.
    /// Same-engine reinstall. Third command PCM is the next turn.
    /// `startCount` stays 1.
    public static func detachAfterTTSDrainNoInterruptionThenReinstallSameTap(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .detachAfterTTSDrainNoInterruptionThenReinstall
        )
    }

    /// bf0af19 / 415c955: HAL tap yanked after drain, installed flag
    /// still true, start no-ops, old repair no-ops. Third is not a turn.
    public static func bf0af19415c955FlagLiesAfterTTSDrainDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .flagLiesAfterTTSDrain
        )
    }

    /// After drain, HAL yank leaves the installed flag true. Product
    /// reinstalls anyway. Third command PCM is the next turn.
    public static func flagLiesAfterTTSDrainThenReinstallSameTap(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .flagLiesAfterTTSDrainThenReinstall
        )
    }

    /// 573f654 / 415c955: drain-time repair ran while the tap was
    /// still live. A beat later HAL yanked it, flag still true, no
    /// interruption, no configuration change. start no-ops. Third
    /// is not a turn.
    public static func drainOnly573f654DelayedYankAfterReturnToListenDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .drainThenDelayedYankNoConfigChange
        )
    }

    /// After drain + 573f654 repair, delayed HAL yank (flag still
    /// true, no interruption). Configuration change reinstalls the
    /// same tap. Third command PCM is the next turn. `startCount` stays 1.
    public static func delayedYankAfterReturnToListenThenConfigChangeReinstallsSameTap(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .drainThenDelayedYankThenConfigChange
        )
    }

    /// Drain-time repair ran while the tap was live. Delayed HAL yank
    /// with zero notifications. Demand-driven reinstall when the tap
    /// object is gone puts the same tap back. Third command PCM is
    /// the next turn. Not a 400ms Task.
    /// 453bda8: tap==nil only. Phone yank leaves the object.
    public static func delayedYankAfterReturnToListenThenDelayedRepairLandsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .drainThenDelayedYankThenDelayedRepair
        )
    }

    /// Phone HAL yank: object stays, HAL released the install block.
    /// 415c955 start no-ops. 453bda8 tap==nil repair no-ops.
    /// 771f6f9 inject-bit-only no-ops. Third is not a turn.
    public static func objectLeftInPlace415c955BitOnly771f6f9RepairDropsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .drainThenObjectLeftInPlaceYankBitOnlyRepair
        )
    }

    /// Phone HAL yank: object stays, HAL released the install block.
    /// 453bda8 tap==nil repair no-ops. 771f6f9 inject-bit-only no-ops.
    /// Demand-driven install-block-released repair lands the third.
    /// Not a 400ms Task.
    public static func objectLeftInPlaceSilentYankThenDemandRepairLandsThird(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .drainThenObjectLeftInPlaceYankThenDemandRepair
        )
    }

    /// Product: same detach, then same-engine reinstall (not `audio.start`).
    /// Third command PCM is the next turn. `startCount` stays 1.
    public static func detachWhileRunningThenReinstallSameTap(
        first: Data = commandPCM(1),
        second: Data = commandPCM(2),
        third: Data = commandPCM(3)
    ) -> FirstHearTapLoop {
        run(
            first: first,
            second: second,
            third: third,
            duringTTS: .keepListening,
            afterDrain: .detachWhileRunningThenReinstall
        )
    }

    private enum DuringTTS {
        case keepListening
        case applySpeakStarted
        case leftoverGrokSpeakAndDone
    }

    private enum AfterDrain {
        case doNothing
        case idleClose
        case rearmWithoutStart
        case detachWhileRunningStartNoOps
        case detachWhileRunningThenReinstall
        case detachAfterTTSDrainNoInterruption
        case detachAfterTTSDrainNoInterruptionThenReinstall
        case flagLiesAfterTTSDrain
        case flagLiesAfterTTSDrainThenReinstall
        case drainThenDelayedYankNoConfigChange
        case drainThenDelayedYankThenConfigChange
        case drainThenDelayedYankThenDelayedRepair
        case drainThenObjectLeftInPlaceYankBitOnlyRepair
        case drainThenObjectLeftInPlaceYankThenDemandRepair
        case returnToListenAfterTTS
        case close1000AfterTTSStayIdle
        case close1000AfterTTSStayLive
    }

    private static func run(
        first: Data,
        second: Data,
        third: Data,
        duringTTS: DuringTTS,
        afterDrain: AfterDrain
    ) -> FirstHearTapLoop {
        var session = VoiceSession()
        session.apply(.tapTalk)
        var tapLive = true
        var stayLive = true
        var startCount = 1
        var turns: [Data] = []
        var close1000 = ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: false,
            sessionShouldStayLive: true,
            closeCode: 1000,
            voiceState: session.state
        )

        func take(_ pcm: Data) {
            if let accepted = accept(
                pcm: pcm,
                tapLive: tapLive,
                session: session,
                stayLive: stayLive,
                startCount: startCount
            ) {
                turns.append(accepted)
            }
        }

        take(first)
        take(second)

        switch duringTTS {
        case .keepListening:
            break
        case .applySpeakStarted:
            session.apply(.speakStarted)
        case .leftoverGrokSpeakAndDone:
            break
        }

        switch afterDrain {
        case .doNothing:
            break
        case .idleClose:
            session.apply(.speakStarted)
            session.apply(.speakFinished)
            stayLive = ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: false,
                audioStarted: false
            )
            close1000 = ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: stayLive,
                closeCode: 1000,
                voiceState: session.state
            )
        case .rearmWithoutStart:
            tapLive = false
        case .detachWhileRunningStartNoOps:
            tapLive = false
            if startAudioIfNeededWouldStart(engineRunning: true) {
                startCount += 1
                tapLive = true
            }
        case .detachWhileRunningThenReinstall:
            tapLive = false
            tapLive = true
        case .detachAfterTTSDrainNoInterruption, .detachAfterTTSDrainNoInterruptionThenReinstall:
            let after = ListenResumePolicy.afterClientTTSFinished(
                session: &session,
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                captureRunning: tapLive
            )
            stayLive = after.stayLive
            close1000 = after.close1000
            if after.startAgain {
                startCount += 1
            }
            tapLive = false
            if startAudioIfNeededWouldStart(engineRunning: true) {
                startCount += 1
                tapLive = true
            }
            if afterDrain == .detachAfterTTSDrainNoInterruptionThenReinstall,
               shouldReinstallTapIfSilentWhileRunning(
                engineRunning: true,
                wantsCapture: true
               ) {
                tapLive = true
            }
        case .flagLiesAfterTTSDrain, .flagLiesAfterTTSDrainThenReinstall:
            let after = ListenResumePolicy.afterClientTTSFinished(
                session: &session,
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                captureRunning: true
            )
            stayLive = after.stayLive
            close1000 = after.close1000
            if after.startAgain {
                startCount += 1
            }
            // HAL yank. Installed flag stays true. Actual tap is dead.
            let flagInstalled = true
            tapLive = false
            if startAudioIfNeededWouldStart(engineRunning: true) {
                startCount += 1
                tapLive = true
            }
            let oldRepair = bf0af19ShouldReinstallTapIfSilentWhileRunning(
                tapInstalled: flagInstalled,
                engineRunning: true,
                wantsCapture: true
            )
            let productRepair = shouldReinstallTapIfSilentWhileRunning(
                engineRunning: true,
                wantsCapture: true
            )
            if afterDrain == .flagLiesAfterTTSDrainThenReinstall, productRepair {
                tapLive = true
            } else if oldRepair {
                tapLive = true
            }
        case .drainThenDelayedYankNoConfigChange, .drainThenDelayedYankThenConfigChange, .drainThenDelayedYankThenDelayedRepair, .drainThenObjectLeftInPlaceYankBitOnlyRepair, .drainThenObjectLeftInPlaceYankThenDemandRepair:
            // 573f654: returnToListen + reinstall while the tap is still live.
            let after = ListenResumePolicy.afterClientTTSFinished(
                session: &session,
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                captureRunning: tapLive
            )
            stayLive = after.stayLive
            close1000 = after.close1000
            if after.startAgain {
                startCount += 1
            }
            if shouldReinstallTapIfSilentWhileRunning(
                engineRunning: true,
                wantsCapture: true
            ) {
                tapLive = true
            }
            // Delayed HAL yank AFTER drain-time repair. Flag stays true.
            tapLive = false
            if startAudioIfNeededWouldStart(engineRunning: true) {
                startCount += 1
                tapLive = true
            }
            if afterDrain == .drainThenDelayedYankThenConfigChange {
                var interrupted = false
                if AudioTapLifecycle.action(
                    for: .engineConfigurationChanged,
                    wantsCapture: true,
                    isInterrupted: &interrupted
                ) == .reinstallTap {
                    tapLive = true
                }
            }
            if afterDrain == .drainThenDelayedYankThenDelayedRepair,
               shouldApplyDelayedSilentTapRepair(
                engineRunning: true,
                wantsCapture: true,
                tapObjectMissing: !tapLive
               ) {
                tapLive = true
            }
            if afterDrain == .drainThenObjectLeftInPlaceYankBitOnlyRepair
                || afterDrain == .drainThenObjectLeftInPlaceYankThenDemandRepair {
                let onlyNilObject = shouldApplyDelayedSilentTapRepair(
                    engineRunning: true,
                    wantsCapture: true,
                    tapObjectMissing: false
                )
                let bitOnly = shouldApplyDelayedSilentTapRepair(
                    engineRunning: true,
                    wantsCapture: true,
                    tapObjectMissing: false,
                    halTapMissing: false
                )
                if onlyNilObject || bitOnly {
                    tapLive = true
                } else if afterDrain == .drainThenObjectLeftInPlaceYankThenDemandRepair,
                          shouldApplyDelayedSilentTapRepair(
                    engineRunning: true,
                    wantsCapture: true,
                    tapObjectMissing: false,
                    halTapMissing: true
                          ) {
                    tapLive = true
                }
            }
        case .returnToListenAfterTTS:
            let after = ListenResumePolicy.afterClientTTSFinished(
                session: &session,
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                captureRunning: tapLive
            )
            stayLive = after.stayLive
            close1000 = after.close1000
            if after.startAgain {
                startCount += 1
            }
        case .close1000AfterTTSStayIdle:
            stayLive = ListenResumePolicy.sha415c955StayLiveAfterClose1000(
                userWantsVoiceOff: false,
                listenArmed: ListenResumePolicy.isListenArmed(state: session.state)
            )
            close1000 = ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: stayLive,
                closeCode: 1000,
                voiceState: session.state
            )
        case .close1000AfterTTSStayLive:
            let after = ListenResumePolicy.afterClientTTSFinished(
                session: &session,
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                captureRunning: tapLive
            )
            stayLive = ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                audioStarted: tapLive,
                clientTTSInFlight: false
            )
            close1000 = ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: stayLive,
                closeCode: 1000,
                voiceState: session.state,
                liveSessionArmed: true
            )
            if after.startAgain {
                startCount += 1
            }
        }

        take(third)

        return FirstHearTapLoop(
            turns: turns,
            tapLive: tapLive,
            listenArmed: ListenResumePolicy.isListenArmed(state: session.state),
            stayLive: stayLive,
            close1000: close1000,
            startCount: startCount
        )
    }
}
