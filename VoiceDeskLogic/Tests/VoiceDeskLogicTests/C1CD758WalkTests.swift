import XCTest
@testable import VoiceDeskLogic

/// Device walk 16:45:39–16:48:25Z on c1cd758 (last 6 jsonl records).
/// Version logged `eve speaks identity` with empty assistantReply and
/// no write→player. 83a5c6a spoke “VoiceDesk point 1, build 6.”
/// Also: first-delta voice cut; show-latest cards missing (Eriq).
final class C1CD758WalkTests: XCTestCase {
    func testWalkLastSixVersionIsEmptyEveSpeaksIdentityLie() throws {
        let records = C1CD758Walk.lastSix
        XCTAssertEqual(records.count, 6)
        XCTAssertEqual(records[0].intent, ListenResumeLog.intent)
        XCTAssertTrue(records[0].routingNotes[0].contains("audio.start"), records[0].routingNotes[0])
        XCTAssertTrue(records[0].assistantReply.isEmpty)

        let version = try XCTUnwrap(C1CD758Walk.versionTurn(in: records))
        XCTAssertEqual(version.userTranscript, C1CD758Walk.versionAsk)
        XCTAssertEqual(version.intent, "version")
        XCTAssertTrue(version.routingNotes.contains(C1CD758Walk.versionIdentityNote), "\(version.routingNotes)")
        XCTAssertTrue(version.routingNotes.contains(where: { $0.contains("0.1.0 build 6 sha c1cd758") }))
        XCTAssertTrue(version.assistantReply.isEmpty, "walk assistantReply was empty")
        XCTAssertEqual(version.cardsAttached, [])
        XCTAssertTrue(
            C1CD758Walk.isEmptyEveSpeaksIdentity(version),
            "c1cd758 version: eve speaks identity + empty reply + no PCM"
        )
        XCTAssertTrue(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: version.routingNotes,
                assistantReply: version.assistantReply,
                wrotePlayerPCM: false
            )
        )

        let close = records[5]
        XCTAssertEqual(close.intent, ListenResumeLog.intent)
        XCTAssertTrue(close.routingNotes[0].contains("session close code=1000"), close.routingNotes[0])
        XCTAssertTrue(close.routingNotes[0].contains("stayLive=false"), close.routingNotes[0])
    }

    func testFixWritesIdentityToPlayerNotEmptyEveLie() {
        let identity = ConversationPresence.spokenIdentityLine(
            for: C1CD758Walk.versionAsk,
            identity: .fixture
        )
        XCTAssertEqual(identity, C1CD758Walk.spokenIdentity83a5c6a)
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: identity,
                identityLine: identity
            ),
            "live VAD desk write is a second mouth; Eve speaks identity"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: InboxGlance.spokenListAck(),
                identityLine: identity
            ),
            "do not write the list stub"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: "",
                identityLine: identity
            )
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: ["local build identity", BuildIdentity.fixture.dogfoodLine],
                assistantReply: identity,
                wrotePlayerPCM: false
            )
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true
            )
        )
        let cards = LiveVADPlayerKeep.oneMouthFullReply(cardCount: 5)
        XCTAssertFalse(cards.isCardlessBlob)
        XCTAssertTrue(cards.remainingDeltasReachPlayer)
        XCTAssertFalse(LiveVADPlayerKeep.c1cd758Regression().remainingDeltasReachPlayer)
    }

    func testShowLatestIsNotACardlessBlob() {
        let snapshot = DeskSnapshot(
            accountEmail: "agent@example.com",
            lastSyncedAt: Date(timeIntervalSince1970: 1_777_000_000).addingTimeInterval(-52),
            emails: [
                VoiceRegressionDesk.greenacre,
                VoiceRegressionDesk.murray,
                VoiceRegressionDesk.steve,
                VoiceRegressionDesk.laren,
                VoiceRegressionDesk.ericGross
            ]
        )
        for ask in ["show my latest emails", "Show me my latest emails.", "okay show me my latest emails"] {
            let evidence = ConversationPresence.deskEvidence(
                for: ask,
                context: DeskContext(isConnected: true, snapshot: snapshot)
            )
            XCTAssertGreaterThan(evidence?.cards.count ?? 0, 0, ask)
            XCTAssertTrue(evidence?.shouldGlanceInbox == true, ask)
            XCTAssertFalse(
                LiveVADPlayerKeep.oneMouthFullReply(cardCount: evidence?.cards.count ?? 0).isCardlessBlob,
                ask
            )
        }
    }
}
