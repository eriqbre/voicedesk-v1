import Foundation

/// One leftover-only policy, any ingress (Grok socket or AppModel live
/// transcript / FakeLive emit). Drop leftover of on-device desk TTS.
/// Never drop because Grok is speaking or `lastSpokenLine` is empty.
public enum EchoBargeIn: Sendable {
    /// Whether this event may cancel in-flight Eve audio.
    public static func shouldCancelSpeak(
        event: GrokRealtime.EventKind,
        gate: EchoTranscriptGate,
        voiceState: VoiceState = .listening
    ) -> Bool {
        switch event {
        case .speechStarted:
            return gate.shouldCancelSpeakOnSpeechStarted(voiceState: voiceState)
        case .userTranscript(let text, _):
            return gate.shouldCancelSpeak(for: text, voiceState: voiceState)
        default:
            return false
        }
    }

    /// Transcript that may become a user turn. `nil` = dropped (never Grok).
    /// Non-nil means leftover on-device desk TTS must stop. One policy:
    /// leftover drops, accepted cancels leftover speak.
    public static func acceptedUserTranscript(
        _ text: String,
        gate: EchoTranscriptGate,
        voiceState: VoiceState = .listening
    ) -> String? {
        gate.acceptUserTranscript(text, voiceState: voiceState)
    }
}
