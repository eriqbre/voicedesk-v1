import Foundation

/// Linux fixture for the 576cf79 walk: version ask speaks the full line;
/// an echo of her first words must not cancel her mid-sentence.
public struct EchoSpeakWalk: Equatable, Sendable {
    public var spokenLine: String
    public var completedSpokenLine: Bool
    public var cancelledSpeak: Bool
    public var droppedTranscripts: [String]
    public var acceptedTurns: [String]

    public init(
        spokenLine: String,
        completedSpokenLine: Bool,
        cancelledSpeak: Bool,
        droppedTranscripts: [String],
        acceptedTurns: [String]
    ) {
        self.spokenLine = spokenLine
        self.completedSpokenLine = completedSpokenLine
        self.cancelledSpeak = cancelledSpeak
        self.droppedTranscripts = droppedTranscripts
        self.acceptedTurns = acceptedTurns
    }

    /// Version ask → Eve starts the identity line → echo fragments arrive
    /// mid-speak (and as leftovers after) → calendar / Lauren stay live.
    public static func versionAskThenMidSpeakEcho(
        identity: BuildIdentity = .fixture,
        midSpeakFragments: [String] = ["voice", "point", "build", "zero"],
        leftoverFragments: [String] = ["voice", "point", "zero"],
        liveAsks: [String] = ["what's on my calendar", "latest email from Lauren"]
    ) -> EchoSpeakWalk {
        let line = identity.spokenLine
        var gate = EchoTranscriptGate()
        var cancelled = false
        var dropped: [String] = []
        var accepted: [String] = []

        gate.beginSpeaking(line)

        if EchoBargeIn.shouldCancelSpeak(
            event: .speechStarted,
            gate: gate,
            voiceState: .speaking
        ) {
            cancelled = true
        }

        for fragment in midSpeakFragments {
            let event = GrokRealtime.EventKind.userTranscript(text: fragment, itemID: nil)
            if EchoBargeIn.shouldCancelSpeak(event: event, gate: gate, voiceState: .speaking) {
                cancelled = true
            }
            if EchoBargeIn.acceptedUserTranscript(fragment, gate: gate, voiceState: .speaking) == nil {
                dropped.append(fragment)
            } else {
                accepted.append(fragment)
            }
        }

        gate.finishSpeaking()

        for leftover in leftoverFragments {
            if EchoBargeIn.acceptedUserTranscript(leftover, gate: gate) == nil {
                dropped.append(leftover)
            } else {
                accepted.append(leftover)
            }
        }

        for ask in liveAsks {
            if let text = EchoBargeIn.acceptedUserTranscript(ask, gate: gate) {
                accepted.append(text)
            } else {
                dropped.append(ask)
            }
        }

        return EchoSpeakWalk(
            spokenLine: line,
            completedSpokenLine: !cancelled && line == identity.spokenLine,
            cancelledSpeak: cancelled,
            droppedTranscripts: dropped,
            acceptedTurns: accepted
        )
    }
}
