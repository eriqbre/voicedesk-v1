import Foundation

/// 2150783 live fail: Grok `responseCreated` flips `.speaking` before the
/// user transcript arrives. lastSpokenLine is empty. That must not drop
/// a real ask — latest-emails, version, SHA, calendar, or named email.
public struct GrokSpeakingEmptyEchoWalk: Equatable, Sendable {
    public var accepted: Bool
    public var intent: String
    public var dropped: Bool

    public init(accepted: Bool, intent: String, dropped: Bool) {
        self.accepted = accepted
        self.intent = intent
        self.dropped = dropped
    }

    public static let latestEmailsFamily = [
        "show my latest emails",
        "my latest emails",
        "okay show me my latest emails",
        "Okay, show me my latest emails.",
        "show me my latest emails"
    ]

    public static let versionFamily = [
        "what version are we on",
        "what's on the phone",
        "what build is this"
    ]

    public static let shaFamily = [
        "what SHA is this",
        "what's the SHA",
        "what git hash is this"
    ]

    public static let calendarFamily = [
        "what's on my calendar",
        "show my calendar",
        "calendar for the week"
    ]

    public static let namedEmailFamily = [
        "latest email from Lauren",
        "email from Lauren",
        "What's the latest email from Lauren?"
    ]

    public static let namedKatherineFamily = [
        "email from Katherine",
        "the email from Katherine"
    ]

    /// Grok is already `.speaking`. No on-device desk line. Real ask.
    public static func race(
        ask: String,
        context: DeskContext = VoiceRegressionDesk.connected
    ) -> GrokSpeakingEmptyEchoWalk {
        let gate = EchoTranscriptGate()
        let decision = gate.decide(ask, voiceState: .speaking, context: context)
        return GrokSpeakingEmptyEchoWalk(
            accepted: decision.acceptedText != nil
                && !gate.isSpeaking
                && gate.lastSpokenLine.isEmpty,
            intent: decision.intent,
            dropped: decision.isDropped
        )
    }

    /// Second ask after the first would have been dropped in the old world.
    public static func twoAsks(
        first: String,
        second: String,
        context: DeskContext = VoiceRegressionDesk.connected
    ) -> (first: GrokSpeakingEmptyEchoWalk, second: GrokSpeakingEmptyEchoWalk) {
        let gate = EchoTranscriptGate()
        let d1 = gate.decide(first, voiceState: .speaking, context: context)
        let d2 = gate.decide(second, voiceState: .speaking, context: context)
        return (
            GrokSpeakingEmptyEchoWalk(
                accepted: d1.acceptedText != nil && gate.lastSpokenLine.isEmpty,
                intent: d1.intent,
                dropped: d1.isDropped
            ),
            GrokSpeakingEmptyEchoWalk(
                accepted: d2.acceptedText != nil && gate.lastSpokenLine.isEmpty,
                intent: d2.intent,
                dropped: d2.isDropped
            )
        )
    }
}
