import Foundation

public enum ListenResumeDecision: Equatable, Sendable {
    /// User tapped stop / cancel. Do not capture or reconnect.
    case stayIdle
    /// Socket is open. Mic tap stays. Stay in listen.
    case keepListening
    /// Socket closed while the session should still be live. Reconnect — no new first-tap.
    case reconnect
}

/// After a local desk line, the live Grok socket must keep hearing.
/// Live Talk speaks through Eve. Offline / down-socket still uses
/// ClientVoiceSpeech. This policy is only “stay in listen / reconnect.”
public enum ListenResumePolicy: Sendable {
    /// Client TTS never leaves listen. Socket open → keep hearing.
    /// Closed socket → reconnect. User stop → idle.
    public static func afterDeskSpeak(
        userWantsVoiceOff: Bool,
        socketConnected: Bool
    ) -> ListenResumeDecision {
        if userWantsVoiceOff { return .stayIdle }
        if !socketConnected { return .reconnect }
        return .keepListening
    }

    /// One contract with `speak()`. Live socket up = Eve. Down = ClientVoiceSpeech.
    public static func deskSpeakUsesClientTTS(
        socketConnected: Bool,
        liveSessionArmed: Bool = true,
        usesLiveLoop: Bool = true,
        userWantsVoiceOff: Bool = false
    ) -> Bool {
        LiveEveSpeak.mouth(
            usesLiveLoop: usesLiveLoop,
            socketConnected: socketConnected,
            liveSessionArmed: liveSessionArmed,
            userWantsVoiceOff: userWantsVoiceOff
        ) == .clientTTS
    }

    public static func deskSpeakUsesGrokVerbatim(
        socketConnected: Bool,
        liveSessionArmed: Bool = true,
        usesLiveLoop: Bool = true,
        userWantsVoiceOff: Bool = false
    ) -> Bool {
        !deskSpeakUsesClientTTS(
            socketConnected: socketConnected,
            liveSessionArmed: liveSessionArmed,
            usesLiveLoop: usesLiveLoop,
            userWantsVoiceOff: userWantsVoiceOff
        )
    }

    /// 4ac127a / 697147d: `session close code=1000 state=idle` after a desk
    /// line is not user-stop. Reconnect when the live session should hear.
    public static func isNormalClose(_ code: Int) -> Bool {
        code == 1000 || code == 1001
    }

    /// Armed on first Tap to talk, warmUp, or `audio.start`. Cleared only on
    /// user stop. Audio flowing is live unless they tapped stop.
    /// `clientTTSInFlight` keeps stayLive during write→player only.
    /// After drain it is cleared; stayLive is then armed + running audio.
    public static func sessionShouldStayLive(
        userWantsVoiceOff: Bool,
        liveSessionArmed: Bool,
        audioStarted: Bool = false,
        clientTTSInFlight: Bool = false
    ) -> Bool {
        !userWantsVoiceOff && (liveSessionArmed || audioStarted || clientTTSInFlight)
    }

    /// fe1ffc8 / fa72e1c / 18d5878 / 415c955: stayLive was listen-armed.
    /// Close 1000 after desk TTS while speaking/idle → stayIdle.
    public static func sha415c955StayLiveAfterClose1000(
        userWantsVoiceOff: Bool,
        listenArmed: Bool
    ) -> Bool {
        !userWantsVoiceOff && listenArmed
    }

    /// Socket closed. Reconnect when the live session is still supposed to hear.
    /// Code 1000 + idle/speaking after desk TTS is not user-stop.
    /// 415c955 stayLive was listen-armed only — idle after TTS + 1000
    /// skipped recover. A live conversation (`liveSessionArmed`, user
    /// did not tap stop) must reconnect even if VoiceSession is idle.
    public static func afterSocketClose(
        userWantsVoiceOff: Bool,
        sessionShouldStayLive: Bool,
        closeCode: Int? = nil,
        voiceState: VoiceState? = nil,
        liveSessionArmed: Bool = false
    ) -> ListenResumeDecision {
        _ = closeCode
        _ = voiceState
        if userWantsVoiceOff { return .stayIdle }
        if sessionShouldStayLive || liveSessionArmed { return .reconnect }
        return .stayIdle
    }

    /// Server idle / max_duration. Stay live → reconnect.
    public static func afterRealtimeTimeout(
        userWantsVoiceOff: Bool,
        liveSessionArmed: Bool
    ) -> ListenResumeDecision {
        afterSocketClose(
            userWantsVoiceOff: userWantsVoiceOff,
            sessionShouldStayLive: sessionShouldStayLive(
                userWantsVoiceOff: userWantsVoiceOff,
                liveSessionArmed: liveSessionArmed
            )
        )
    }

    /// Idle after a desk speak still wants listen — they already tapped Talk.
    public static func sessionEventAfterDeskSpeak(state: VoiceState) -> VoiceSessionEvent {
        state == .idle ? .tapTalk : .turnFinished
    }

    public static func applySessionAfterDeskSpeak(_ session: inout VoiceSession) {
        session.apply(sessionEventAfterDeskSpeak(state: session.state))
    }

    /// Grok `response.created` must not flip the session to `.speaking`.
    /// That leftover parked listen unarmed — 415c955 close 1000 stayIdle
    /// after she talks. Grok audio plays through the one-engine player.
    public static func shouldApplyGrokSpeakStarted(clientTTSSpeaking: Bool) -> Bool {
        _ = clientTTSSpeaking
        return false
    }

    /// Leftover `response.done` during desk TTS must not leave listen.
    /// `turnFinished` from `.listening` stays listening; skip it while
    /// client TTS owns the turn so a prior `.speaking` is not required.
    public static func shouldApplyGrokTurnFinished(clientTTSSpeaking: Bool) -> Bool {
        !clientTTSSpeaking
    }

    /// Leftover `response.created` / `response.done` during write→player.
    /// Must not park `.speaking`. Same step as GrokVoiceService + the
    /// live fixtures. Not a skip flag — the leftover events are ignored.
    public static func applyLeftoverGrokDuringClientTTS(_ session: inout VoiceSession) {
        if shouldApplyGrokSpeakStarted(clientTTSSpeaking: true) {
            session.apply(.speakStarted)
        }
        if shouldApplyGrokTurnFinished(clientTTSSpeaking: true) {
            session.apply(.turnFinished)
        }
    }

    /// After on-device desk TTS. Return to listen. Desk speak is not
    /// user-stop. Close 1000 reconnects. Does not start audio again.
    public static func afterClientTTSFinished(
        session: inout VoiceSession,
        userWantsVoiceOff: Bool,
        liveSessionArmed: Bool,
        captureRunning: Bool
    ) -> ClientTTSListenResult {
        if !userWantsVoiceOff {
            applySessionAfterDeskSpeak(&session)
        }
        let stayLive = sessionShouldStayLive(
            userWantsVoiceOff: userWantsVoiceOff,
            liveSessionArmed: liveSessionArmed,
            audioStarted: captureRunning || liveSessionArmed
        )
        let close1000 = afterSocketClose(
            userWantsVoiceOff: userWantsVoiceOff,
            sessionShouldStayLive: stayLive,
            closeCode: 1000,
            voiceState: session.state,
            liveSessionArmed: liveSessionArmed
        )
        return ClientTTSListenResult(
            listenArmed: !userWantsVoiceOff && isListenArmed(state: session.state),
            stayLive: stayLive,
            close1000: close1000,
            startAgain: false
        )
    }

    public static func isListenArmed(state: VoiceState) -> Bool {
        state == .listening
    }

    public static func isArmed(_ decision: ListenResumeDecision) -> Bool {
        switch decision {
        case .keepListening, .reconnect:
            return true
        case .stayIdle:
            return false
        }
    }
}

/// After client TTS. Listen stays up. No second `audio.start`.
public struct ClientTTSListenResult: Equatable, Sendable {
    public var listenArmed: Bool
    public var stayLive: Bool
    public var close1000: ListenResumeDecision
    /// Always false — collapse listen, do not relaunch capture.
    public var startAgain: Bool

    public init(
        listenArmed: Bool,
        stayLive: Bool,
        close1000: ListenResumeDecision,
        startAgain: Bool
    ) {
        self.listenArmed = listenArmed
        self.stayLive = stayLive
        self.close1000 = close1000
        self.startAgain = startAgain
    }
}

/// Compact engine line for the dogfood JSONL / gist. Not a user turn.
public enum ListenResumeLog: Sendable {
    public static let intent = "listen-resume"
    public static let source = "engine"

    public static func entry(note: String, errors: [String] = []) -> VoiceInteractionEntry {
        VoiceInteractionEntry(
            source: source,
            userTranscript: "",
            intent: intent,
            routingNotes: [note],
            cardsAttached: [],
            assistantReply: "",
            voicePath: "Eve realtime",
            errors: errors
        )
    }
}
