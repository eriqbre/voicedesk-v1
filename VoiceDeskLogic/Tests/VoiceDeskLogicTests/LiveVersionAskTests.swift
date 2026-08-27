import XCTest
@testable import VoiceDeskLogic

/// Production handleLiveUser + speakDeskReply on the Linux seam
/// AppModel calls. Not LiveTalkMouth factories. Not source-scrape.
/// L402: local build identity + “VoiceDesk point 1, build 6.” +
/// voicePath Eve realtime. a2727b1 leaves Eve live. The fix does not.
final class LiveVersionAskTests: XCTestCase {
    private let ask = "Good morning. What version are we on?"

    func testA2727b1HandleLiveUserSpeakDeskReplyLeavesEveRealtime() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: true)
        session.handleLiveUser(ask)
        XCTAssertTrue(session.dropAssistantOutput, "claimLocal")
        XCTAssertTrue(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertEqual(session.assistantReply, "VoiceDesk point 1, build 6.")
        XCTAssertEqual(session.voicePath, "Eve realtime")
        XCTAssertTrue(session.routingNotes.contains("local build identity"))
        XCTAssertTrue(session.routingNotes.contains("0.1.0 build 6 sha a2727b1"))
        XCTAssertEqual(session.identityPCM, "VoiceDesk point 1, build 6.")
        session.ingestEveRealtimeDeltaA2727B1()
        XCTAssertTrue(
            session.isDualMouth,
            "a2727b1: desk identity write + Eve realtime on the same version turn"
        )
    }

    func testProductionHandleLiveUserSpeakDeskReplyIsOneMouth() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: true)
        session.handleLiveUser(ask)
        XCTAssertTrue(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertEqual(session.assistantReply, "VoiceDesk point 1, build 6.")
        XCTAssertEqual(session.voicePath, "Eve realtime")
        XCTAssertTrue(session.routingNotes.contains("local build identity"))
        XCTAssertTrue(session.wroteIdentityPCM)
        session.ingestEveRealtimeDelta()
        XCTAssertFalse(
            session.eveRealtimeReachedPlayer,
            "claimLocal + identity write must drop Eve PCM"
        )
        XCTAssertFalse(session.isDualMouth)
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: session.routingNotes,
                assistantReply: session.assistantReply,
                wrotePlayerPCM: session.wroteIdentityPCM
            )
        )
    }

    func testLaterEveTurnStillPlays() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: true)
        session.ingestEveRealtimeDelta()
        XCTAssertTrue(session.eveRealtimeReachedPlayer)
        XCTAssertFalse(session.isDualMouth)
    }
}
