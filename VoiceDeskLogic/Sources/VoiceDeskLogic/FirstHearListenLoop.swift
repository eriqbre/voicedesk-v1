import Foundation

/// No-user first-hear walk. Goes through tap + listen-resume, not a
/// phrase parser. fa72e1c failed here: Grok `response.created` during
/// client TTS left VoiceSession speaking, then close 1000 stayLive=false.
/// One inject after keep-listen. No second audio.start.
public struct FirstHearListenLoop: Equatable, Sendable {
    public var landed: [String]
    public var tapLive: Bool
    public var listenArmed: Bool
    public var leftoverDropped: [String]
    public var stayLive: Bool
    public var close1000: ListenResumeDecision
    public var startCount: Int

    public init(
        landed: [String],
        tapLive: Bool,
        listenArmed: Bool,
        leftoverDropped: [String],
        stayLive: Bool,
        close1000: ListenResumeDecision,
        startCount: Int
    ) {
        self.landed = landed
        self.tapLive = tapLive
        self.listenArmed = listenArmed
        self.leftoverDropped = leftoverDropped
        self.stayLive = stayLive
        self.close1000 = close1000
        self.startCount = startCount
    }

    /// Two kept turns, then Eve TTS, then **one** inject. That inject must
    /// land. Session stays live. No second start. Leftover of the spoken
    /// line still drops.
    public static func twoTurnsThenOneDuringClientTTS(
        first: String,
        second: String,
        spokenAfterSecond: String,
        duringTTS: String,
        leftovers: [String] = ["here", "they"],
        context: DeskContext = VoiceRegressionDesk.greenacreFirst
    ) -> FirstHearListenLoop {
        var session = VoiceSession()
        session.apply(.tapTalk)
        var tapLive = true
        var startCount = 1
        var gate = EchoTranscriptGate()
        var landed: [String] = []
        var leftoverDropped: [String] = []

        func inject(_ text: String) -> Bool {
            let decision = ListenResumePolicy.afterClientTTS(
                ttsFinished: false,
                userWantsVoiceOff: false,
                socketConnected: true,
                captureRunning: tapLive
            )
            if decision != .keepListening {
                tapLive = false
            }
            guard tapLive, ListenResumePolicy.isListenArmed(state: session.state) else {
                return false
            }
            guard let accepted = EchoBargeIn.acceptedUserTranscript(text, gate: gate) else {
                leftoverDropped.append(text)
                return false
            }
            landed.append(accepted)
            return true
        }

        _ = inject(first)
        _ = inject(second)

        gate.beginSpeaking(spokenAfterSecond)
        // Grok may still emit response.created during on-device TTS.
        // fa72e1c left VoiceSession in .speaking and never keep-listened.
        if ListenResumePolicy.shouldApplyGrokSpeakStarted(clientTTSSpeaking: true) {
            session.apply(.speakStarted)
        }
        let during = ListenResumePolicy.afterClientTTS(
            ttsFinished: false,
            userWantsVoiceOff: false,
            socketConnected: true,
            captureRunning: tapLive
        )
        if during != .keepListening {
            tapLive = false
        }
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
        gate.finishSpeaking()

        for leftover in leftovers {
            _ = inject(leftover)
        }

        return FirstHearListenLoop(
            landed: landed,
            tapLive: tapLive,
            listenArmed: after.listenArmed,
            leftoverDropped: leftoverDropped,
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
            leftoverDropped: [],
            stayLive: stay,
            close1000: close,
            startCount: 1
        )
    }
}
