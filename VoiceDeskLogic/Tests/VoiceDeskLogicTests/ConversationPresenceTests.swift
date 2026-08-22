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
        XCTAssertFalse(ConversationPresence.cards(for: .inbox, googleConnected: false).isEmpty)

        let listing = ConversationPresence.plan(for: "Show me Beach Drive")
        XCTAssertEqual(listing.topic, .listing)

        let draft = ConversationPresence.plan(for: "Draft a reply to Jordan")
        XCTAssertEqual(draft.topic, .draft)

        let statute = ConversationPresence.plan(for: "Florida law on brokerage disclosure")
        XCTAssertEqual(statute.topic, .statute)

        let google = ConversationPresence.plan(for: "Connect Google")
        XCTAssertEqual(google.topic, .google)
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
