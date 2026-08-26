import AVFoundation
import Foundation

/// On-device TTS as PCM into the live engine player. Never the AVSpeech
/// output path — that sits outside voice processing, so AEC cannot cancel Eve.
///
/// `write` yields buffers; the caller plays them with `playPCM16` on the
/// same `AVAudioEngine` that owns the mic tap.
@MainActor
final class ClientVoiceSpeech: NSObject {
    static let shared = ClientVoiceSpeech()

    private let synthesizer = AVSpeechSynthesizer()
    private var play: ((Data) -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    private var currentUtterance: AVSpeechUtterance?

    private override init() {
        super.init()
        // write() only yields PCM. The shared session stays playAndRecord
        // + voiceChat. Letting AVSpeech own it flips category/mode or
        // deactivates and yanks the HAL tap.
        synthesizer.usesApplicationAudioSession = false
    }

    func speak(_ text: String, play: @escaping (Data) -> Void) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        finishPendingWait()
        synthesizer.stopSpeaking(at: .immediate)
        self.play = play
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        currentUtterance = utterance
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            continuation = cont
            synthesizer.write(utterance) { [weak self] buffer in
                self?.handleWrite(buffer)
            }
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        play = nil
        currentUtterance = nil
        finishPendingWait()
    }

    private func handleWrite(_ buffer: AVAudioBuffer) {
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            Task { @MainActor in
                self.currentUtterance = nil
                self.finishPendingWait()
            }
            return
        }
        guard let data = Self.pcm16LE(from: pcm) else { return }
        Task { @MainActor in
            self.play?(data)
        }
    }

    private func finishPendingWait() {
        continuation?.resume()
        continuation = nil
    }

    /// Same 24 kHz PCM16 the player and tap already use.
    nonisolated static func pcm16LE(from pcm: AVAudioPCMBuffer) -> Data? {
        let count = Int(pcm.frameLength)
        guard count > 0 else { return nil }
        var samples = [Float](repeating: 0, count: count)
        if let channel = pcm.floatChannelData?[0] {
            samples.withUnsafeMutableBufferPointer { dest in
                guard let base = dest.baseAddress else { return }
                base.update(from: channel, count: count)
            }
        } else if let channel = pcm.int16ChannelData?[0] {
            for index in 0..<count {
                samples[index] = Float(channel[index]) / Float(Int16.max)
            }
        } else {
            return nil
        }
        return GrokVoiceAudioEngine.int16Data(samples: samples, sourceRate: pcm.format.sampleRate)
    }
}
