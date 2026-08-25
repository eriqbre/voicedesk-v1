import XCTest
@testable import VoiceDeskLogic

/// Live tape 2026-08-25 (SHA be0b4c8): “calendar for the week” → calendar
/// overview, Massimo’s, 2 cards, plus a printed spoken summary. Delete the reprint.
///
/// Same cards-only rule as inbox glance: attach the event cards, Eve may speak
/// a short overview, do not print that line in the chat bubble.
///
/// Synonym families, not one golden phrase. Assert intent / cards / no printed
/// summary — never Eve’s exact spoken wording.
final class CalendarOverviewSynonymTests: XCTestCase {
    static let overviewFamily = [
        "calendar for the week",
        "What's on my calendar for the week?",
        "what's on my calendar for the week",
        "show my calendar",
        "Show my calendar.",
        "show the calendar",
        "show calendar",
        "what's on my calendar",
        "whats on my calendar",
        "What's on my calendar this week?",
        "latest on my calendar",
        "What's the latest on my calendar?",
        "um what's my calendar look like",
        "what's my calendar look like",
        "my calendar this week",
        "uh show my calendar",
        "okay, calendar for the week"
    ]

    private var desk: DeskContext { VoiceRegressionDesk.massimoCalendar }

    func testOverviewFamilyIsCalendarCardsOnlyNotPrintedSummary() {
        let context = desk
        for ask in Self.overviewFamily {
            XCTAssertTrue(ConversationPresence.wantsCalendarAsk(ask), ask)
            XCTAssertTrue(ConversationPresence.wantsCalendarOverview(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsCalendarDetails(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertFalse(GmailSearchQuery.hasSenderPattern(ask), ask)

            let replay = VoiceTurnReplay.play(utterance: ask, context: context)
            XCTAssertEqual(replay.intent, "calendar", ask)
            XCTAssertNotEqual(replay.intent, "general", "\(ask) must not yield to live Grok")
            XCTAssertNotEqual(replay.intent, "inbox-overview", ask)
            XCTAssertTrue(replay.ownsDeskTurn, ask)
            XCTAssertTrue(replay.attachesCalendarCard, "\(ask) → \(replay.cardLabels)")
            XCTAssertGreaterThanOrEqual(replay.cardLabels.count, 2, "\(ask) → \(replay.cardLabels)")
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Massimo showing") },
                "\(ask) → \(replay.cardLabels)"
            )
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Walk the lot") },
                "\(ask) → \(replay.cardLabels)"
            )
            XCTAssertEqual(replay.evidence?.hidesSpokenSummaryOnScreen, true, ask)
            XCTAssertTrue(
                InboxGlance.isShortOnScreenLeadIn(replay.onScreen),
                "\(ask) on-screen must not reprint Eve: \(replay.onScreen)"
            )
            XCTAssertFalse(InboxGlance.repeatsGlanceLines(replay.onScreen), ask)
            XCTAssertFalse(replay.onScreen.contains("Massimo"), "\(ask) printed: \(replay.onScreen)")
            XCTAssertFalse(replay.onScreen.contains("Next up"), "\(ask) printed: \(replay.onScreen)")
            XCTAssertNotEqual(replay.onScreen, replay.reply, ask)
            XCTAssertEqual(DeskReplySpeech.textToSpeak(replay.reply, lastSpoken: nil), replay.reply, ask)
            XCTAssertNil(DeskReplySpeech.textToSpeak(replay.onScreen, lastSpoken: nil), ask)
        }
    }

    func testEmptyCalendarStillPrintsHonestCopy() {
        let empty = DeskContext(isConnected: true, snapshot: .empty)
        for ask in ["show my calendar", "calendar for the week", "what's on my calendar"] {
            let replay = VoiceTurnReplay.play(utterance: ask, context: empty)
            XCTAssertEqual(replay.intent, "calendar", ask)
            XCTAssertFalse(replay.attachesCalendarCard, ask)
            XCTAssertEqual(replay.evidence?.hidesSpokenSummaryOnScreen, false, ask)
            XCTAssertFalse(InboxGlance.isShortOnScreenLeadIn(replay.onScreen), ask)
            XCTAssertEqual(replay.onScreen, replay.reply, ask)
            XCTAssertNotEqual(replay.reply, ConversationPresence.calendarMissReply, ask)
        }
    }

    func testCalendarDetailsStillPrintsAndIsNotOverview() {
        let ask = "details for Massimo's reservation"
        XCTAssertTrue(ConversationPresence.wantsCalendarDetails(ask))
        XCTAssertFalse(ConversationPresence.wantsCalendarOverview(ask))
        let replay = VoiceTurnReplay.play(utterance: ask, context: desk)
        XCTAssertEqual(replay.intent, "calendar")
        XCTAssertTrue(replay.attachesCalendarCard)
        XCTAssertEqual(replay.cardLabels.count, 1, "\(replay.cardLabels)")
        XCTAssertEqual(replay.evidence?.hidesSpokenSummaryOnScreen, false)
        XCTAssertEqual(replay.onScreen, replay.reply)
        XCTAssertFalse(InboxGlance.isShortOnScreenLeadIn(replay.onScreen))
        XCTAssertTrue(ConversationPresence.replyMentionsCard(replay.reply))
    }

    func testJokeAndEmailStayOutOfCalendarOverview() {
        XCTAssertFalse(ConversationPresence.wantsCalendarOverview("Tell me a joke"))
        XCTAssertFalse(ConversationPresence.wantsCalendarOverview("show me my emails"))
        XCTAssertFalse(ConversationPresence.wantsCalendarOverview("What's for dinner?"))
        XCTAssertTrue(ConversationPresence.wantsInboxOverview("show me my emails"))
    }
}
