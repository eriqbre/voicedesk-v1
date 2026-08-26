import Foundation

/// Talk → Eve answers → tap stays live. One inject after client TTS.
/// Command vs ambient is Eve (`ListenInterrupt`), not leftover-echo.
/// No second audio.start.
public struct FirstHearListenLoop: Equatable, Sendable {
    public var landed: [String]
    public var tapLive: Bool
    public var listenArmed: Bool
    public var stayLive: Bool
    public var close1000: ListenResumeDecision
    public var startCount: Int

    public init(
        landed: [String],
        tapLive: Bool,
        listenArmed: Bool,
        stayLive: Bool,
        close1000: ListenResumeDecision,
        startCount: Int
    ) {
        self.landed = landed
        self.tapLive = tapLive
        self.listenArmed = listenArmed
        self.stayLive = stayLive
        self.close1000 = close1000
        self.startCount = startCount
    }

    /// Two kept turns, then Eve TTS, then **one** inject. Session stays
    /// live so the inject is heard. Playback cancel is not this walk.
    public static func twoTurnsThenOneDuringClientTTS(
        first: String,
        second: String,
        spokenAfterSecond: String,
        duringTTS: String,
        context: DeskContext = VoiceRegressionDesk.greenacreFirst
    ) -> FirstHearListenLoop {
        _ = spokenAfterSecond
        _ = context
        var session = VoiceSession()
        session.apply(.tapTalk)
        var tapLive = true
        var startCount = 1
        var landed: [String] = []

        func inject(_ text: String) -> Bool {
            guard tapLive, ListenResumePolicy.isListenArmed(state: session.state) else {
                return false
            }
            landed.append(text)
            return true
        }

        _ = inject(first)
        _ = inject(second)

        ListenResumePolicy.applyLeftoverGrokDuringClientTTS(&session)
        let after = ListenResumePolicy.afterClientTTSFinished(
            session: &session,
            userWantsVoiceOff: false,
            liveSessionArmed: true,
            captureRunning: tapLive
        )
        if after.startAgain {
            startCount += 1
        }
        if !after.stayLive {
            tapLive = false
        }
        _ = inject(duringTTS)

        return FirstHearListenLoop(
            landed: landed,
            tapLive: tapLive,
            listenArmed: after.listenArmed,
            stayLive: after.stayLive,
            close1000: after.close1000,
            startCount: startCount
        )
    }

    /// fa72e1c: speakStarted during TTS, no keep-listen. Next ask is deaf.
    public static func fa72e1cSpeakStartedWithoutKeepListen(
        nextAsk: String = "What version are we on?"
    ) -> FirstHearListenLoop {
        var session = VoiceSession()
        session.apply(.tapTalk)
        session.apply(.speakStarted)
        let landed: [String] = ListenResumePolicy.isListenArmed(state: session.state)
            ? [nextAsk]
            : []
        let stay = ListenResumePolicy.sessionShouldStayLive(
            userWantsVoiceOff: false,
            liveSessionArmed: true,
            audioStarted: true
        )
        let close = ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: false,
            sessionShouldStayLive: stay,
            closeCode: 1000,
            voiceState: session.state
        )
        return FirstHearListenLoop(
            landed: landed,
            tapLive: true,
            listenArmed: ListenResumePolicy.isListenArmed(state: session.state),
            stayLive: stay,
            close1000: close,
            startCount: 1
        )
    }
}
