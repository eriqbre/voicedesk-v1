import XCTest
@testable import VoiceDeskLogic

/// fe1ffc8 walk: version + today’s emails landed on resumeCapture; the
/// next first-ask lived in a 43s hole (no leftover-echo, no hold). One
/// inject during/after client TTS must land without a second shot.
final class FirstHearListenLoopTests: XCTestCase {
    static let firstFamily = [
        "what version are we on",
        "what build is this"
    ]

    static let secondFamily = [
        "show me my emails",
        "today's emails",
        "see my latest emails"
    ]

    static let duringFamily = [
        "Murray",
        "show calendar",
        "what's on my calendar"
    ]

    func testTwoTurnsThenOneInjectDuringClientTTSLands() {
        let spoken = InboxGlance.spokenListAck()
        XCTAssertEqual(spoken, "Here they are.")
        for first in Self.firstFamily {
            for second in Self.secondFamily {
                for during in Self.duringFamily {
                    let walk = FirstHearListenLoop.twoTurnsThenOneDuringClientTTS(
                        first: first,
                        second: second,
                        spokenAfterSecond: spoken,
                        duringTTS: during
                    )
                    XCTAssertEqual(walk.landed, [first, second, during], "\(first) / \(second) / \(during)")
                    XCTAssertTrue(walk.tapLive, during)
                    XCTAssertTrue(walk.listenArmed, during)
                    XCTAssertTrue(walk.stayLive, "session must stay live after client TTS: \(during)")
                    XCTAssertNotEqual(walk.close1000, .stayIdle, during)
                    XCTAssertEqual(walk.startCount, 1, "no second audio.start: \(during)")
                }
            }
        }
    }

    func testFe1ffc8RearmPathIsGoneFromClientTTS() throws {
        let source = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        XCTAssertFalse(source.contains("resumeCaptureAfterDeskSpeak"), source)
        XCTAssertTrue(source.contains("playPCM16"), source)
        XCTAssertFalse(source.contains("keepListeningAfterClientTTS"), source)
        XCTAssertFalse(source.contains("echoGate"), source)
        XCTAssertFalse(source.contains("armListenIfSessionLive(reason: \"client tts\")"), source)
        XCTAssertFalse(
            source.contains("echoGate.beginSpeaking(trimmed)\n        apply(.speakStarted)"),
            source
        )
        XCTAssertEqual(
            ListenResumePolicy.afterClientTTS(
                ttsFinished: false,
                userWantsVoiceOff: false,
                socketConnected: true,
                captureRunning: true
            ),
            .keepListening
        )
        let engine = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceAudioEngine.swift"))
        XCTAssertFalse(engine.contains("func resumeCapture"), engine)
        XCTAssertFalse(engine.contains("func rearmTap"), engine)
    }

    func testFa72e1cSpeakStartedWithoutKeepListenDropsTheNextAsk() {
        let dead = FirstHearListenLoop.fa72e1cSpeakStartedWithoutKeepListen()
        XCTAssertFalse(dead.listenArmed, "fa72e1c left VoiceSession speaking")
        XCTAssertTrue(dead.landed.isEmpty, "next ask must not land until keep-listen")
        XCTAssertEqual(dead.startCount, 1)

        let live = FirstHearListenLoop.twoTurnsThenOneDuringClientTTS(
            first: "what version are we on",
            second: "show me my emails",
            spokenAfterSecond: InboxGlance.spokenListAck(),
            duringTTS: "Tell me Murray's latest email."
        )
        XCTAssertEqual(live.landed.last, "Tell me Murray's latest email.")
        XCTAssertTrue(live.listenArmed)
        XCTAssertTrue(live.stayLive)
        XCTAssertNotEqual(live.close1000, .stayIdle)
        XCTAssertEqual(live.startCount, 1)
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
