import Foundation

/// Half-duplex (mute mic / `.speaking`) only when Eve audio will actually play.
/// Desk-claim mute must not leak into the next weather / John Wick turn.
public enum AssistantPlaybackPolicy: Sendable {
    public static let silentSpeakingTimeout: TimeInterval = 4

    /// Enter `.speaking` and mute capture only if this response will be heard.
    public static func shouldEnterHalfDuplex(
        dropAssistantAudio: Bool,
        verbatimSpeaking: Bool
    ) -> Bool {
        verbatimSpeaking || !dropAssistantAudio
    }

    /// After Eve finishes a local desk digest, unmute Grok for the next general turn.
    /// Restoring the desk-claim mute left weather / trivia silent.
    public static var restoreSuppressAfterVerbatim: Bool { false }

    /// Stuck `.speaking` with no audio (suppressed handoff, ignored done, error).
    public static func shouldForceEndSpeaking(
        audioDeltaCount: Int,
        elapsed: TimeInterval,
        timeout: TimeInterval = silentSpeakingTimeout
    ) -> Bool {
        audioDeltaCount == 0 && elapsed >= timeout
    }

    /// User finished speaking but Grok never created a playable response.
    public static func shouldForceEndThinking(
        elapsed: TimeInterval,
        timeout: TimeInterval = silentSpeakingTimeout
    ) -> Bool {
        elapsed >= timeout
    }

    /// Local desk digest must go to Eve when the live loop is up and voice is on.
    public static func shouldSpeakVerbatim(
        reply: String?,
        liveConnected: Bool,
        userWantsVoiceOff: Bool
    ) -> Bool {
        guard let reply, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if userWantsVoiceOff { return false }
        return liveConnected
    }
}
