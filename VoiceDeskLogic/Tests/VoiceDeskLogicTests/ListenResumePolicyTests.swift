import XCTest
@testable import VoiceDeskLogic

final class ListenResumePolicyTests: XCTestCase {
    func testAfterDeskSpeakResumesCaptureWhenSocketOpen() {
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: false,
                socketConnected: true,
                captureRunning: false
            ),
            .resumeCapture
        )
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: false,
                socketConnected: true,
                captureRunning: true
            ),
            .resumeCapture,
            "after desk TTS, isRunning is not proof the tap still hears"
        )
    }

    func testAfterDeskSpeakReconnectsWhenSocketClosedWithoutNewTap() {
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: false,
                socketConnected: false,
                captureRunning: false
            ),
            .reconnect
        )
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: false,
                socketConnected: false,
                captureRunning: true
            ),
            .reconnect
        )
    }

    func testUserStopStaysIdleAfterDeskSpeakAndSocketClose() {
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: true,
                socketConnected: true,
                captureRunning: false
            ),
            .stayIdle
        )
        XCTAssertEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: true,
                sessionShouldStayLive: true
            ),
            .stayIdle
        )
        XCTAssertEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: false
            ),
            .stayIdle
        )
        XCTAssertEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: true
            ),
            .reconnect
        )
    }

    func testSessionReturnsToListeningAfterDeskSpeakFromAnyLiveState() {
        for start: VoiceState in [.listening, .thinking, .speaking, .idle] {
            var session = VoiceSession(state: start)
            ListenResumePolicy.applySessionAfterDeskSpeak(&session)
            XCTAssertTrue(
                ListenResumePolicy.isListenArmed(state: session.state),
                "after desk speak from \(start) must be listening, got \(session.state)"
            )
        }
    }

    func testCaptureArmedRequiresLiveSocketRunningMicAndListening() {
        XCTAssertTrue(
            ListenResumePolicy.isCaptureArmed(
                userWantsVoiceOff: false,
                socketConnected: true,
                captureRunning: true,
                voiceState: .listening
            )
        )
        XCTAssertFalse(
            ListenResumePolicy.isCaptureArmed(
                userWantsVoiceOff: false,
                socketConnected: true,
                captureRunning: true,
                voiceState: .speaking
            ),
            "still speaking is not armed listen"
        )
        XCTAssertFalse(
            ListenResumePolicy.isCaptureArmed(
                userWantsVoiceOff: false,
                socketConnected: true,
                captureRunning: false,
                voiceState: .listening
            )
        )
        XCTAssertFalse(
            ListenResumePolicy.isCaptureArmed(
                userWantsVoiceOff: false,
                socketConnected: false,
                captureRunning: true,
                voiceState: .listening
            )
        )
        XCTAssertFalse(
            ListenResumePolicy.isCaptureArmed(
                userWantsVoiceOff: true,
                socketConnected: true,
                captureRunning: true,
                voiceState: .listening
            )
        )
    }

    func testEngineLogLineIsCompactAndNotAUserTurn() {
        let entry = ListenResumeLog.entry(
            note: "audio.start Audio engine running running=true",
            errors: []
        )
        XCTAssertEqual(entry.source, "engine")
        XCTAssertEqual(entry.intent, "listen-resume")
        XCTAssertEqual(entry.userTranscript, "")
        XCTAssertEqual(entry.routingNotes, ["audio.start Audio engine running running=true"])
        XCTAssertTrue(entry.errors.isEmpty)
        XCTAssertEqual(entry.voicePath, "Eve realtime")

        let close = ListenResumeLog.entry(
            note: "session close code=1000 reason= state=listening",
            errors: ["Mic input has zero sample rate"]
        )
        XCTAssertEqual(close.intent, ListenResumeLog.intent)
        XCTAssertEqual(close.errors, ["Mic input has zero sample rate"])
    }
}
