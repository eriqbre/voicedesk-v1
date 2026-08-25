import Foundation

/// Linux fixture for the 2026-08-25 live walk: a completed desk speak
/// (calendar, inbox-overview, need-more, task miss) must leave the live
/// session armed for the next ask. Intent / state only — not Eve’s wording.
public struct DeskSpeakListenResume: Equatable, Sendable {
    public var spokenIntent: String
    public var listenArmed: Bool
    public var captureArmed: Bool
    public var decision: ListenResumeDecision
    public var nextIntent: String
    public var nextAccepted: Bool
    public var voiceState: VoiceState

    public init(
        spokenIntent: String,
        listenArmed: Bool,
        captureArmed: Bool,
        decision: ListenResumeDecision,
        nextIntent: String,
        nextAccepted: Bool,
        voiceState: VoiceState
    ) {
        self.spokenIntent = spokenIntent
        self.listenArmed = listenArmed
        self.captureArmed = captureArmed
        self.decision = decision
        self.nextIntent = nextIntent
        self.nextAccepted = nextAccepted
        self.voiceState = voiceState
    }

    /// Live session → desk speak → speak completes → listen/capture armed
    /// → a later real ask is accepted (not eaten as echo / leftover).
    public static func afterCompletedDeskSpeak(
        ask: String,
        spokenLine: String,
        nextAsk: String,
        context: DeskContext,
        socketConnected: Bool = true,
        captureRunningAfterSpeak: Bool = false,
        userWantsVoiceOff: Bool = false
    ) -> DeskSpeakListenResume {
        var session = VoiceSession()
        session.apply(.tapTalk)
        session.apply(.listenFinished)
        session.apply(.speakStarted)

        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spokenLine)
        gate.finishSpeaking()
        ListenResumePolicy.applySessionAfterDeskSpeak(&session)

        let decision = ListenResumePolicy.afterDeskSpeak(
            userWantsVoiceOff: userWantsVoiceOff,
            socketConnected: socketConnected,
            captureRunning: captureRunningAfterSpeak
        )
        let spoken = VoiceTurnReplay.play(utterance: ask, context: context)
        let next = gate.decide(nextAsk, voiceState: session.state, context: context)
        let listenArmed = ListenResumePolicy.isListenArmed(state: session.state)

        return DeskSpeakListenResume(
            spokenIntent: spoken.intent,
            listenArmed: listenArmed,
            captureArmed: listenArmed && ListenResumePolicy.isArmed(decision),
            decision: decision,
            nextIntent: next.intent,
            nextAccepted: !next.isDropped,
            voiceState: session.state
        )
    }

    /// Walk 2 (2026-08-25 ~12:17 ET): several desk speaks, then calendar.
    /// Capture must still arm after the last TTS even if the engine reports running.
    public static func afterSequentialDeskSpeaks(
        turns: [(ask: String, spoken: String)],
        nextAsk: String,
        context: DeskContext,
        socketConnected: Bool = true,
        captureRunningAfterSpeak: Bool = true,
        userWantsVoiceOff: Bool = false
    ) -> DeskSpeakListenResume {
        var session = VoiceSession()
        session.apply(.tapTalk)
        var gate = EchoTranscriptGate()
        var lastAsk = ""
        for turn in turns {
            lastAsk = turn.ask
            session.apply(.listenFinished)
            session.apply(.speakStarted)
            gate.beginSpeaking(turn.spoken)
            gate.finishSpeaking()
            ListenResumePolicy.applySessionAfterDeskSpeak(&session)
        }
        let decision = ListenResumePolicy.afterDeskSpeak(
            userWantsVoiceOff: userWantsVoiceOff,
            socketConnected: socketConnected,
            captureRunning: captureRunningAfterSpeak
        )
        let spoken = VoiceTurnReplay.play(utterance: lastAsk, context: context)
        let next = gate.decide(nextAsk, voiceState: session.state, context: context)
        let listenArmed = ListenResumePolicy.isListenArmed(state: session.state)
        return DeskSpeakListenResume(
            spokenIntent: spoken.intent,
            listenArmed: listenArmed,
            captureArmed: listenArmed && ListenResumePolicy.isArmed(decision),
            decision: decision,
            nextIntent: next.intent,
            nextAccepted: !next.isDropped,
            voiceState: session.state
        )
    }

    /// 4ac127a live fail: walk-2 tape through calendar, then code-1000 close
    /// with VoiceSession already idle. Must reconnect + arm without a new tap.
    public static func afterWalk2CalendarThenIdleNormalClose(
        nextAsk: String,
        context: DeskContext,
        userWantsVoiceOff: Bool = false,
        liveSessionArmed: Bool = true
    ) -> DeskSpeakListenResume {
        let before = afterSequentialDeskSpeaks(
            turns: [
                ("Tell me my emails for the day.", "Five emails in the last sync."),
                (
                    "Find that, find that email from Lauren about Fleeman Road.",
                    "Laren Jansen wrote about Fleeman Road disclosures."
                ),
                ("What's on my calendar for the week?", "Massimo’s on Thursday.")
            ],
            nextAsk: nextAsk,
            context: context,
            captureRunningAfterSpeak: true
        )
        var session = VoiceSession(state: .idle)
        let shouldStay = ListenResumePolicy.sessionShouldStayLive(
            userWantsVoiceOff: userWantsVoiceOff,
            liveSessionArmed: liveSessionArmed
        )
        let close = ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: userWantsVoiceOff,
            sessionShouldStayLive: shouldStay,
            closeCode: 1000,
            voiceState: .idle
        )
        if ListenResumePolicy.isArmed(close) {
            ListenResumePolicy.applySessionAfterDeskSpeak(&session)
        }
        let next = EchoTranscriptGate().decide(nextAsk, voiceState: session.state, context: context)
        return DeskSpeakListenResume(
            spokenIntent: before.spokenIntent,
            listenArmed: ListenResumePolicy.isListenArmed(state: session.state),
            captureArmed: ListenResumePolicy.isListenArmed(state: session.state)
                && ListenResumePolicy.isArmed(close),
            decision: close,
            nextIntent: next.intent,
            nextAccepted: !next.isDropped,
            voiceState: session.state
        )
    }
}
