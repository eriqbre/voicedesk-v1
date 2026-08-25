import XCTest
@testable import VoiceDeskLogic

/// Live dogfood 2026-08-25 (SHA 8505ef2):
/// 1. “Show me all my emails from today.” → need-more / zero cards.
/// 2. “Just show me everything.” → sticky reused Murray 302 Georgia.
///
/// Synonym families, not one golden phrase. Assert intent / outcome —
/// never Eve’s exact wording.
final class TodayInboxSweepTests: XCTestCase {
    static let todayInboxFamily = [
        "Show me all my emails from today.",
        "show me all my emails from today",
        "all my emails from today",
        "mails from today",
        "today's emails",
        "todays emails",
        "emails from today",
        "uh show me all my emails from today",
        "how about today's emails",
        "show me what other emails I have today",
        "how many emails today",
        "how many emails from today",
        "um how many emails today"
    ]

    static let everythingFamily = [
        "Just show me everything.",
        "just show me everything",
        "show me everything",
        "everything",
        "all of them",
        "show me all of them",
        "all my emails",
        "uh just show me everything",
        "how about everything",
        "okay, show me everything"
    ]

    static let namedStillWins = [
        "Show me all my emails from Murray today",
        "show me everything from Murray",
        "all of Murray's emails"
    ]

    private var mixedDayContext: DeskContext {
        DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [
                VoiceRegressionDesk.murrayGeorgia,
                VoiceRegressionDesk.sandyGut,
                VoiceRegressionDesk.murrayOlder
            ])
        )
    }

    func testTodayInboxFamilyIsOverviewNotNeedMore() {
        let context = mixedDayContext
        let storeCount = context.snapshot.emails.count
        XCTAssertEqual(storeCount, 3, "fixture must keep yesterday + today in the store")

        for ask in Self.todayInboxFamily {
            XCTAssertTrue(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertTrue(ConversationPresence.wantsTodayInbox(ask), ask)
            XCTAssertFalse(ConversationPresence.isClarifyPick(ask), ask)
            XCTAssertFalse(GmailSearchQuery.hasSenderPattern(ask), ask)
            XCTAssertNil(GmailSearchQuery.query(from: ask), ask)

            let replay = VoiceTurnReplay.play(
                utterance: ask,
                context: context,
                focusedEmail: VoiceRegressionDesk.murrayGeorgia,
                pendingSearchClarify: true
            )
            XCTAssertEqual(replay.intent, "inbox-overview", ask)
            XCTAssertNotEqual(replay.intent, "need-more", ask)
            XCTAssertNotEqual(replay.intent, "desk-person", ask)
            XCTAssertTrue(replay.stickyCleared, ask)
            XCTAssertNil(replay.evidence?.focusedEmail, ask)
            XCTAssertNotEqual(replay.reply, ConversationPresence.emailNeedMoreReply, ask)
            XCTAssertFalse(replay.cardLabels.isEmpty, "\(ask) must attach today's cards")
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Murray Mitchell") },
                "\(ask) → \(replay.cardLabels)"
            )
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Sandy Woodcock") },
                "\(ask) → \(replay.cardLabels)"
            )
            XCTAssertFalse(
                replay.cardLabels.contains { $0.contains("Old walk-through") },
                "today-inbox must not attach yesterday: \(ask) → \(replay.cardLabels)"
            )
            XCTAssertFalse(
                replay.reply.localizedCaseInsensitiveContains("who's it from"),
                ask
            )
            XCTAssertFalse(
                replay.reply.contains("CLOSING INFORMATION REQUIRED"),
                "must not recite the sticky Murray body: \(ask)"
            )
            XCTAssertEqual(
                context.snapshot.emails.count,
                storeCount,
                "today-inbox is a view — do not drop yesterday from the store: \(ask)"
            )
        }
    }

    func testHowManyEmailsTodaySpeaksCountNotPerson() {
        let context = mixedDayContext
        for ask in [
            "how many emails today",
            "how many emails from today",
            "um how many emails today"
        ] {
            XCTAssertTrue(ConversationPresence.wantsInboxCount(ask), ask)
            XCTAssertTrue(ConversationPresence.wantsInboxOverview(ask), ask)
            let replay = VoiceTurnReplay.play(
                utterance: ask,
                context: context,
                focusedEmail: VoiceRegressionDesk.murrayGeorgia
            )
            XCTAssertEqual(replay.intent, "inbox-overview", ask)
            XCTAssertTrue(replay.stickyCleared, ask)
            XCTAssertEqual(replay.reply, ConversationPresence.todayCountCopy(2), ask)
            XCTAssertEqual(replay.cardLabels.count, 2, "\(ask) → \(replay.cardLabels)")
            XCTAssertFalse(replay.reply.contains("302"), ask)
            XCTAssertFalse(replay.reply.contains("CLOSING INFORMATION REQUIRED"), ask)
        }
    }

    func testEverythingFamilyClearsStickyMurrayNotReuse() {
        let context = mixedDayContext
        for ask in Self.everythingFamily {
            XCTAssertTrue(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertTrue(ConversationPresence.isInboxSweepAsk(ask), ask)
            XCTAssertFalse(ConversationPresence.isClarifyPick(ask), ask)
            XCTAssertFalse(GmailSearchQuery.hasSenderPattern(ask), ask)

            let replay = VoiceTurnReplay.play(
                utterance: ask,
                context: context,
                focusedEmail: VoiceRegressionDesk.murrayGeorgia,
                pendingSearchClarify: true,
                clarifyMatches: [VoiceRegressionDesk.murrayGeorgia]
            )
            XCTAssertEqual(replay.intent, "inbox-overview", ask)
            XCTAssertNotEqual(replay.intent, "desk-person", ask)
            XCTAssertNotEqual(replay.intent, "need-more", ask)
            XCTAssertTrue(replay.stickyCleared, ask)
            XCTAssertNil(replay.evidence?.focusedEmail, ask)
            XCTAssertTrue(
                replay.notes.contains("sticky cleared")
                    || replay.stickyCleared,
                "\(ask) → \(replay.notes)"
            )
            XCTAssertFalse(
                replay.notes.contains(where: { $0.contains("sticky reused") }),
                "\(ask) → \(replay.notes)"
            )
            XCTAssertGreaterThanOrEqual(replay.cardLabels.count, 2, "\(ask) → \(replay.cardLabels)")
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Sandy Woodcock") },
                "everything must list inbox, not only Murray: \(ask) → \(replay.cardLabels)"
            )
            XCTAssertFalse(
                replay.reply.contains("CLOSING INFORMATION REQUIRED"),
                "must not re-speak Murray 302 Georgia: \(ask)"
            )
            XCTAssertNotEqual(replay.reply, ConversationPresence.emailNeedMoreReply, ask)
        }
    }

    func testNamedSenderStillWinsOverTodayAndEverything() {
        let context = mixedDayContext
        for ask in Self.namedStillWins {
            XCTAssertFalse(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertTrue(GmailSearchQuery.hasSenderPattern(ask), ask)
            let replay = VoiceTurnReplay.play(
                utterance: ask,
                context: context,
                focusedEmail: VoiceRegressionDesk.sandyGut
            )
            XCTAssertNotEqual(replay.intent, "inbox-overview", ask)
            XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), "\(ask) → \(replay.intent)")
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Murray Mitchell") },
                "\(ask) → \(replay.cardLabels)"
            )
            XCTAssertFalse(
                replay.cardLabels.contains { $0.contains("Sandy Woodcock") },
                "named Murray must not attach Sandy: \(ask) → \(replay.cardLabels)"
            )
        }
    }

    func testLastOneAndWeatherStayOutOfInboxOverview() {
        XCTAssertFalse(ConversationPresence.wantsInboxOverview("The last one."))
        XCTAssertFalse(ConversationPresence.wantsInboxOverview("the last one"))
        XCTAssertTrue(ConversationPresence.isClarifyPick("The last one."))
        XCTAssertFalse(ConversationPresence.wantsInboxOverview("What's for dinner?"))
        XCTAssertFalse(ConversationPresence.wantsInboxOverview("tell me everything about the weather"))
        XCTAssertFalse(ConversationPresence.isInboxSweepAsk("tell me everything about the weather"))
    }

    func testFromTodayAndEverythingAreNotSenders() {
        for ask in [
            "Show me all my emails from today.",
            "Just show me everything.",
            "mails from today",
            "how many emails today"
        ] {
            XCTAssertFalse(GmailSearchQuery.hasSenderPattern(ask), ask)
            XCTAssertNil(GmailSearchQuery.query(from: ask), ask)
            XCTAssertFalse((GmailSearchQuery.query(from: ask) ?? "").contains("from:today"), ask)
            XCTAssertFalse((GmailSearchQuery.query(from: ask) ?? "").contains("from:everything"), ask)
        }
    }

    func testTodayFilterIsAViewNotAStoreReplace() {
        var yesterday = VoiceRegressionDesk.murrayOlder
        yesterday.providerID = "keep-yesterday"
        let snapshot = DeskSnapshot(emails: [
            VoiceRegressionDesk.greenacre,
            yesterday
        ])
        XCTAssertEqual(snapshot.emails.count, 2)
        XCTAssertEqual(EmailRecency.fromToday(snapshot.emails).count, 1)
        XCTAssertTrue(snapshot.emails.contains { $0.providerID == "keep-yesterday" })

        let evidence = ConversationPresence.deskEvidence(
            for: "Show me all my emails from today.",
            context: DeskContext(isConnected: true, snapshot: snapshot)
        )
        XCTAssertEqual(evidence?.cards.count, 1)
        if case .email(let item) = evidence?.cards.first {
            XCTAssertEqual(item.fromName, "Greenacre Properties, Inc.")
        } else {
            XCTFail("expected today's Greenacre card")
        }
        XCTAssertEqual(snapshot.emails.count, 2)
        XCTAssertTrue(snapshot.emails.contains { $0.providerID == "keep-yesterday" })
    }
}
