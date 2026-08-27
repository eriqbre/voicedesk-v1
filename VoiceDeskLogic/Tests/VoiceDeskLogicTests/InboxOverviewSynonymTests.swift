import XCTest
@testable import VoiceDeskLogic

/// Live dogfood 2026-08-25 (SHA e153435):
/// 1. “Tell me my emails.” → live Grok, zero cards.
/// 2. “Tell me about my emails.” → live Grok, zero cards.
/// 3. Follow-ups stayed with Grok because the desk never took the inbox.
/// 4. “show me the email” → need-more “Who’s it from?” instead of last card.
///
/// Synonym families, not one golden phrase. Assert intent / outcome —
/// never Eve’s exact wording. Do not special-case “Okay Okay?” / “Yes.” /
/// “You are the app.”
final class InboxOverviewSynonymTests: XCTestCase {
    static let tellMeEmailsFamily = [
        "Tell me my emails.",
        "tell me my emails",
        "Tell me about my emails.",
        "tell me about my emails",
        "show me my emails",
        "show me the emails",
        "pull my emails",
        "list my emails",
        "list the emails",
        "my emails",
        "the emails",
        "my inbox",
        "uh tell me my emails",
        "um tell me about my emails",
        "okay, tell me my emails",
        "how about my emails"
    ]

    static let lastCardFamily = [
        "show me the email",
        "Show me the email.",
        "the email",
        "that email",
        "this email",
        "open the email",
        "read that email",
        "uh show me the email",
        "okay, show me the email"
    ]

    static let namedStillWins = [
        "Tell me about Murray's emails",
        "show me the email from Murray",
        "tell me my emails from Murray"
    ]

    private var mixedInbox: DeskContext {
        DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [
                VoiceRegressionDesk.greenacre,
                VoiceRegressionDesk.murray,
                VoiceRegressionDesk.steve
            ])
        )
    }

    func testTellMeEmailsFamilyIsInboxOverviewNotGrok() {
        let context = mixedInbox
        for ask in Self.tellMeEmailsFamily {
            XCTAssertTrue(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertTrue(ConversationPresence.isInboxCollectionAsk(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsLastDeskEmail(ask), ask)
            XCTAssertFalse(GmailSearchQuery.hasSenderPattern(ask), ask)
            XCTAssertFalse(ConversationPresence.isClarifyPick(ask), ask)

            let replay = VoiceTurnReplay.play(
                utterance: ask,
                context: context,
                focusedEmail: VoiceRegressionDesk.murray
            )
            XCTAssertEqual(replay.intent, "inbox-overview", ask)
            XCTAssertNotEqual(replay.intent, "general", "\(ask) must not yield to live Grok")
            XCTAssertNotEqual(replay.intent, "need-more", ask)
            XCTAssertTrue(replay.ownsDeskTurn, ask)
            XCTAssertTrue(replay.stickyCleared, ask)
            XCTAssertNil(replay.evidence?.focusedEmail, ask)
            XCTAssertGreaterThanOrEqual(replay.cardLabels.count, 2, "\(ask) → \(replay.cardLabels)")
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Murray Mitchell") },
                "\(ask) → \(replay.cardLabels)"
            )
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Greenacre") } ||
                    replay.cardLabels.contains { $0.contains("Steve Brown") },
                "\(ask) must glance the inbox, not one sticky card: \(replay.cardLabels)"
            )
            XCTAssertFalse(
                replay.reply.localizedCaseInsensitiveContains("who's it from"),
                ask
            )
            XCTAssertFalse(
                replay.reply.localizedCaseInsensitiveContains("stay quiet"),
                ask
            )
            XCTAssertEqual(replay.evidence?.shouldGlanceInbox, true, ask)
            let onScreen = InboxGlance.onScreenText(compactCardCount: replay.cardLabels.count)
            XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(onScreen), "\(ask) on-screen: \(onScreen)")
            XCTAssertFalse(InboxGlance.repeatsGlanceLines(onScreen), ask)
            XCTAssertTrue(replay.reply.isEmpty, "\(ask) list/show: \(replay.reply)")
            XCTAssertNotEqual(replay.reply, InboxGlance.spokenListAck(), ask)
            XCTAssertFalse(InboxGlance.isMultiline(replay.reply), ask)
            XCTAssertFalse(replay.reply.contains("Murray"), ask)
            XCTAssertNil(DeskReplySpeech.textToSpeak(replay.reply, lastSpoken: nil), ask)
        }
    }

    func testLastCardFamilyUsesFocusedThreadNotNeedMore() {
        let context = mixedInbox
        for ask in Self.lastCardFamily {
            XCTAssertTrue(ConversationPresence.wantsLastDeskEmail(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertFalse(GmailSearchQuery.hasSenderPattern(ask), ask)

            let replay = VoiceTurnReplay.play(
                utterance: ask,
                context: context,
                focusedEmail: VoiceRegressionDesk.murray
            )
            XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), "\(ask) → \(replay.intent)")
            XCTAssertNotEqual(replay.intent, "need-more", ask)
            XCTAssertNotEqual(replay.intent, "inbox-overview", ask)
            XCTAssertNotEqual(replay.intent, "general", ask)
            XCTAssertNotEqual(replay.reply, ConversationPresence.emailNeedMoreReply, ask)
            XCTAssertEqual(replay.evidence?.focusedEmail?.fromName, "Murray Mitchell", ask)
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Murray Mitchell") },
                "\(ask) → \(replay.cardLabels)"
            )
            XCTAssertFalse(
                replay.cardLabels.contains { $0.contains("Greenacre") },
                "focused last-card must not attach the whole inbox: \(ask) → \(replay.cardLabels)"
            )
            XCTAssertEqual(replay.cardLabels.count, 1, "\(ask) → \(replay.cardLabels)")
            XCTAssertFalse(
                replay.reply.localizedCaseInsensitiveContains("who's it from"),
                ask
            )
            let onScreen = InboxGlance.onScreenTextHidingSpokenSummary()
            XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(onScreen), "\(ask) on-screen: \(onScreen)")
            XCTAssertFalse(onScreen.contains("Need you to notarize"), ask)
            XCTAssertEqual(DeskReplySpeech.textToSpeak(replay.reply, lastSpoken: nil), replay.reply, ask)
        }
    }

    func testLastCardWithNoFocusUsesNewestGlanceCard() {
        let context = mixedInbox
        XCTAssertEqual(
            ConversationPresence.lastDeskEmail(context: context, focusedEmail: nil)?.fromName,
            "Greenacre Properties, Inc."
        )
        for ask in ["show me the email", "the email", "that email"] {
            let replay = VoiceTurnReplay.play(utterance: ask, context: context)
            XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), "\(ask) → \(replay.intent)")
            XCTAssertNotEqual(replay.intent, "need-more", ask)
            XCTAssertEqual(replay.evidence?.focusedEmail?.fromName, "Greenacre Properties, Inc.", ask)
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Greenacre") },
                "\(ask) → \(replay.cardLabels)"
            )
            XCTAssertEqual(replay.cardLabels.count, 1, "\(ask) → \(replay.cardLabels)")
        }
    }

    func testEmptyDeskLastCardStillNeedMore() {
        let empty = DeskContext(isConnected: true, snapshot: .empty)
        XCTAssertNil(ConversationPresence.lastDeskEmail(context: empty, focusedEmail: nil))
        let replay = VoiceTurnReplay.play(utterance: "show me the email", context: empty)
        XCTAssertEqual(replay.intent, "need-more")
        XCTAssertEqual(replay.reply, ConversationPresence.emailNeedMoreReply)
        XCTAssertTrue(replay.cardLabels.isEmpty, "\(replay.cardLabels)")
    }

    func testNamedSenderStillWinsOverTellMeAndTheEmail() {
        let context = mixedInbox
        for ask in Self.namedStillWins {
            XCTAssertFalse(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsLastDeskEmail(ask), ask)
            XCTAssertTrue(GmailSearchQuery.hasSenderPattern(ask), ask)
            let replay = VoiceTurnReplay.play(
                utterance: ask,
                context: context,
                focusedEmail: VoiceRegressionDesk.steve
            )
            XCTAssertNotEqual(replay.intent, "inbox-overview", ask)
            XCTAssertNotEqual(replay.intent, "need-more", ask)
            XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), "\(ask) → \(replay.intent)")
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Murray Mitchell") },
                "\(ask) → \(replay.cardLabels)"
            )
            XCTAssertFalse(
                replay.cardLabels.contains { $0.contains("Steve Brown") },
                "named Murray must not keep Steve sticky: \(ask) → \(replay.cardLabels)"
            )
        }
    }

    func testJokeWeatherAndLastOneStayOutOfInboxOverview() {
        XCTAssertFalse(ConversationPresence.wantsInboxOverview("Tell me a joke"))
        XCTAssertFalse(ConversationPresence.wantsInboxOverview("tell me everything about the weather"))
        XCTAssertFalse(ConversationPresence.wantsLastDeskEmail("Tell me a joke"))
        XCTAssertFalse(ConversationPresence.wantsLastDeskEmail("The last one."))
        XCTAssertFalse(ConversationPresence.wantsInboxOverview("The last one."))
        XCTAssertTrue(ConversationPresence.isClarifyPick("The last one."))
        XCTAssertFalse(ConversationPresence.wantsInboxOverview("What's for dinner?"))
    }
}
