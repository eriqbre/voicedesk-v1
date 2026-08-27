import XCTest
@testable import VoiceDeskLogic

/// a2727b1 restore-walk L420+L421: desk identity write + Eve stayLive
/// on the same version second. Mute-flag tokens are not in the window.
final class FirstAskOneMouthTests: XCTestCase {
    func testA2727b1RestoreWalkVersionIsDeskIdentityPlusEveRealtime() throws {
        let records = A2727B1Walk.bakedRestoreWalk
        let start = try XCTUnwrap(A2727B1Walk.audioStart(in: records))
        XCTAssertEqual(start.source, ListenResumeLog.source)
        XCTAssertEqual(start.intent, ListenResumeLog.intent)
        XCTAssertTrue(start.routingNotes.contains(where: { $0.contains("audio.start") }))
        XCTAssertEqual(start.assistantReply, "")

        let drain = try XCTUnwrap(A2727B1Walk.drain(in: records))
        XCTAssertEqual(drain.source, ListenResumeLog.source)
        XCTAssertEqual(drain.intent, ListenResumeLog.intent)
        XCTAssertEqual(drain.routingNotes, [A2727B1Walk.drainNote])

        let version = try XCTUnwrap(A2727B1Walk.versionTurn(in: records))
        XCTAssertEqual(version.source, "live voice")
        XCTAssertEqual(version.userTranscript, A2727B1Walk.versionAsk)
        XCTAssertEqual(version.intent, "version")
        XCTAssertTrue(version.routingNotes.contains(A2727B1Walk.versionIdentityNote))
        XCTAssertTrue(version.routingNotes.contains(A2727B1Walk.versionDogfoodNote))
        XCTAssertEqual(version.assistantReply, A2727B1Walk.spokenIdentity)
        XCTAssertEqual(version.cardsAttached, [])
        XCTAssertEqual(version.voicePath, A2727B1Walk.eveRealtime)
        XCTAssertFalse(
            version.routingNotes.contains(where: { $0.contains("eve speaks identity") })
        )
        XCTAssertTrue(
            A2727B1Walk.versionIsDualMouth(in: records),
            "desk identity write + Eve realtime on the same version turn"
        )
        XCTAssertTrue(A2727B1Walk.versionIsDualMouth(in: records))
        XCTAssertTrue(ConversationPresence.wantsVersionAsk(A2727B1Walk.versionAsk))
        XCTAssertTrue(A2727B1Walk.versionIsDualMouth())
        XCTAssertTrue(A2727B1Walk.versionHasNoFirstAudioWhileDeskDrained(in: records))
        XCTAssertTrue(A2727B1Walk.diedStayIdleAfterLastReply(in: records))
        XCTAssertFalse(A2727B1Walk.mentionsMuteFlagTokens(in: records))
    }

    func testFirstAskDeskPlusEveIsTwoMouthsAndFixIsEveOnly() {
        XCTAssertTrue(A2727B1Walk.versionIsDualMouth())
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: A2727B1Walk.spokenIdentity,
                identityLine: A2727B1Walk.spokenIdentity
            )
        )
    }

    func testVersionAskKeepsEveMouthAndDoesNotWriteDesk() {
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true
            ),
            "Eve must finish; version ask is not a barge cut"
        )
        XCTAssertTrue(
            ConversationPresence.wantsVersionAsk("Hey, good morning. What version are we on?")
        )
        XCTAssertFalse(ConversationPresence.wantsVersionAsk("Can you hear me?"))
        let identity = ConversationPresence.spokenIdentityLine(
            for: "Hey, good morning. What version are we on?",
            identity: .fixture
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: identity,
                identityLine: identity
            ),
            "live VAD desk identity write is the second mouth"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: ["local build identity"],
                assistantReply: identity,
                wrotePlayerPCM: false
            )
        )
    }

    /// a2727b1: desk write→player AND Eve live VAD PCM. Mute flags
    /// tried to hide Eve and stuck. Live Talk is Eve only.
    func testIdentityWriteAndEveDeltasBothReachPlayerIsTheHole() {
        XCTAssertTrue(A2727B1Walk.versionIsDualMouth())
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: A2727B1Walk.spokenIdentity,
                identityLine: A2727B1Walk.spokenIdentity
            )
        )
    }
}
