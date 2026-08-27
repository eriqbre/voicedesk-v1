import Foundation

/// Version / SHA desk speak is on-device TTS. The live socket stays in
/// listen. Close 1000 after the line is not user-stop.
public struct VersionDeskSpeakWalk: Equatable, Sendable {
    public var spokenIntent: String
    public var cardsAttached: Bool
    public var spokenLineCompleted: Bool
    public var usesGrokVerbatim: Bool
    public var listenArmedDuringTTS: Bool
    public var listenArmedAfterSpeak: Bool
    public var close1000StayLive: Bool
    public var close1000Decision: ListenResumeDecision
    public var glanceIntent: String
    public var glanceWaitsOnGmailList: Bool
    public var glanceWaitsOnModel: Bool

    public init(
        spokenIntent: String,
        cardsAttached: Bool,
        spokenLineCompleted: Bool,
        usesGrokVerbatim: Bool,
        listenArmedDuringTTS: Bool,
        listenArmedAfterSpeak: Bool,
        close1000StayLive: Bool,
        close1000Decision: ListenResumeDecision,
        glanceIntent: String,
        glanceWaitsOnGmailList: Bool,
        glanceWaitsOnModel: Bool
    ) {
        self.spokenIntent = spokenIntent
        self.cardsAttached = cardsAttached
        self.spokenLineCompleted = spokenLineCompleted
        self.usesGrokVerbatim = usesGrokVerbatim
        self.listenArmedDuringTTS = listenArmedDuringTTS
        self.listenArmedAfterSpeak = listenArmedAfterSpeak
        self.close1000StayLive = close1000StayLive
        self.close1000Decision = close1000Decision
        self.glanceIntent = glanceIntent
        self.glanceWaitsOnGmailList = glanceWaitsOnGmailList
        self.glanceWaitsOnModel = glanceWaitsOnModel
    }

    public static func versionAskThenClientTTSThenClose1000(
        ask: String,
        glanceAsk: String = "Okay, show me my latest emails.",
        identity: BuildIdentity = .fixture,
        snapshot: DeskSnapshot = VoiceRegressionDesk.connected.snapshot,
        now: Date = Date(timeIntervalSince1970: 1_777_000_000),
        userWantsVoiceOff: Bool = false,
        liveSessionArmed: Bool = true
    ) -> VersionDeskSpeakWalk {
        var hold = EarlyFinalHold()
        let accepted = hold.decide(ask, context: VoiceRegressionDesk.connected)
        let uttered = accepted.acceptedText ?? ask
        let replay = VoiceTurnReplay.play(utterance: uttered, context: VoiceRegressionDesk.connected)
        let spokenLine = ConversationPresence.spokenIdentityLine(for: uttered, identity: identity)

        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spokenLine)
        var barged = false
        for fragment in ["voice", "point", "build"] {
            guard EchoTranscriptGate.isLeftoverEcho(fragment, of: spokenLine) else { continue }
            if EchoBargeIn.shouldCancelSpeak(
                event: .userTranscript(text: fragment, itemID: nil),
                gate: gate,
                voiceState: .speaking
            ) {
                barged = true
            }
        }
        let during = DeskSpeakListenResume.whileClientTTSSpeaking(
            ask: uttered,
            spokenLine: spokenLine,
            nextAsk: glanceAsk,
            context: VoiceRegressionDesk.connected,
            userWantsVoiceOff: userWantsVoiceOff
        )
        gate.finishSpeaking()

        let after = DeskSpeakListenResume.afterCompletedDeskSpeak(
            ask: uttered,
            spokenLine: spokenLine,
            nextAsk: glanceAsk,
            context: VoiceRegressionDesk.connected,
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
        let glance = InboxGlanceSpeakPlan.cacheHot(ask: glanceAsk, snapshot: snapshot, now: now)

        return VersionDeskSpeakWalk(
            spokenIntent: replay.intent,
            cardsAttached: !replay.cardLabels.isEmpty,
            spokenLineCompleted: !barged && !spokenLine.isEmpty,
            usesGrokVerbatim: LiveEveSpeak.plan(
                text: spokenLine,
                socketConnected: false
            ).mouth == .eve,
            listenArmedDuringTTS: during.listenArmed,
            listenArmedAfterSpeak: after.listenArmed && after.captureArmed,
            close1000StayLive: stayLive,
            close1000Decision: close,
            glanceIntent: glance.intent,
            glanceWaitsOnGmailList: glance.waitsOnGmailList,
            glanceWaitsOnModel: glance.waitsOnModel
        )
    }
}
