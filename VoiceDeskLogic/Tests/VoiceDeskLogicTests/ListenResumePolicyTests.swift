import XCTest
@testable import VoiceDeskLogic

final class ListenResumePolicyTests: XCTestCase {
    func testLeftoverGrokSpeakAndDoneDuringClientTTSDoNotParkSpeaking() {
        XCTAssertFalse(ListenResumePolicy.shouldApplyGrokSpeakStarted(clientTTSSpeaking: true))
        XCTAssertFalse(ListenResumePolicy.shouldApplyGrokTurnFinished(clientTTSSpeaking: true))
        XCTAssertTrue(ListenResumePolicy.shouldApplyGrokTurnFinished(clientTTSSpeaking: false))
        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                audioStarted: true,
                clientTTSInFlight: true
            )
        )
        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: false,
                audioStarted: false,
                clientTTSInFlight: true
            ),
            "desk TTS in flight is stayLive even if listen looks unarmed"
        )
        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                audioStarted: true,
                clientTTSInFlight: false
            ),
            "after drain, stayLive is armed+running, not a stuck TTS flag"
        )
        XCTAssertFalse(
            ListenResumePolicy.sha415c955StayLiveAfterClose1000(
                userWantsVoiceOff: false,
                listenArmed: false
            )
        )
        XCTAssertEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: true,
                closeCode: 1000,
                voiceState: .speaking
            ),
            .reconnect
        )
        XCTAssertEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: false,
                closeCode: 1000,
                voiceState: .speaking
            ),
            .stayIdle,
            "415c955: stayLive=false and not armed is stayIdle"
        )
        XCTAssertEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: false,
                closeCode: 1000,
                voiceState: .idle,
                liveSessionArmed: true
            ),
            .reconnect,
            "live conversation must reconnect on 1000 even if VoiceSession is idle"
        )
    }

    func testLeftoverGrokDuringClientTTSDoesNotParkSpeaking() {
        var session = VoiceSession()
        session.apply(.tapTalk)
        ListenResumePolicy.applyLeftoverGrokDuringClientTTS(&session)
        XCTAssertEqual(session.state, .listening, "leftover created/done must not park speaking")
        XCTAssertTrue(ListenResumePolicy.isListenArmed(state: session.state))
    }

    func testAfterClientTTSFinishedStaysLiveWithoutSecondStart() {
        var session = VoiceSession()
        session.apply(.tapTalk)
        session.apply(.speakStarted)
        XCTAssertFalse(ListenResumePolicy.shouldApplyGrokSpeakStarted(clientTTSSpeaking: true))
        XCTAssertFalse(
            ListenResumePolicy.shouldApplyGrokSpeakStarted(clientTTSSpeaking: false),
            "Grok created must not park .speaking — that disarms listen (415c955)"
        )
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
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: false,
                socketConnected: true
            ),
            .keepListening
        )
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: true,
                socketConnected: true
            ),
            .stayIdle
        )
    }

    func testDeskSpeakUsesClientTTSNotGrokVerbatim() {
        XCTAssertTrue(ListenResumePolicy.deskSpeakUsesClientTTS())
        XCTAssertFalse(ListenResumePolicy.deskSpeakUsesGrokVerbatim())
        XCTAssertTrue(
            GrokRealtime.shouldSpeakViaRealtime(
                usesLiveLoop: true,
                isConnected: true,
                userWantsVoiceOff: false
            ),
            "live Talk is Eve; leftover walks still model offline client TTS"
        )
        XCTAssertFalse(
            GrokRealtime.shouldSpeakViaRealtime(
                usesLiveLoop: true,
                isConnected: false,
                userWantsVoiceOff: false
            ),
            "down socket keeps ClientVoiceSpeech"
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
                socketConnected: true
            ),
            .keepListening
        )
    }

    func testAfterDeskSpeakReconnectsWhenSocketClosedWithoutNewTap() {
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: false,
                socketConnected: false
            ),
            .reconnect
        )
    }

    func testUserStopStaysIdleAfterDeskSpeakAndSocketClose() {
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: true,
                socketConnected: true
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
