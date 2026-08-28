import XCTest
@testable import VoiceDeskLogic

/// c1cd758 hole vs 83a5c6a: after the first output_audio.delta, same-turn
/// interruptResponse cancelled A. No second create. Voice quit. Glance
/// cards never landed on the streaming turn (blob). Prefetch
/// session.update mid-A stalled printed transcripts.
///
/// One mouth: keep A's PCM on the player. Cards on first delta.
/// Stream text as it arrives. No client “Here they are.” first audio.
final class LiveVADPlayerKeepAliveTests: XCTestCase {
    static let showLatestFamily = [
        "show-latest-emails",
        "show my latest emails",
        "Show me my latest emails.",
        "okay show me my latest emails"
    ]

    private var now: Date {
        Date(timeIntervalSince1970: 1_777_000_000)
    }

    private var hotSnapshot: DeskSnapshot {
        DeskSnapshot(
            accountEmail: "agent@example.com",
            lastSyncedAt: now.addingTimeInterval(-52),
            emails: [
                VoiceRegressionDesk.greenacre,
                VoiceRegressionDesk.murray,
                VoiceRegressionDesk.steve,
                VoiceRegressionDesk.laren,
                VoiceRegressionDesk.ericGross
            ]
        )
    }

    func testC1cd758CutsVoiceAfterFirstDeltaAndFixKeepsPlayer() {
        let hole = LiveVADPlayerKeep.c1cd758Regression()
        XCTAssertTrue(hole.firstDeltaOnPlayer)
        XCTAssertTrue(hole.sameTurnInterruptCancelledFirstAnswer)
        XCTAssertFalse(hole.sentSecondCreate)
        XCTAssertTrue(
            hole.voiceCutsAfterFirstDelta,
            "c1cd758 latched A cancelled after the first delta; no B"
        )
        XCTAssertFalse(hole.remainingDeltasReachPlayer)
        XCTAssertTrue(hole.isCardlessBlob)
        XCTAssertTrue(hole.dumpsTranscriptLate)
        XCTAssertFalse(hole.isOneMouthFullReply)

        let keep = LiveVADPlayerKeep.oneMouthFullReply(cardCount: 5)
        XCTAssertFalse(keep.sameTurnInterruptCancelledFirstAnswer)
        XCTAssertFalse(keep.sentSecondCreate)
        XCTAssertFalse(keep.voiceCutsAfterFirstDelta)
        XCTAssertTrue(keep.remainingDeltasReachPlayer)
        XCTAssertFalse(keep.isCardlessBlob)
        XCTAssertFalse(keep.dumpsTranscriptLate)
        XCTAssertTrue(keep.isOneMouthFullReply)
    }

    func testSameTurnFirstAnswerMustNotBeInterrupted() {
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true
            ),
            "first-answer PCM on the player is the one mouth"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: true,
                hasPendingPlayback: true
            ),
            "speech_started already dropped leftover"
        )
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: false
            )
        )
    }

    func testPresenceUpdateWaitsUntilIdleAndTranscriptsAreNotBuffered() {
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldSendPresenceSessionUpdate(responseInFlight: true),
            "session.update mid-A cut voice and stalled print"
        )
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldSendPresenceSessionUpdate(responseInFlight: false)
        )
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldAttachCardsOnFirstTranscriptDelta(liveVADTurn: true)
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldAttachCardsOnFirstTranscriptDelta(liveVADTurn: false)
        )
    }

    func testShowLatestFamilyGetsCardsNotABlob() {
        let snapshot = hotSnapshot
        for ask in Self.showLatestFamily {
            XCTAssertTrue(
                ConversationPresence.wantsInboxOverview(ask)
                    || ask == "show-latest-emails",
                ask
            )
            let evidence = ConversationPresence.deskEvidence(
                for: ask == "show-latest-emails" ? "show my latest emails" : ask,
                context: DeskContext(isConnected: true, snapshot: snapshot)
            )
            XCTAssertNotNil(evidence, ask)
            XCTAssertTrue(evidence?.shouldGlanceInbox == true, ask)
            XCTAssertGreaterThan(evidence?.cards.count ?? 0, 0, "\(ask) must have cards")
            let surface = LiveVADPlayerKeep.oneMouthFullReply(
                cardCount: evidence?.cards.count ?? 0
            )
            XCTAssertFalse(surface.isCardlessBlob, ask)
            let plan = InboxGlanceSpeakPlan.liveVAD(ask: ask, snapshot: snapshot, now: now)
            XCTAssertFalse(plan.spokenText.isEmpty, "fd4a772 \(ask) empty reply + cards")
            XCTAssertTrue(InboxGlance.isShortSpokenSummary(plan.spokenText), ask)
            XCTAssertNotEqual(plan.spokenText, "Here they are.", ask)
            XCTAssertGreaterThan(plan.cardCount, 0, ask)
        }
    }
}
