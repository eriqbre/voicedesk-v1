import Foundation

/// No-user first-hear walk. Goes through tap + listen-resume, not a
/// phrase parser. fe1ffc8 failed here: tap died until resumeCapture, so
/// one inject during/after client TTS never became a kept turn.
public struct FirstHearListenLoop: Equatable, Sendable {
    public var landed: [String]
    public var tapLive: Bool
    public var listenArmed: Bool
    public var leftoverDropped: [String]

    public init(
        landed: [String],
        tapLive: Bool,
        listenArmed: Bool,
        leftoverDropped: [String]
    ) {
        self.landed = landed
        self.tapLive = tapLive
        self.listenArmed = listenArmed
        self.leftoverDropped = leftoverDropped
    }

    /// Two kept turns, then Eve TTS, then **one** inject. That inject must
    /// land. Leftover of the spoken line still drops.
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
        // Client TTS. Mic stays live — do not resumeCapture.
        let during = ListenResumePolicy.afterClientTTS(
            ttsFinished: false,
            userWantsVoiceOff: false,
            socketConnected: true,
            captureRunning: tapLive
        )
        if during != .keepListening {
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
            listenArmed: ListenResumePolicy.isListenArmed(state: session.state),
            leftoverDropped: leftoverDropped
        )
    }
}
