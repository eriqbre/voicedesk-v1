import XCTest
@testable import VoiceDeskLogic

/// 18d5878 went green on transcript injects and still failed. Hear proof
/// is write→playPCM16 on the live player, not leftover-echo or rearm.
final class ListenLoopSourceContractTests: XCTestCase {
    func testClientVoiceSpeechWritesPCMToPlayerNotSpeak() throws {
        let tts = try XCTUnwrap(repoFile("VoiceDesk/Voice/ClientVoiceSpeech.swift"))
        XCTAssertTrue(tts.contains("synthesizer.write"), tts)
        XCTAssertTrue(tts.contains("playPCM16") || tts.contains("pcm16LE"), tts)
        XCTAssertFalse(tts.contains("synthesizer.speak("), tts)
        XCTAssertFalse(tts.contains("synthesizer.speak(utterance)"), tts)
        XCTAssertFalse(tts.contains("AVSpeechSynthesizerDelegate"), tts)
    }

    func testSpeakPathDoesNotEchoGateRearmOrStartAfterTTS() throws {
        let speak = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        XCTAssertTrue(speak.contains("ClientVoiceSpeech.shared.speak"), speak)
        XCTAssertTrue(speak.contains("playPCM16"), speak)
        XCTAssertFalse(speak.contains("echoGate"), speak)
        XCTAssertFalse(speak.contains("keepListeningAfterClientTTS"), speak)
        XCTAssertFalse(speak.contains("EchoBargeIn"), speak)
        XCTAssertFalse(speak.contains("resumeCaptureAfterDeskSpeak"), speak)
        XCTAssertFalse(speak.contains("armListenIfSessionLive(reason: \"client tts\")"), speak)
        XCTAssertFalse(speak.contains("EarlyFinalHold"), speak)
        let speakFn = speakSlice(speak, from: "func speak(_ text: String) async {", to: "func sendTextTurn")
        XCTAssertFalse(speakFn.contains("echoGate.beginSpeaking"), speakFn)
        if let writeAt = speakFn.range(of: "ClientVoiceSpeech.shared.speak") {
            let afterWrite = String(speakFn[writeAt.upperBound...])
            XCTAssertFalse(afterWrite.contains("startAudioIfNeeded"), afterWrite)
            XCTAssertFalse(afterWrite.contains("audio.start"), afterWrite)
            XCTAssertFalse(afterWrite.contains("keepListeningAfterClientTTS"), afterWrite)
        } else {
            XCTFail("speak() must call ClientVoiceSpeech.shared.speak")
        }
    }

    func testInterruptPlaybackDoesNotRemoveTap() throws {
        let engine = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceAudioEngine.swift"))
        XCTAssertTrue(engine.contains("func interruptPlayback()"), engine)
        XCTAssertFalse(engine.contains("func resumeCapture"), engine)
        XCTAssertFalse(engine.contains("func rearmTap"), engine)
        let interrupt = engineSlice(engine, from: "func interruptPlayback() {", to: "func feedTapPCM16")
        XCTAssertFalse(interrupt.contains("removeTap"), interrupt)
        XCTAssertTrue(interrupt.contains("playerNode?.play()"), interrupt)
    }

    func testLiveIngressDoesNotLeftoverMatch() throws {
        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        XCTAssertFalse(app.contains("echoGate"), app)
        XCTAssertFalse(app.contains("EchoBargeIn.acceptedUserTranscript"), app)
        XCTAssertTrue(app.contains("handleLiveUser(event.text, itemID: event.itemID)"), app)
    }

    private func speakSlice(_ source: String, from: String, to: String) -> String {
        guard let start = source.range(of: from), let end = source.range(of: to, range: start.upperBound..<source.endIndex) else {
            return source
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func engineSlice(_ source: String, from: String, to: String) -> String {
        speakSlice(source, from: from, to: to)
    }

    private func repoFile(_ relative: String) -> String? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try? String(contentsOf: candidate, encoding: .utf8)
            }
        }
        return nil
    }
}
