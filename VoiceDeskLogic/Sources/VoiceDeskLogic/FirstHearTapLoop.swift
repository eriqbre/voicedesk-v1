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
    /// Do not wait for interruption. Do not start a second engine.
    public static func shouldReinstallTapIfSilentWhileRunning(
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
        third: Data = commandPCM(3)
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
        ListenResumePolicy.applyLeftoverGrokDuringClientTTS(&session)
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
        ListenResumePolicy.applyLeftoverGrokDuringClientTTS(&session)
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

    /// Product: leftover response.created/done during TTS, then close 1000.
    /// stayLive stays true, listen is re-armed on the same tap, third lands.
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
            if ListenResumePolicy.shouldApplyGrokSpeakStarted(clientTTSSpeaking: true) {
                session.apply(.speakStarted)
            }
        case .applySpeakStarted:
            session.apply(.speakStarted)
        case .leftoverGrokSpeakAndDone:
            ListenResumePolicy.applyLeftoverGrokDuringClientTTS(&session)
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
                tapInstalled: tapLive,
                engineRunning: true,
                wantsCapture: true
               ) {
                tapLive = true
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
                clientTTSInFlight: true
            )
            close1000 = ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: stayLive,
                closeCode: 1000,
                voiceState: session.state
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
