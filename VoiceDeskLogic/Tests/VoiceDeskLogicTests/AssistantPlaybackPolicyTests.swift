import XCTest
@testable import VoiceDeskLogic

final class AssistantPlaybackPolicyTests: XCTestCase {
    func testHalfDuplexOnlyWhenAudioWillPlay() {
        XCTAssertTrue(
            AssistantPlaybackPolicy.shouldEnterHalfDuplex(
                dropAssistantAudio: false,
                verbatimSpeaking: false
            ),
            "general weather / John Wick must enter speaking"
        )
        XCTAssertTrue(
            AssistantPlaybackPolicy.shouldEnterHalfDuplex(
                dropAssistantAudio: true,
                verbatimSpeaking: true
            ),
            "Eve desk digest must half-duplex"
        )
        XCTAssertFalse(
            AssistantPlaybackPolicy.shouldEnterHalfDuplex(
                dropAssistantAudio: true,
                verbatimSpeaking: false
            ),
            "suppressed handoff must not stick in speaking"
        )
    }

    func testDeskMuteDoesNotRestoreAfterVerbatim() {
        XCTAssertFalse(
            AssistantPlaybackPolicy.restoreSuppressAfterVerbatim,
            "weather after inbox must not inherit desk-claim mute"
        )
    }

    func testSilentSpeakingWatchdog() {
        XCTAssertFalse(
            AssistantPlaybackPolicy.shouldForceEndSpeaking(audioDeltaCount: 0, elapsed: 1)
        )
        XCTAssertTrue(
            AssistantPlaybackPolicy.shouldForceEndSpeaking(audioDeltaCount: 0, elapsed: 4)
        )
        XCTAssertFalse(
            AssistantPlaybackPolicy.shouldForceEndSpeaking(audioDeltaCount: 3, elapsed: 5),
            "real Eve audio must not be cut by the watchdog"
        )
    }

    func testThinkingWatchdogAndVerbatimSpeakGate() {
        XCTAssertFalse(AssistantPlaybackPolicy.shouldForceEndThinking(elapsed: 1))
        XCTAssertTrue(AssistantPlaybackPolicy.shouldForceEndThinking(elapsed: 4))
        XCTAssertTrue(
            AssistantPlaybackPolicy.shouldSpeakVerbatim(
                reply: "Murray wrote: notarize today.",
                liveConnected: true,
                userWantsVoiceOff: false
            )
        )
        XCTAssertFalse(
            AssistantPlaybackPolicy.shouldSpeakVerbatim(
                reply: "Murray wrote: notarize today.",
                liveConnected: true,
                userWantsVoiceOff: true
            ),
            "tap-stop must not AVSpeech / verbatim after voice-off"
        )
        XCTAssertFalse(
            AssistantPlaybackPolicy.shouldSpeakVerbatim(
                reply: "   ",
                liveConnected: true,
                userWantsVoiceOff: false
            )
        )
    }

    func testErrorRecoveryReturnsToListening() {
        var session = VoiceSession(state: .listening)
        session.apply(.speakStarted)
        XCTAssertEqual(session.state, .speaking)
        session.apply(.turnFinished)
        XCTAssertEqual(session.state, .listening)
    }
}
