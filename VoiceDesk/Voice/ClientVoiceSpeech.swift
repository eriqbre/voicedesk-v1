import AVFoundation
import Foundation

/// On-device TTS for local desk replies. The live Grok socket stays in
/// listen — desk speak never injects a fake user turn.
@MainActor
final class ClientVoiceSpeech {
    static let shared = ClientVoiceSpeech()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
