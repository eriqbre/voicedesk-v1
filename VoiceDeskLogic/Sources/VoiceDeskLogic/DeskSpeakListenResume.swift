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
    public var ttsFinished: Bool
    /// Next ask cancelled leftover on-device desk TTS only if Eve
    /// already treats it as a command.
    public var cancelledSpeak: Bool

    public init(
        spokenIntent: String,
        listenArmed: Bool,
        captureArmed: Bool,
        decision: ListenResumeDecision,
        nextIntent: String,
        nextAccepted: Bool,
        voiceState: VoiceState,
        ttsFinished: Bool = true,
        cancelledSpeak: Bool = false
    ) {
        self.spokenIntent = spokenIntent
        self.listenArmed = listenArmed
        self.captureArmed = captureArmed
        self.decision = decision
        self.nextIntent = nextIntent
        self.nextAccepted = nextAccepted
        self.voiceState = voiceState
        self.ttsFinished = ttsFinished
        self.cancelledSpeak = cancelledSpeak
    }

    /// Client TTS is playing. Mic stays in listen. Next ask is heard
    /// when listen is armed. Playback cancel is Eve (`ListenInterrupt`).
    public static func whileClientTTSSpeaking(
        ask: String,
        spokenLine: String,
        nextAsk: String,
        context: DeskContext,
        socketConnected: Bool = true,
        userWantsVoiceOff: Bool = false
    ) -> DeskSpeakListenResume {
        _ = spokenLine
        var session = VoiceSession()
        session.apply(.tapTalk)

        let pending = ListenResumePolicy.afterDeskSpeak(
            userWantsVoiceOff: userWantsVoiceOff,
            socketConnected: socketConnected
        )
        let spoken = VoiceTurnReplay.play(utterance: ask, context: context)
        let next = VoiceTurnReplay.play(utterance: nextAsk, context: context)
        let listenArmed = !userWantsVoiceOff && ListenResumePolicy.isListenArmed(state: session.state)
        let trimmed = nextAsk.trimmingCharacters(in: .whitespacesAndNewlines)

        return DeskSpeakListenResume(
            spokenIntent: spoken.intent,
            listenArmed: listenArmed,
            captureArmed: listenArmed && ListenResumePolicy.isArmed(pending),
            decision: pending,
            nextIntent: next.intent,
            nextAccepted: listenArmed && !trimmed.isEmpty,
            voiceState: session.state,
            ttsFinished: false,
            cancelledSpeak: ListenInterrupt.isCommand(nextAsk, context: context)
        )
    }

    /// Live session → desk speak → TTS reports done → listen armed
    /// → a later real ask is accepted (not eaten by a leftover gate).
    public static func afterCompletedDeskSpeak(
        ask: String,
        spokenLine: String,
        nextAsk: String,
        context: DeskContext,
        socketConnected: Bool = true,
        userWantsVoiceOff: Bool = false
    ) -> DeskSpeakListenResume {
        _ = spokenLine
        var session = VoiceSession()
        session.apply(.tapTalk)

        let decision = ListenResumePolicy.afterDeskSpeak(
            userWantsVoiceOff: userWantsVoiceOff,
            socketConnected: socketConnected
        )
        let spoken = VoiceTurnReplay.play(utterance: ask, context: context)
        let next = VoiceTurnReplay.play(utterance: nextAsk, context: context)
        let listenArmed = ListenResumePolicy.isListenArmed(state: session.state)
        let trimmed = nextAsk.trimmingCharacters(in: .whitespacesAndNewlines)

        return DeskSpeakListenResume(
            spokenIntent: spoken.intent,
            listenArmed: listenArmed,
            captureArmed: listenArmed && ListenResumePolicy.isArmed(decision),
            decision: decision,
            nextIntent: next.intent,
            nextAccepted: listenArmed && !trimmed.isEmpty,
            voiceState: session.state
        )
    }

    /// Walk 2 (2026-08-25 ~12:17 ET): several desk speaks, then calendar.
    /// The tap stays up after the last TTS. No rearm.
    public static func afterSequentialDeskSpeaks(
        turns: [(ask: String, spoken: String)],
        nextAsk: String,
        context: DeskContext,
        socketConnected: Bool = true,
        userWantsVoiceOff: Bool = false
    ) -> DeskSpeakListenResume {
        var session = VoiceSession()
        session.apply(.tapTalk)
        var lastAsk = ""
        for turn in turns {
            lastAsk = turn.ask
        }
        let decision = ListenResumePolicy.afterDeskSpeak(
            userWantsVoiceOff: userWantsVoiceOff,
            socketConnected: socketConnected
        )
        let spoken = VoiceTurnReplay.play(utterance: lastAsk, context: context)
        let next = VoiceTurnReplay.play(utterance: nextAsk, context: context)
        let listenArmed = ListenResumePolicy.isListenArmed(state: session.state)
        let trimmed = nextAsk.trimmingCharacters(in: .whitespacesAndNewlines)
        return DeskSpeakListenResume(
            spokenIntent: spoken.intent,
            listenArmed: listenArmed,
            captureArmed: listenArmed && ListenResumePolicy.isArmed(decision),
            decision: decision,
            nextIntent: next.intent,
            nextAccepted: listenArmed && !trimmed.isEmpty,
            voiceState: session.state
        )
    }

    /// Named-sender desk speak then calendar. Both are on-device TTS; the
    /// socket stays in listen. Close 1000 after calendar is not user-stop.
    public static func afterNamedSenderThenCalendar(
        senderAsk: String,
        calendarAsk: String,
        context: DeskContext,
        userWantsVoiceOff: Bool = false,
        liveSessionArmed: Bool = true,
        reportClose: Bool = false
    ) -> DeskSpeakListenResume {
        _ = VoiceTurnReplay.play(utterance: senderAsk, context: context)
        let afterCalendar = afterCompletedDeskSpeak(
            ask: calendarAsk,
            spokenLine: ConversationPresence.calendarReply(context: context),
            nextAsk: "Tell me about my emails.",
            context: context,
            userWantsVoiceOff: userWantsVoiceOff
        )
        let stayLive = ListenResumePolicy.sessionShouldStayLive(
            userWantsVoiceOff: userWantsVoiceOff,
            liveSessionArmed: liveSessionArmed
        )
        let close = ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: userWantsVoiceOff,
            sessionShouldStayLive: stayLive,
            closeCode: 1000,
            voiceState: .idle
        )
        return DeskSpeakListenResume(
            spokenIntent: afterCalendar.spokenIntent,
            listenArmed: !userWantsVoiceOff && afterCalendar.listenArmed,
            captureArmed: !userWantsVoiceOff && afterCalendar.captureArmed
                && ListenResumePolicy.isArmed(close),
            decision: reportClose ? close : afterCalendar.decision,
            nextIntent: afterCalendar.nextIntent,
            nextAccepted: afterCalendar.nextAccepted,
            voiceState: afterCalendar.voiceState
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
            context: context
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
        let next = VoiceTurnReplay.play(utterance: nextAsk, context: context)
        let trimmed = nextAsk.trimmingCharacters(in: .whitespacesAndNewlines)
        let listenArmed = ListenResumePolicy.isListenArmed(state: session.state)
        return DeskSpeakListenResume(
            spokenIntent: before.spokenIntent,
            listenArmed: listenArmed,
            captureArmed: listenArmed && ListenResumePolicy.isArmed(close),
            decision: close,
            nextIntent: next.intent,
            nextAccepted: listenArmed && !trimmed.isEmpty,
            voiceState: session.state
        )
    }
}
