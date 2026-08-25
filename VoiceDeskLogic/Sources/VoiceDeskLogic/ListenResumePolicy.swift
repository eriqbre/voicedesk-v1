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
    /// After on-device TTS reports didFinish / cancelled. User did not tap stop.
    ///
    /// AVSpeech can leave the engine “running” with a silent tap — do not
    /// trust `captureRunning`. Never wait on Grok `response.done` / drain.
    /// Never call this while client TTS is still speaking.
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

    /// Listen rearm waits for AVSpeech didFinish / cancelled — not Grok
    /// `response.done`. `nil` means TTS is still speaking: do not arm.
    public static func afterClientTTS(
        ttsFinished: Bool,
        userWantsVoiceOff: Bool,
        socketConnected: Bool,
        captureRunning: Bool
    ) -> ListenResumeDecision? {
        if userWantsVoiceOff { return .stayIdle }
        guard ttsFinished else { return nil }
        return afterDeskSpeak(
            userWantsVoiceOff: userWantsVoiceOff,
            socketConnected: socketConnected,
            captureRunning: captureRunning
        )
    }

    public static func shouldArmListenAfterClientTTS(ttsFinished: Bool) -> Bool {
        ttsFinished
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

    /// Armed on first Tap to talk. Cleared only on user stop. Independent of
    /// whether VoiceSession flipped idle after TTS / timeout.
    public static func sessionShouldStayLive(
        userWantsVoiceOff: Bool,
        liveSessionArmed: Bool
    ) -> Bool {
        !userWantsVoiceOff && liveSessionArmed
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
