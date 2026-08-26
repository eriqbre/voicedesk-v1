import Foundation

public enum ListenResumeDecision: Equatable, Sendable {
    /// User tapped stop / cancel. Do not capture or reconnect.
    case stayIdle
    /// Socket is open and the mic tap is already running. Stay in listen.
    case keepListening
    /// Socket is open but capture is down. Start the mic tap again.
    case resumeCapture
    /// Socket closed while the session should still be live. Reconnect — no new first-tap.
    case reconnect
}

/// After a local desk line, the live Grok socket must keep hearing.
/// Desk speak is on-device TTS — it does not go through the socket.
/// This policy is only “stay in listen / resume the tap / reconnect.”
public enum ListenResumePolicy: Sendable {
    /// Client TTS never leaves listen. Socket open → keep hearing.
    /// Closed socket → reconnect. User stop → idle.
    public static func afterDeskSpeak(
        userWantsVoiceOff: Bool,
        socketConnected: Bool,
        captureRunning: Bool
    ) -> ListenResumeDecision {
        _ = captureRunning
        if userWantsVoiceOff { return .stayIdle }
        if !socketConnected { return .reconnect }
        return .keepListening
    }

    /// Mic stays live through client TTS. `ttsFinished` is unused.
    public static func afterClientTTS(
        ttsFinished: Bool,
        userWantsVoiceOff: Bool,
        socketConnected: Bool,
        captureRunning: Bool
    ) -> ListenResumeDecision? {
        _ = ttsFinished
        return afterDeskSpeak(
            userWantsVoiceOff: userWantsVoiceOff,
            socketConnected: socketConnected,
            captureRunning: captureRunning
        )
    }

    public static func shouldArmListenAfterClientTTS(ttsFinished: Bool) -> Bool {
        _ = ttsFinished
        return true
    }

    /// Desk replies always use on-device TTS. Grok realtime is listen +
    /// general conversation only — never a fake user turn / response.create.
    public static func deskSpeakUsesClientTTS() -> Bool {
        true
    }

    public static func deskSpeakUsesGrokVerbatim() -> Bool {
        !deskSpeakUsesClientTTS()
    }

    /// 4ac127a / 697147d: `session close code=1000 state=idle` after a desk
    /// line is not user-stop. Reconnect when the live session should hear.
    public static func isNormalClose(_ code: Int) -> Bool {
        code == 1000 || code == 1001
    }

    /// Armed on first Tap to talk, warmUp, or `audio.start`. Cleared only on
    /// user stop. Audio flowing is live unless they tapped stop.
    public static func sessionShouldStayLive(
        userWantsVoiceOff: Bool,
        liveSessionArmed: Bool,
        audioStarted: Bool = false
    ) -> Bool {
        !userWantsVoiceOff && (liveSessionArmed || audioStarted)
    }

    /// Socket closed. Reconnect when the live session is still supposed to hear.
    /// Code 1000 + idle is the 4ac127a / 697147d deaf path.
    public static func afterSocketClose(
        userWantsVoiceOff: Bool,
        sessionShouldStayLive: Bool,
        closeCode: Int? = nil,
        voiceState: VoiceState? = nil
    ) -> ListenResumeDecision {
        _ = closeCode
        _ = voiceState
        if userWantsVoiceOff || !sessionShouldStayLive { return .stayIdle }
        return .reconnect
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

    /// Grok `response.created` during on-device TTS must not flip the
    /// session to `.speaking`. Client TTS is listen-only.
    public static func shouldApplyGrokSpeakStarted(clientTTSSpeaking: Bool) -> Bool {
        !clientTTSSpeaking
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
            voiceState: session.state
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

    public static func isCaptureArmed(
        userWantsVoiceOff: Bool,
        socketConnected: Bool,
        captureRunning: Bool,
        voiceState: VoiceState
    ) -> Bool {
        !userWantsVoiceOff
            && socketConnected
            && captureRunning
            && isListenArmed(state: voiceState)
    }

    public static func isArmed(_ decision: ListenResumeDecision) -> Bool {
        switch decision {
        case .keepListening, .resumeCapture, .reconnect:
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

    public static let droppedTranscriptNote = "dropped transcript"

    public static func droppedTranscript(detail: String = "leftover-echo") -> VoiceInteractionEntry {
        entry(note: "\(droppedTranscriptNote) \(detail)")
    }

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
