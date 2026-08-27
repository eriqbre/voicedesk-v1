import XCTest
@testable import VoiceDeskLogic

/// Live version seam AppModel.handleLiveUser / speakDeskReply call.
/// Desk identity write on live VAD is a2727b1 two-mouth. Not the
/// SpokenLoopLog fixture gate.
final class LiveVersionAskTests: XCTestCase {

    func testOneMouthOnVersionDoesNotPlayDeskIdentityAndEveOnTheSameTurn() {
        var session = LiveVersionAsk(
            identity: .a2727b1Walk,
            liveVADTurn: true
        )
        XCTAssertTrue(session.handleLiveUser(A2727B1Walk.versionAsk))
        XCTAssertFalse(
            session.speakDeskReply(session.spokenIdentityLine),
            "desk identity write on live VAD is the second mouth"
        )
        XCTAssertFalse(session.wroteIdentityPCM)
        XCTAssertEqual(session.spokenLoopMouth, .eve)
        XCTAssertTrue(A2727B1Walk.versionIsDualMouth())
        XCTAssertEqual(LiveEveSpeak.plan(text: "1.2.3", socketConnected: true).mouth, .eve)
    }

    func testEveFinishesTheTurnWithoutVoiceCut() {
        var session = LiveVersionAsk(
            identity: .a2727b1Walk,
            liveVADTurn: true
        )
        XCTAssertTrue(session.handleLiveUser(A2727B1Walk.versionAsk))
        XCTAssertFalse(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true
            )
        )
        XCTAssertTrue(LiveVADPlayerKeep.c1cd758Regression().voiceCutsAfterFirstDelta)
        XCTAssertFalse(
            LiveVADPlayerKeep.oneMouthFullReply(cardCount: 1).voiceCutsAfterFirstDelta
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: session.routingNotes,
                assistantReply: session.assistantReply,
                wrotePlayerPCM: false
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

    func testOfflineVersionStillWritesIdentityNotEmptyEveLie() {
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
}
