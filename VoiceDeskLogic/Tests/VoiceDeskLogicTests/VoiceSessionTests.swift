import XCTest
@testable import VoiceDeskLogic

final class VoiceSessionTests: XCTestCase {
    func testTapTalkLoop() {
        var session = VoiceSession()
        XCTAssertEqual(session.state, .idle)

        session.apply(.tapTalk)
        XCTAssertEqual(session.state, .listening)

        session.apply(.listenFinished)
        XCTAssertEqual(session.state, .thinking)

        session.apply(.speakStarted)
        XCTAssertEqual(session.state, .speaking)

        session.apply(.speakFinished)
        XCTAssertEqual(session.state, .idle)
    }

    func testTapDuringListenOrSpeakCancels() {
        var listening = VoiceSession(state: .listening)
        listening.apply(.tapTalk)
        XCTAssertEqual(listening.state, .idle)

        var speaking = VoiceSession(state: .speaking)
        speaking.apply(.tapTalk)
        XCTAssertEqual(speaking.state, .idle)
    }

    func testCancelAbortsAnyState() {
        for state: VoiceState in [.idle, .listening, .thinking, .speaking] {
            var session = VoiceSession(state: state)
            session.apply(.cancel)
            XCTAssertEqual(session.state, .idle, "cancel from \(state)")
        }
    }

    func testWakeWordArmDisarm() {
        var wake = WakeWordSession()
        XCTAssertFalse(wake.isArmed)
        wake.arm()
        XCTAssertTrue(wake.isArmed)
        wake.disarm()
        XCTAssertFalse(wake.isArmed)
    }
}
