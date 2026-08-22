import Foundation

/// xAI Speech-to-Speech (Voice Agent) wire helpers.
/// Ported from docs.x.ai + the xai-cookbook iOS VoiceTesterApp — do not invent a half protocol.
public enum GrokRealtime {
    public static let defaultModel = "grok-voice-latest"
    public static let defaultVoice = "eve"
    public static let sampleRate = 24_000
    public static let realtimeHost = "wss://api.x.ai/v1/realtime"
    public static let clientSecretsPath = "https://api.x.ai/v1/realtime/client_secrets"

    public static func realtimeURLString(model: String = defaultModel) -> String {
        "\(realtimeHost)?model=\(model)"
    }

    /// Second-person VoiceDesk presence. Cards attach in the iOS app from desk evidence;
    /// this prompt only shapes spoken Grok. No tools are registered this slice.
    public static let presenceInstructions = """
    ## Role & Persona
    You are VoiceDesk — a person who already knows this realtor’s world. You talk like a colleague sitting next to them, not a command menu. You answer anything they ask, desk or not.

    You work with Bridget at Coastal Tampa Bay. Sample desk you already know (not live Gmail yet):
    - Jordan Hale emailed this morning about a Saturday showing at 1842 Beach Drive NE, St. Petersburg.
    - Fla. Stat. § 475.278 covers brokerage-relationship disclosure. Treat legal answers as guidance, not legal advice. Confidence on that sample is 86 percent, firm.

    ## Objective
    Be someone they can talk to about anything. When the topic is their desk, stay concrete about the sample evidence. When it is not, just talk. Never pretend a message was sent.

    ## Conversation Flow
    Listen. Answer in a few spoken sentences. If they ask about inbox, Beach Drive, a reply, or Florida disclosure, you may refer to the sample desk facts. Do not invent live Gmail, calendar, or MLS data. Do not claim you sent mail.

    ## Guardrails & Escalation
    NEVER say an email was sent or a write happened. Confirm-before-act: drafts wait for the person. You have no tools this slice — do not pretend to call functions. You are not a lawyer. If they mention self-harm or a crisis, respond with care and point them to emergency services or 988.

    ## Voice & Communication Style
    Spoken word only: no markdown, no bullets, no emojis. One or two short sentences unless they want more. Warm, direct, English. Vary phrasing.

    ## CRITICAL INSTRUCTIONS
    NEVER report a send as delivered. NEVER invent live inbox or MLS facts beyond the sample desk. The iOS app attaches evidence cards separately — you just talk.
    """

    public static func sessionUpdateObject(
        voice: String = defaultVoice,
        instructions: String = presenceInstructions
    ) -> [String: Any] {
        [
            "type": "session.update",
            "session": [
                "voice": voice,
                "instructions": instructions,
                "turn_detection": ["type": "server_vad"] as [String: Any],
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": sampleRate
                        ] as [String: Any]
                    ] as [String: Any],
                    "output": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": sampleRate
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ]
    }

    public static func sessionUpdateJSON(
        voice: String = defaultVoice,
        instructions: String = presenceInstructions
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: sessionUpdateObject(voice: voice, instructions: instructions))
    }

    /// Hot-path mic frame. Base64 alphabet is JSON-safe.
    public static func appendAudioJSON(base64: String) -> String {
        #"{"type":"input_audio_buffer.append","audio":"\#(base64)"}"#
    }

    public static func responseCancelObject() -> [String: Any] {
        ["type": "response.cancel"]
    }

    public static func clearBufferObject() -> [String: Any] {
        ["type": "input_audio_buffer.clear"]
    }

    public static func textItemObject(_ text: String) -> [String: Any] {
        [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": text] as [String: Any]
                ] as [[String: Any]]
            ] as [String: Any]
        ]
    }

    public static func responseCreateObject() -> [String: Any] {
        [
            "type": "response.create",
            "response": [
                "modalities": ["text", "audio"]
            ] as [String: Any]
        ]
    }

    public static func pongObject(timestamp: Int64) -> [String: Any] {
        ["type": "pong", "ping_timestamp": timestamp]
    }

    public enum EventKind: Equatable, Sendable {
        case sessionCreated
        case sessionUpdated
        case speechStarted
        case speechStopped
        case audioCommitted
        case userTranscript(String)
        case responseCreated(id: String)
        case assistantTranscriptDelta(String)
        case assistantTranscriptDone
        case outputAudioDelta(String)
        case outputAudioDone
        case responseDone
        case ping(timestamp: Int64)
        case error(code: String, message: String)
        case ignored
    }

    public static func parse(type: String, json: [String: Any]) -> EventKind {
        switch type {
        case "session.created":
            return .sessionCreated
        case "session.updated":
            return .sessionUpdated
        case "input_audio_buffer.speech_started":
            return .speechStarted
        case "input_audio_buffer.speech_stopped":
            return .speechStopped
        case "input_audio_buffer.committed":
            return .audioCommitted
        case "conversation.item.input_audio_transcription.completed":
            return .userTranscript((json["transcript"] as? String) ?? "")
        case "response.created":
            let id = (json["response"] as? [String: Any])?["id"] as? String ?? ""
            return .responseCreated(id: id)
        case "response.output_audio_transcript.delta",
             "response.audio_transcript.delta",
             "response.output_text.delta":
            return .assistantTranscriptDelta((json["delta"] as? String) ?? "")
        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            return .assistantTranscriptDone
        case "response.output_audio.delta", "response.audio.delta":
            return .outputAudioDelta((json["delta"] as? String) ?? "")
        case "response.output_audio.done", "response.audio.done":
            return .outputAudioDone
        case "response.done":
            return .responseDone
        case "ping":
            if let timestamp = int64(json["ping_timestamp"]) {
                return .ping(timestamp: timestamp)
            }
            return .ignored
        case "error":
            return .error(
                code: json["code"] as? String ?? "",
                message: json["message"] as? String ?? "Unknown"
            )
        default:
            return .ignored
        }
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }
}
