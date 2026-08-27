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
        XCTAssertTrue(fake.stayLiveAfterSpeak)
        XCTAssertTrue(fake.listenArmedAfterSpeak)
        XCTAssertFalse(fake.parkedSpeaking, "leftover created/done must not park speaking")
        XCTAssertNotEqual(fake.close1000AfterSpeak, .stayIdle)
        XCTAssertEqual(fake.startCount, 0, "client TTS must not relaunch audio.start")
        XCTAssertEqual(
            model.turns.filter { $0.role == .user }.map(\.text),
            ["what version are we on", "show me my emails", "Murray"]
        )
    }

    func testEriqSpokenTapeOneInjectDuringClientTTSLands() async {
        let snapshot = DeskSnapshot(emails: [SampleData.syncedEmail()])
        // Fresh model per line. Reusing one AppModel skips the second
        // "Here they are." (`DeskReplySpeech` exact-duplicate), so
        // speak / onClientTTS never fire and injects stays 0.
        for line in EriqSpokenTape.lines {
            let fake = FakeLiveVoiceService()
            let model = AppModel(
                voice: fake,
                google: .mock(connected: true),
                cache: MemoryDeskCache(snapshot: snapshot),
                sync: MockGoogleSync(result: snapshot),
                buildIdentity: .fixture
            )
            var injects = 0
            fake.onClientTTS = {
                injects += 1
                fake.emitUser(line)
            }
            await model.applyUserTurn("show me my emails")
            XCTAssertTrue(
                fake.spoken.contains { InboxGlance.isShortSpokenAck($0) },
                "client TTS must speak so the inject is during/after speak: \(line)"
            )
            XCTAssertEqual(injects, 1, line)
            XCTAssertTrue(fake.tapLive, line)
            XCTAssertTrue(fake.stayLiveAfterSpeak, line)
            XCTAssertTrue(fake.listenArmedAfterSpeak, line)
            XCTAssertFalse(fake.parkedSpeaking, line)
            XCTAssertNotEqual(fake.close1000AfterSpeak, .stayIdle, line)
            XCTAssertEqual(fake.startCount, 0, "no second audio.start: \(line)")
            XCTAssertEqual(
                model.turns.filter { $0.role == .user }.map(\.text),
                ["show me my emails", line],
                line
            )
        }
    }

    func testListenResumePolicyKeepsListeningAfterDeskSpeak() {
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: false,
                socketConnected: true
            ),
            .keepListening
        )
    }
}
