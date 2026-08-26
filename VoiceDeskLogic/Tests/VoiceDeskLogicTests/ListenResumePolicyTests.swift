import XCTest
@testable import VoiceDeskLogic

final class ListenResumePolicyTests: XCTestCase {
    func testAfterClientTTSFinishedStaysLiveWithoutSecondStart() {
        var session = VoiceSession()
        session.apply(.tapTalk)
        session.apply(.speakStarted)
        XCTAssertFalse(ListenResumePolicy.shouldApplyGrokSpeakStarted(clientTTSSpeaking: true))
        XCTAssertTrue(ListenResumePolicy.shouldApplyGrokSpeakStarted(clientTTSSpeaking: false))
        let after = ListenResumePolicy.afterClientTTSFinished(
            session: &session,
            userWantsVoiceOff: false,
            liveSessionArmed: true,
            captureRunning: true
        )
        XCTAssertTrue(after.listenArmed)
        XCTAssertTrue(after.stayLive)
        XCTAssertNotEqual(after.close1000, .stayIdle)
        XCTAssertFalse(after.startAgain)
        XCTAssertEqual(session.state, .listening)

        var stopped = VoiceSession(state: .listening)
        let idle = ListenResumePolicy.afterClientTTSFinished(
            session: &stopped,
            userWantsVoiceOff: true,
            liveSessionArmed: true,
            captureRunning: true
        )
        XCTAssertFalse(idle.stayLive)
        XCTAssertEqual(idle.close1000, .stayIdle)
        XCTAssertFalse(idle.listenArmed)
    }

    func testListenStaysLiveThroughClientTTS() {
        XCTAssertTrue(ListenResumePolicy.shouldArmListenAfterClientTTS(ttsFinished: false))
        XCTAssertTrue(ListenResumePolicy.shouldArmListenAfterClientTTS(ttsFinished: true))
        XCTAssertEqual(
            ListenResumePolicy.afterClientTTS(
                ttsFinished: false,
                userWantsVoiceOff: false,
                socketConnected: true,
                captureRunning: true
            ),
            .keepListening
        )
        XCTAssertEqual(
            ListenResumePolicy.afterClientTTS(
                ttsFinished: true,
                userWantsVoiceOff: false,
                socketConnected: true,
                captureRunning: false
            ),
            .keepListening
        )
        XCTAssertEqual(
            ListenResumePolicy.afterClientTTS(
                ttsFinished: false,
                userWantsVoiceOff: true,
                socketConnected: true,
                captureRunning: false
            ),
            .stayIdle
        )
    }

    func testDeskSpeakUsesClientTTSNotGrokVerbatim() {
        XCTAssertTrue(ListenResumePolicy.deskSpeakUsesClientTTS())
        XCTAssertFalse(ListenResumePolicy.deskSpeakUsesGrokVerbatim())
        XCTAssertFalse(
            GrokRealtime.shouldSpeakViaRealtime(
                usesLiveLoop: true,
                isConnected: true,
                userWantsVoiceOff: false
            ),
            "desk lines must not inject a fake Grok turn"
        )
    }

    func testClose1000AfterDeskSpeakReconnectsWhenLiveSessionArmed() {
        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: true
            )
        )
        XCTAssertEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: true,
                closeCode: 1000,
                voiceState: .idle
            ),
            .reconnect,
            "697147d: close 1000 after a desk line is not user-stop"
        )
        XCTAssertNotEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: true,
                closeCode: 1000,
                voiceState: .idle
            ),
            .stayIdle
        )
        XCTAssertEqual(
            ListenResumePolicy.afterRealtimeTimeout(
                userWantsVoiceOff: false,
                liveSessionArmed: true
            ),
            .reconnect
        )
        XCTAssertFalse(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: true,
                liveSessionArmed: true
            )
        )
    }

    func testAfterDeskSpeakKeepsListeningWhenSocketOpen() {
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: false,
                socketConnected: true,
                captureRunning: false
            ),
            .keepListening
        )
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: false,
                socketConnected: true,
                captureRunning: true
            ),
            .keepListening
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

    func testNormalClose1000WhileIdleStillReconnectsWhenLiveSessionArmed() {
        XCTAssertTrue(ListenResumePolicy.isNormalClose(1000))
        XCTAssertTrue(ListenResumePolicy.isNormalClose(1001))
        XCTAssertFalse(ListenResumePolicy.isNormalClose(1006))

        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: true
            )
        )
        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: false,
                audioStarted: true
            ),
            "audio.start / warmUp is live unless they tapped stop"
        )
        XCTAssertFalse(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: false,
                audioStarted: false
            ),
            "never opened audio and never tapped must not reconnect a 1000"
        )
        XCTAssertFalse(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: true,
                liveSessionArmed: true
            )
        )

        XCTAssertEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: true,
                closeCode: 1000,
                voiceState: .idle
            ),
            .reconnect,
            "4ac127a: code 1000 + idle is not user-stop"
        )
        XCTAssertEqual(
            ListenResumePolicy.afterRealtimeTimeout(
                userWantsVoiceOff: false,
                liveSessionArmed: true
            ),
            .reconnect
        )
        XCTAssertEqual(
            ListenResumePolicy.afterRealtimeTimeout(
                userWantsVoiceOff: true,
                liveSessionArmed: true
            ),
            .stayIdle
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
