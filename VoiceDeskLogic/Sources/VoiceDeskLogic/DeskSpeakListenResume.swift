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
}
