import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

/// No-user first-hear. Would have failed fe1ffc8: tap died until
/// resumeCapture, so one inject during/after client TTS never landed.
@MainActor
final class FirstHearListenLoopTests: XCTestCase {
    func testTwoTurnsThenOneInjectDuringClientTTSLands() async {
        let snapshot = DeskSnapshot(emails: [SampleData.syncedEmail()])
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot),
            buildIdentity: .fixture
        )

        await model.applyUserTurn("what version are we on")
        XCTAssertEqual(model.turns.filter { $0.role == .user }.count, 1)
        XCTAssertTrue(fake.spoken.contains { $0.contains("VoiceDesk") })
        XCTAssertTrue(fake.tapLive)

        fake.onClientTTS = {
            fake.emitUser("Murray")
        }
        await model.applyUserTurn("show me my emails")
        XCTAssertTrue(fake.spoken.contains { InboxGlance.isShortSpokenAck($0) })
        XCTAssertTrue(fake.tapLive, "client TTS must not tear down the tap")
        XCTAssertEqual(
            model.turns.filter { $0.role == .user }.map(\.text),
            ["what version are we on", "show me my emails", "Murray"]
        )
    }

    func testProductSpeakDoesNotRearmTapAfterClientTTS() throws {
        var url = URL(fileURLWithPath: #filePath)
        var source: String?
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("VoiceDesk/Voice/GrokVoiceService.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                source = try? String(contentsOf: candidate, encoding: .utf8)
                break
            }
        }
        let text = try XCTUnwrap(source)
        XCTAssertFalse(text.contains("resumeCaptureAfterDeskSpeak"), text)
        XCTAssertFalse(text.contains("armListenIfSessionLive(reason: \"client tts\")"), text)
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
}
