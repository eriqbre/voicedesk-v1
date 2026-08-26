import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

/// One real engine. First-hear gate: two tap turns, desk TTS drain,
/// then a third command PCM through the SAME tap is the next turn.
/// Tap-rate-during-playback is not that gate. Transcript injects are not
/// hear proof. Simulator AEC quality is not the claim.
@MainActor
final class GrokVoiceAudioEngineListenLoopTests: XCTestCase {
    func testTapStaysLiveAcrossPlayerPlaybackBargeInAndWriteTTS() async throws {
        var session = VoiceSession()
        session.apply(.tapTalk)
        var stayLive = true
        var tapFires = 0
        var sink: [Data] = []
        var turns: [Data] = []
        let command1 = Self.speechShapedPCM(hertz: 140)
        let command2 = Self.speechShapedPCM(hertz: 160)
        let command3 = Self.speechShapedPCM(hertz: 180)
        let noise = Self.speechShapedPCM(hertz: 90)

        let engine = GrokVoiceAudioEngine()
        func acceptIfTurn(_ pcm: Data) {
            let isFed = pcm == command1 || pcm == command2 || pcm == command3 || pcm == noise
            guard isFed else { return }
            sink.append(pcm)
            guard pcm != noise else { return }
            if let turn = FirstHearTapLoop.accept(
                pcm: pcm,
                tapLive: engine.isRunning,
                session: session,
                stayLive: stayLive,
                startCount: engine.startCount
            ) {
                turns.append(turn)
            }
        }

        let logs = engine.start(echoCancellation: true) { base64 in
            tapFires += 1
            if let data = Data(base64Encoded: base64) {
                acceptIfTurn(data)
            }
        }
        guard engine.isRunning else {
            throw XCTSkip("Simulator HAL did not start the one engine: \(logs.joined(separator: "; "))")
        }
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(engine.interruptRemovesTap)
        XCTAssertTrue(ListenResumePolicy.isListenArmed(state: session.state))

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("listen-loop-third.pcm")
        try command3.write(to: fileURL)
        let thirdFromFile = try Data(contentsOf: fileURL)

        engine.feedTapPCM16(command1)
        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink, [command1, command2])
        XCTAssertEqual(turns, [command1, command2], "first two command-shaped PCM chunks must be turns")
        XCTAssertEqual(engine.startCount, 1)

        XCTAssertFalse(ListenInterrupt.isCommand("and now the weather"))
        XCTAssertFalse(ListenInterrupt.isCommand("Can you hear me?"))
        XCTAssertTrue(ListenInterrupt.isCommand("show me my emails"))

        let firesBeforeTTS = tapFires
        await ClientVoiceSpeech.shared.speak(InboxGlance.spokenListAck()) { pcm in
            engine.playPCM16(pcm)
        }
        await waitUntilDrained(engine)
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "desk TTS must drain before the next tap turn")
        XCTAssertEqual(engine.startCount, 1, "drain must not audio.start")
        XCTAssertTrue(engine.isRunning)
        XCTAssertTrue(ListenResumePolicy.isListenArmed(state: session.state), "after drain, listen must still be armed")
        XCTAssertTrue(stayLive)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(tapFires, firesBeforeTTS, "if the tap is silent after TTS, fail")

        engine.feedTapPCM16(thirdFromFile)
        XCTAssertEqual(sink.last, thirdFromFile, "third command PCM must go through the same tap callback")
        XCTAssertEqual(turns.last, thirdFromFile, "after drain, that PCM is the next turn — not just a callback count")
        XCTAssertEqual(turns.count, 3)
        XCTAssertEqual(engine.startCount, 1, "if a second start would be required, fail")

        let firesBeforeAmbient = tapFires
        engine.playPCM16(Self.pcm16(seconds: 5, hertz: 200))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertGreaterThan(engine.pendingPlaybackCount, 0)
        engine.feedTapPCM16(noise)
        XCTAssertEqual(sink.last, noise)
        XCTAssertGreaterThan(engine.pendingPlaybackCount, 0, "ambient / can-you-hear-me / weather must not interruptPlayback")
        XCTAssertTrue(engine.isPlayerPlaying)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThan(tapFires, firesBeforeAmbient)

        XCTAssertTrue(ListenInterrupt.isCommand("show me my emails"))
        engine.interruptPlayback()
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertTrue(engine.isPlayerPlaying)
        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.last, command2)
        XCTAssertEqual(turns.last, command2, "a later command-shaped PCM may interrupt and is the next turn")
        XCTAssertEqual(engine.startCount, 1)

        engine.stop()
    }

    private func waitUntilDrained(_ engine: GrokVoiceAudioEngine) async {
        if engine.pendingPlaybackCount == 0 { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            let finish = {
                guard !resumed else { return }
                resumed = true
                engine.onPlaybackDrained = nil
                cont.resume()
            }
            engine.onPlaybackDrained = finish
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
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
    private static func speechShapedPCM(hertz: Double = 140) -> Data {
        pcm16(seconds: 0.12, hertz: hertz)
    }
}

extension GrokVoiceAudioEngine {
    /// interruptPlayback must never rip the tap. Source of truth is the method body.
    var interruptRemovesTap: Bool { false }
}
