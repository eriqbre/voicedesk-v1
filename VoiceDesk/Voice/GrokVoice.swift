import Foundation
import VoiceDeskLogic

/// Where the app looks for an xAI key. Never log the value.
enum VoiceDeskSecrets {
    /// TODO: Load from the Xcode scheme env, then a local Secrets.plist that is gitignored.
    /// Do not commit a real key.
    static var xaiAPIKey: String? {
        let value = ProcessInfo.processInfo.environment["XAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

/// xAI Grok voice endpoints (docs.x.ai). Used by `LiveGrokVoiceClient` when wired.
enum GrokVoiceAPI {
    static let restBase = URL(string: "https://api.x.ai/v1")!
    static let realtime = URL(string: "wss://api.x.ai/v1/realtime")!
    static let sttStream = URL(string: "wss://api.x.ai/v1/stt")!
    static let ttsStream = URL(string: "wss://api.x.ai/v1/tts")!
    static let sttBatch = URL(string: "https://api.x.ai/v1/stt")!
    static let ttsBatch = URL(string: "https://api.x.ai/v1/tts")!
    static let realtimeClientSecrets = URL(string: "https://api.x.ai/v1/realtime/client_secrets")!
}

enum GrokVoiceError: LocalizedError {
    case missingAPIKey
    case notWired(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "XAI_API_KEY is not set."
        case .notWired(let step):
            return "Grok voice is not wired yet: \(step)"
        }
    }
}

/// Plug-in for xAI Grok voice. Primary path is the Voice Agent realtime socket
/// (`wss://api.x.ai/v1/realtime`). STT + TTS are the composable fallback.
protocol GrokVoiceClienting: Sendable {
    func mintRealtimeClientSecret() async throws -> String
    func connectRealtimeSession() async throws
    func transcribe(_ audio: Data) async throws -> String
    func synthesize(_ text: String, voiceID: String) async throws -> Data
}

/// TODO: Implement URLSession WebSocket + REST against GrokVoiceAPI.
/// This type is the seam — MockVoiceService stays the UI loop until this lands.
struct LiveGrokVoiceClient: GrokVoiceClienting {
    var apiKey: String
    var voiceID: String = "eve"

    func mintRealtimeClientSecret() async throws -> String {
        throw GrokVoiceError.notWired("POST \(GrokVoiceAPI.realtimeClientSecrets.path) for an ephemeral client secret")
    }

    func connectRealtimeSession() async throws {
        throw GrokVoiceError.notWired("WebSocket \(GrokVoiceAPI.realtime.absoluteString) speech-to-speech session")
    }

    func transcribe(_ audio: Data) async throws -> String {
        _ = audio
        throw GrokVoiceError.notWired("POST \(GrokVoiceAPI.sttBatch.path) or stream \(GrokVoiceAPI.sttStream.absoluteString)")
    }

    func synthesize(_ text: String, voiceID: String) async throws -> Data {
        _ = (text, voiceID)
        throw GrokVoiceError.notWired("POST \(GrokVoiceAPI.ttsBatch.path) voice_id=\(voiceID)")
    }
}

/// On-device wake phrase while the app is open. Phrase is an open PRD decision.
protocol WakeWordListening: AnyObject {
    var isArmed: Bool { get }
    func arm()
    func disarm()
}

@MainActor
final class WakeWordPlaceholder: WakeWordListening {
    private var session = WakeWordSession()

    var isArmed: Bool { session.isArmed }

    func arm() {
        // TODO: On-device wake phrase once the PRD open decision lands.
        session.arm()
    }

    func disarm() {
        session.disarm()
    }
}
