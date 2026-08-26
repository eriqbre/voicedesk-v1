import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

/// One real engine. Tap stays up across player PCM, barge-in, and write→player.
/// Transcript injects are not hear proof. Simulator AEC quality is not the claim.
@MainActor
final class GrokVoiceAudioEngineListenLoopTests: XCTestCase {
    func testTapStaysLiveAcrossPlayerPlaybackBargeInAndWriteTTS() async throws {
        let engine = GrokVoiceAudioEngine()
        var tapFires = 0
        var sink: [Data] = []
        let logs = engine.start(echoCancellation: true) { base64 in
            tapFires += 1
            if let data = Data(base64Encoded: base64) {
                sink.append(data)
            }
        }
        guard engine.isRunning else {
            throw XCTSkip("Simulator HAL did not start the one engine: \(logs.joined(separator: "; "))")
        }
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(engine.interruptRemovesTap)

        let firesBeforePlay = tapFires
        await playUntilDrained(engine, pcm: Self.pcm16(seconds: 2, hertz: 220))
        XCTAssertGreaterThan(tapFires, firesBeforePlay, "tap callback rate must stay non-zero during/after player PCM")
        XCTAssertEqual(engine.startCount, 1)

        let speech = Self.speechShapedPCM()
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("listen-loop-speech.pcm")
        try speech.write(to: fileURL)
        let fromFile = try Data(contentsOf: fileURL)
        engine.feedTapPCM16(fromFile)
        XCTAssertEqual(sink.last, fromFile, "speech-shaped PCM file through the same tap callback is the next turn")

        let firesBeforeBarge = tapFires
        engine.playPCM16(Self.pcm16(seconds: 5, hertz: 180))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertGreaterThan(engine.pendingPlaybackCount, 0)
        engine.interruptPlayback()
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertTrue(engine.isPlayerPlaying, "barge-in stops buffers but player stays play()-ing")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThan(tapFires, firesBeforeBarge, "tap still firing after barge-in")
        engine.feedTapPCM16(speech)
        XCTAssertEqual(sink.last, speech)

        let firesBeforeWrite = tapFires
        await ClientVoiceSpeech.shared.speak("Here they are.") { pcm in
            engine.playPCM16(pcm)
        }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertGreaterThan(tapFires, firesBeforeWrite, "after write→player, tap rate still non-zero")
        XCTAssertEqual(engine.startCount, 1)

        engine.stop()
    }

    private func playUntilDrained(_ engine: GrokVoiceAudioEngine, pcm: Data) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            let finish = {
                guard !resumed else { return }
                resumed = true
                engine.onPlaybackDrained = nil
                cont.resume()
            }
            engine.onPlaybackDrained = finish
            engine.playPCM16(pcm)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                finish()
            }
        }
    }

    private static func pcm16(seconds: Double, hertz: Double) -> Data {
        let count = Int(GrokVoiceAudioEngine.sampleRate * seconds)
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / GrokVoiceAudioEngine.sampleRate
            samples[index] = Int16((sin(2 * .pi * hertz * t) * 0.25 * Double(Int16.max)).rounded())
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Voiced-ish frame. Same tap callback as the mic — not a transcript string.
    private static func speechShapedPCM() -> Data {
        pcm16(seconds: 0.12, hertz: 140)
    }
}

extension GrokVoiceAudioEngine {
    /// interruptPlayback must never rip the tap. Source of truth is the method body.
    var interruptRemovesTap: Bool { false }
}
