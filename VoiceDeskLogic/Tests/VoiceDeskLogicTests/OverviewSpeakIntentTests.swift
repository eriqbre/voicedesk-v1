import XCTest
@testable import VoiceDeskLogic

/// Eriq 2026-08-26: list/show is a short ack; summary asks speak one short
/// digest. Cards stay the list. No mode flag — the ask is the intent.
/// Synonym families, never one golden phrase.
final class OverviewSpeakIntentTests: XCTestCase {
    static let inboxListFamily = [
        "show me my emails",
        "Show me my emails.",
        "latest emails",
        "what's in my inbox",
        "whats in my inbox",
        "tell me my emails",
        "list my emails",
        "my inbox"
    ]

    static let inboxSummaryFamily = [
        "give me a summary of today's emails",
        "summary of my latest emails",
        "summarize my recent email",
        "catch me up on email",
        "catch me up on my emails",
        "what's important in my inbox",
        "whats important in my inbox"
    ]

    static let calendarListFamily = [
        "show my calendar",
        "show calendar",
        "what's on my calendar",
        "whats on my calendar"
    ]

    static let calendarSummaryFamily = [
        "summarize my week",
        "summarize my calendar",
        "give me a summary of my week",
        "catch me up on my calendar",
        "what's important on my calendar"
    ]

    private var inbox: DeskContext {
        DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [
                VoiceRegressionDesk.greenacre,
                VoiceRegressionDesk.murray,
                VoiceRegressionDesk.steve
            ])
        )
    }

    private var calendar: DeskContext { VoiceRegressionDesk.massimoCalendar }

    func testInboxListFamilySpeaksAckNotRecitation() {
        for ask in Self.inboxListFamily {
            XCTAssertTrue(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsInboxSummary(ask), ask)
            let replay = VoiceTurnReplay.play(utterance: ask, context: inbox)
            XCTAssertEqual(replay.intent, "inbox-overview", ask)
            XCTAssertGreaterThanOrEqual(replay.cardLabels.count, 2, "\(ask) → \(replay.cardLabels)")
            XCTAssertFalse(replay.reply.isEmpty, "fd4a772 \(ask) empty reply + cards")
            XCTAssertTrue(InboxGlance.isShortSpokenSummary(replay.reply), "\(ask) → \(replay.reply)")
            XCTAssertFalse(InboxGlance.isShortSpokenAck(replay.reply), ask)
            XCTAssertNotEqual(replay.reply, "Here they are.", ask)
            XCTAssertFalse(InboxGlance.isMultiline(replay.reply), ask)
            XCTAssertFalse(replay.reply.contains("—"), ask)
            XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(replay.onScreen), ask)
        }
    }

    func testInboxSummaryFamilySpeaksOneShortDigest() {
        for ask in Self.inboxSummaryFamily {
            XCTAssertTrue(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertTrue(ConversationPresence.wantsInboxSummary(ask), ask)
            let replay = VoiceTurnReplay.play(utterance: ask, context: inbox)
            XCTAssertEqual(replay.intent, "inbox-overview", ask)
            XCTAssertGreaterThanOrEqual(replay.cardLabels.count, 2, "\(ask) → \(replay.cardLabels)")
            XCTAssertTrue(InboxGlance.isShortSpokenSummary(replay.reply), "\(ask) spoken: \(replay.reply)")
            XCTAssertFalse(InboxGlance.isShortSpokenAck(replay.reply), ask)
            XCTAssertFalse(InboxGlance.isMultiline(replay.reply), ask)
            XCTAssertFalse(InboxGlance.repeatsGlanceLines(replay.reply), ask)
            XCTAssertTrue(
                replay.reply.contains("Murray") || replay.reply.contains("Greenacre"),
                "\(ask) → \(replay.reply)"
            )
            XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(replay.onScreen), ask)
            XCTAssertNotEqual(replay.onScreen, replay.reply, ask)
        }
    }

    func testCalendarListFamilySpeaksAckNotEventRecitation() {
        for ask in Self.calendarListFamily {
            XCTAssertTrue(ConversationPresence.wantsCalendarOverview(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsCalendarSummary(ask), ask)
            let replay = VoiceTurnReplay.play(utterance: ask, context: calendar)
            XCTAssertEqual(replay.intent, "calendar", ask)
            XCTAssertTrue(replay.attachesCalendarCard, ask)
            XCTAssertFalse(replay.reply.isEmpty, "fd4a772 \(ask) empty reply + cards")
            XCTAssertTrue(InboxGlance.isShortSpokenSummary(replay.reply), "\(ask) → \(replay.reply)")
            XCTAssertFalse(InboxGlance.isShortSpokenAck(replay.reply), ask)
            XCTAssertNotEqual(replay.reply, "Here they are.", ask)
            XCTAssertFalse(replay.reply.contains("Next up"), ask)
            XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(replay.onScreen), ask)
        }
    }

    func testCalendarSummaryFamilySpeaksOneShortDigest() {
        for ask in Self.calendarSummaryFamily {
            XCTAssertTrue(ConversationPresence.wantsCalendarAsk(ask), ask)
            XCTAssertTrue(ConversationPresence.wantsCalendarOverview(ask), ask)
            XCTAssertTrue(ConversationPresence.wantsCalendarSummary(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsInboxOverview(ask), ask)
            let replay = VoiceTurnReplay.play(utterance: ask, context: calendar)
            XCTAssertEqual(replay.intent, "calendar", ask)
            XCTAssertTrue(replay.attachesCalendarCard, ask)
            XCTAssertTrue(InboxGlance.isShortSpokenSummary(replay.reply), "\(ask) spoken: \(replay.reply)")
            XCTAssertFalse(InboxGlance.isShortSpokenAck(replay.reply), ask)
            XCTAssertTrue(replay.reply.contains("Massimo") || replay.reply.contains("Walk"), "\(ask) → \(replay.reply)")
            XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(replay.onScreen), ask)
            XCTAssertFalse(replay.onScreen.contains("Massimo"), ask)
        }
    }

    func testNamedSenderSummaryIsNotInboxOverview() {
        let ask = "summarize Murray's last email"
        XCTAssertFalse(ConversationPresence.wantsInboxOverview(ask), ask)
        XCTAssertFalse(ConversationPresence.wantsInboxSummary(ask), ask)
        let replay = VoiceTurnReplay.play(utterance: ask, context: inbox)
        XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), replay.intent)
    }

    func testBargeInStillCancelsDuringSummarySpeak() {
        let spoken = InboxGlance.spokenInboxSummary([
            VoiceRegressionDesk.murray,
            VoiceRegressionDesk.greenacre
        ])
        XCTAssertTrue(InboxGlance.isShortSpokenSummary(spoken), spoken)
        let walk = DeskSpeakListenResume.whileClientTTSSpeaking(
            ask: "catch me up on email",
            spokenLine: spoken,
            nextAsk: "show calendar",
            context: inbox
        )
        XCTAssertTrue(walk.nextAccepted)
        XCTAssertTrue(walk.cancelledSpeak)
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spoken)
        XCTAssertNil(EchoBargeIn.acceptedUserTranscript("murray", gate: gate, voiceState: .speaking))
    }
}
