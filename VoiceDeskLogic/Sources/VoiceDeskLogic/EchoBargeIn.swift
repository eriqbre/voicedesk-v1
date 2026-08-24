import Foundation

/// Ingress policy for live Grok events. The drop runs **before** any
/// `response.cancel` / stop-speaking path. A dropped transcript never
/// becomes a Grok user turn and never stops Eve.
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
    public static func acceptedUserTranscript(
        _ text: String,
        gate: EchoTranscriptGate,
        voiceState: VoiceState = .listening
    ) -> String? {
        gate.acceptUserTranscript(text, voiceState: voiceState)
    }
}
