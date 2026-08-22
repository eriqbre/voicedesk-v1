import XCTest
@testable import VoiceDeskLogic

final class ConversationPresenceTests: XCTestCase {
    func testGeneralChatDoesNotAttachCards() {
        let asks = [
            "What's for dinner?",
            "Tell me a joke",
            "How's the weather?",
            "How are you?",
            "Can you help me think through a gift for my sister?"
        ]
        for ask in asks {
            let plan = ConversationPresence.plan(for: ask)
            XCTAssertEqual(plan.topic, .general, ask)
            XCTAssertFalse(plan.attachesCards, ask)
            XCTAssertTrue(ConversationPresence.cards(for: plan.topic, googleConnected: false).isEmpty, ask)
            XCTAssertFalse(plan.text.lowercased().contains("i can demo"), ask)
        }
    }

    func testDeskAsksAttachEvidenceCards() {
        let inbox = ConversationPresence.plan(for: "What's in my inbox?")
        XCTAssertEqual(inbox.topic, .inbox)
        let disconnectedInbox = ConversationPresence.cards(for: .inbox, googleConnected: false)
        XCTAssertEqual(disconnectedInbox.map(\.kind), [.connectGoogle])
        XCTAssertFalse(inbox.text.lowercased().contains("jordan"))

        let listing = ConversationPresence.plan(for: "Show me Beach Drive")
        XCTAssertEqual(listing.topic, .listing)

        let draft = ConversationPresence.plan(for: "Draft a reply to Jordan")
        XCTAssertEqual(draft.topic, .draft)

        let statute = ConversationPresence.plan(for: "Florida law on brokerage disclosure")
        XCTAssertEqual(statute.topic, .statute)

        let google = ConversationPresence.plan(for: "Connect Google")
        XCTAssertEqual(google.topic, .google)
        XCTAssertEqual(google.text, ConversationPresence.connectHowToReply)
    }

    func testHowDoIConnectGoogleMapsToConnectCard() {
        let asks = [
            "how do I connect my Google account?",
            "How do I connect Google?",
            "how to connect Google",
            "link my Gmail",
            "where is Google in Settings?",
            "open Integrations to connect Gmail"
        ]
        for ask in asks {
            XCTAssertTrue(ConversationPresence.wantsConnectGoogle(ask), ask)
            let plan = ConversationPresence.plan(for: ask)
            XCTAssertEqual(plan.topic, .google, ask)
            XCTAssertTrue(plan.attachesCards, ask)
            XCTAssertEqual(plan.text, ConversationPresence.connectHowToReply, ask)
            XCTAssertFalse(plan.text.lowercased().contains("settings"), ask)
            XCTAssertFalse(plan.text.contains("Integrations"), ask)
            XCTAssertTrue(plan.text.contains("Tap Connect Google"), ask)
            let cards = ConversationPresence.cards(for: plan.topic, googleConnected: false)
            XCTAssertEqual(cards.map(\.kind), [.connectGoogle], ask)
        }
        XCTAssertFalse(ConversationPresence.wantsConnectGoogle("What's in my inbox?"))
        XCTAssertFalse(ConversationPresence.wantsConnectGoogle("What's for dinner?"))
    }

    func testConnectedInboxUsesCacheNotSampleDesk() {
        let snapshot = DeskSnapshot(emails: [SampleData.syncedEmail()])
        let context = DeskContext(isConnected: true, snapshot: snapshot)
        let plan = ConversationPresence.plan(for: "What's in my inbox?", context: context)
        XCTAssertEqual(plan.topic, .inbox)
        XCTAssertTrue(plan.text.contains("Ada Cole"))
        XCTAssertFalse(plan.text.lowercased().contains("jordan"))
        let cards = ConversationPresence.cards(for: .inbox, context: context)
        XCTAssertEqual(cards.count, 1)
        if case .email(let item) = cards[0] {
            XCTAssertEqual(item.subject, "Inspection questions")
        } else {
            XCTFail("expected email card")
        }
    }

    func testConnectedEmptyInboxDoesNotInventMail() {
        let context = DeskContext(isConnected: true, snapshot: .empty)
        let plan = ConversationPresence.plan(for: "What's in my inbox?", context: context)
        XCTAssertTrue(plan.text.lowercased().contains("not inventing"))
        XCTAssertTrue(ConversationPresence.cards(for: .inbox, context: context).isEmpty)
    }

    func testCalendarAndTasksWhenConnected() {
        let snapshot = DeskSnapshot(
            events: [SampleData.calendarEvent()],
            tasks: [SampleData.openTask()]
        )
        let context = DeskContext(isConnected: true, snapshot: snapshot)
        XCTAssertEqual(ConversationPresence.plan(for: "What's on my calendar?", context: context).topic, .calendar)
        XCTAssertEqual(ConversationPresence.cards(for: .calendar, context: context).map(\.kind), [.calendar])
        XCTAssertEqual(ConversationPresence.plan(for: "What tasks do I have?", context: context).topic, .task)
        XCTAssertEqual(ConversationPresence.cards(for: .task, context: context).map(\.kind), [.task])
    }

    func testWelcomeIsAPersonNotAMenu() {
        XCTAssertTrue(ConversationPresence.firstRunWelcome.lowercased().contains("tap talk"))
        XCTAssertTrue(ConversationPresence.firstRunWelcome.lowercased().contains("speak"))
        XCTAssertFalse(ConversationPresence.firstRunWelcome.lowercased().contains("pick"))
        XCTAssertEqual(ConversationPresence.starterChips.count, 3)
        XCTAssertTrue(ConversationPresence.starterChips.contains(ConversationPresence.justTalk))
        XCTAssertTrue(ConversationPresence.starterChips.contains(ConversationPresence.deskPreview))
        XCTAssertTrue(ConversationPresence.starterChips.contains(ConversationPresence.draftStarter))
        XCTAssertEqual(ConversationPresence.chipAccessibilityID(ConversationPresence.deskPreview), "suggestion.tour")
        XCTAssertTrue(ConversationPresence.firstRunWelcome.lowercased().contains("sample"))
        XCTAssertFalse(ConversationPresence.deskPreviewReply.lowercased().contains("live gmail is"))
        XCTAssertTrue(ConversationPresence.deskPreviewReply.lowercased().contains("samples"))
    }

    func testTourOfferIsConversational() {
        XCTAssertTrue(ConversationPresence.wantsTour("Sure, show me"))
        XCTAssertTrue(ConversationPresence.wantsTour("give me a tour"))
        XCTAssertTrue(ConversationPresence.wantsDeskPreview("Show me a sample email and listing"))
        XCTAssertFalse(ConversationPresence.wantsTour(ConversationPresence.deskPreview))
        XCTAssertTrue(ConversationPresence.isJustTalk("Just talk to me"))
        XCTAssertFalse(ConversationPresence.wantsTour("yes I want pizza"))
        XCTAssertFalse(ConversationPresence.wantsTour("start the car"))
    }

    func testDeskPreviewPlanIsSampleNotLive() {
        let plan = ConversationPresence.plan(for: ConversationPresence.deskPreview)
        XCTAssertEqual(plan.text, ConversationPresence.deskPreviewReply)
        XCTAssertFalse(plan.text.lowercased().contains("sent"))
        let cards = TourScript.deskPreviewCards()
        XCTAssertEqual(cards.map(\.kind), [.email, .listing])
    }

    func testDraftStarterMapsToDraftCard() {
        let plan = ConversationPresence.plan(for: ConversationPresence.draftStarter)
        XCTAssertEqual(plan.topic, .draft)
    }
}
