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
                    XCTAssertEqual(walk.leftoverDropped, ["here", "they"], during)
                }
            }
        }
    }

    func testFe1ffc8RearmPathIsGoneFromClientTTS() throws {
        let source = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        XCTAssertFalse(source.contains("resumeCaptureAfterDeskSpeak"), source)
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
