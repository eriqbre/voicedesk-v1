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

/// After a completed local desk speak on the live Grok path, the realtime
/// session must keep hearing. Pure so Linux tests can run it.
///
/// Desk speak (calendar, inbox-overview, need-more, task miss, any local
/// Eve line) currently leaves `create_response: false` and/or a stopped
/// capture. This policy is the arming decision; the iOS service applies it.
public enum ListenResumePolicy: Sendable {
    /// After Eve finishes a local desk line. User did not tap stop.
    ///
    /// Walks 2026-08-25 (fa6616e) both went deaf after a completed calendar
    /// speak while the app stayed up. The engine can still report running
    /// after desk TTS while the tap is silent — do not trust `captureRunning`.
    public static func afterDeskSpeak(
        userWantsVoiceOff: Bool,
        socketConnected: Bool,
        captureRunning: Bool
    ) -> ListenResumeDecision {
        _ = captureRunning
        if userWantsVoiceOff { return .stayIdle }
        if !socketConnected { return .reconnect }
        return .resumeCapture
    }

    /// Socket closed. Reconnect when the live session is still supposed to hear.
    public static func afterSocketClose(
        userWantsVoiceOff: Bool,
        sessionShouldStayLive: Bool
    ) -> ListenResumeDecision {
        if userWantsVoiceOff || !sessionShouldStayLive { return .stayIdle }
        return .reconnect
    }

    /// Idle after a desk speak still wants listen — they already tapped Talk.
    public static func sessionEventAfterDeskSpeak(state: VoiceState) -> VoiceSessionEvent {
        state == .idle ? .tapTalk : .turnFinished
    }

    public static func applySessionAfterDeskSpeak(_ session: inout VoiceSession) {
        session.apply(sessionEventAfterDeskSpeak(state: session.state))
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
