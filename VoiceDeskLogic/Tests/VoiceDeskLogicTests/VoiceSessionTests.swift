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

    func testTurnFinishedKeepsLiveSessionListening() {
        var session = VoiceSession(state: .speaking)
        session.apply(.turnFinished)
        XCTAssertEqual(session.state, .listening)

        session.apply(.turnFinished)
        XCTAssertEqual(session.state, .listening)
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

    func testDeskClaimHoldsThinkingUntilSpeakStarted() {
        var session = VoiceSession(state: .listening)
        session.beginThinking(holdUntilAudio: true)
        XCTAssertEqual(session.state, .thinking)
        XCTAssertTrue(session.holdsThinkingUntilAudio)

        session.apply(.turnFinished)
        XCTAssertEqual(session.state, .thinking, "leftover Grok done must not drop Thinking")

        session.apply(.speakStarted)
        XCTAssertEqual(session.state, .speaking)
        XCTAssertFalse(session.holdsThinkingUntilAudio)
    }

    func testThinkingCancelReturnsIdle() {
        var session = VoiceSession(state: .listening)
        session.beginThinking(holdUntilAudio: true)
        session.apply(.cancel)
        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(session.holdsThinkingUntilAudio)
    }

    func testThinkingTapTalkReturnsIdle() {
        var session = VoiceSession(state: .listening)
        session.beginThinking(holdUntilAudio: true)
        session.apply(.tapTalk)
        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(session.holdsThinkingUntilAudio)
    }

    func testListenFinishedWithoutHoldStillYieldsOnTurnFinished() {
        var session = VoiceSession(state: .listening)
        session.apply(.listenFinished)
        XCTAssertEqual(session.state, .thinking)
        XCTAssertFalse(session.holdsThinkingUntilAudio)
        session.apply(.turnFinished)
        XCTAssertEqual(session.state, .listening)
    }

    func testBeginThinkingFromIdleAndIdempotentWhileThinking() {
        var idle = VoiceSession()
        idle.beginThinking(holdUntilAudio: true)
        XCTAssertEqual(idle.state, .thinking)

        var thinking = VoiceSession(state: .thinking)
        thinking.beginThinking(holdUntilAudio: true)
        XCTAssertEqual(thinking.state, .thinking)
        XCTAssertTrue(thinking.holdsThinkingUntilAudio)
        thinking.apply(.turnFinished)
        XCTAssertEqual(thinking.state, .thinking)
    }

    func testBeginThinkingDoesNotLeaveSpeaking() {
        var session = VoiceSession(state: .speaking)
        session.beginThinking(holdUntilAudio: true)
        XCTAssertEqual(session.state, .speaking)
        XCTAssertFalse(session.holdsThinkingUntilAudio)
    }
}
