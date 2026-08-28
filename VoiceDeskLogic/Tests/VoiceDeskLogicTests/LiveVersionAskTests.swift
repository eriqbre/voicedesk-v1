import XCTest
@testable import VoiceDeskLogic

/// Helper only. Live VAD `AppModel.speakDeskReply` bypasses
/// `LiveVersionAsk.speakDeskReply` and calls `voice.speak`.
/// Production speak proof is `GrokVoiceServiceSpeakTests`.
final class LiveVersionAskTests: XCTestCase {

    func testHelperRefusesLiveVADDeskWrite() {
        var session = LiveVersionAsk(
            identity: .a2727b1Walk,
            liveVADTurn: true
        )
        XCTAssertTrue(session.handleLiveUser(A2727B1Walk.versionAsk))
        XCTAssertFalse(
            session.speakDeskReply(session.spokenIdentityLine),
            "helper still refuses desk PCM; AppModel live VAD does not use this return"
        )
        XCTAssertFalse(session.wroteIdentityPCM)
        XCTAssertEqual(session.spokenLoopMouth, .eve)
        XCTAssertTrue(A2727B1Walk.versionIsDualMouth())
    }

    func testHelperOfflineVersionStillWritesIdentityNotEmptyEveLie() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: false)
        XCTAssertTrue(session.handleLiveUser(A2727B1Walk.versionAsk))
        XCTAssertTrue(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertTrue(session.wroteIdentityPCM)
        XCTAssertEqual(session.spokenLoopMouth, .desk)
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: session.routingNotes,
                assistantReply: session.assistantReply,
                wrotePlayerPCM: session.wroteIdentityPCM
            )
        )
    }

    func testSessionStaysListeningAfterEmailReply() {
        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                audioStarted: true
            )
        )
        let decision = ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: false,
            sessionShouldStayLive: true,
            closeCode: 1000,
            voiceState: .idle,
            liveSessionArmed: true
        )
        XCTAssertEqual(decision, .reconnect)
        XCTAssertFalse(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: false,
                audioStarted: false
            )
        )
    }
}
