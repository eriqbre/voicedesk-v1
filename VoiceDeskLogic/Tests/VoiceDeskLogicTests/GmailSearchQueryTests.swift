import XCTest
@testable import VoiceDeskLogic

final class GmailSearchQueryTests: XCTestCase {
    private let marieAsk = "Hey, can you give me a full summary of Marie’s last email?"
    private let showingAsk = "You search my inbox for emails from showing time?"

    func testBaselineInboxLimitIs25() {
        XCTAssertEqual(GoogleSyncPolicy.recentInboxLimit, 25)
    }

    func testMurrayAskUsesFromClause() {
        let query = GmailSearchQuery.query(from: "Hey, show me Murray's latest email.")
        XCTAssertEqual(query, "from:murray")
    }

    func testSteveBrownPossessiveKeepsMultiWordFrom() {
        let plan = GmailSearchQuery.plan(from: "show me Steve Brown's note")
        XCTAssertNotNil(plan)
        XCTAssertTrue(plan?.phrases.contains("steve brown") == true)
        XCTAssertTrue(plan?.variants.contains(where: { $0.contains("\"steve brown\"") }) == true)
        XCTAssertTrue(plan?.variants.contains(where: { $0.contains("from:steve") }) == true)
        XCTAssertFalse(plan?.variants.contains(where: { GmailSearchQuery.bareLetterTokens(in: $0).contains("note") && !$0.contains("from:") }) == true)
    }

    func testExplicitFromColonIsPreservedWithoutJunkAnd() {
        let query = GmailSearchQuery.query(from: "pull up from:ada inspection")
        XCTAssertTrue(query?.contains("from:ada") == true)
        XCTAssertFalse(GmailSearchQuery.bareLetterTokens(in: query ?? "").contains("inspection"))
        XCTAssertFalse(GmailSearchQuery.bareLetterTokens(in: query ?? "").contains("pull"))
    }

    func testFullThreadFollowUpHasNoSearchTokens() {
        XCTAssertNil(GmailSearchQuery.query(from: "Can you summarize the full thread?"))
    }

    func testFindMurraysClosingNoteWithoutSayingEmail() {
        let plan = GmailSearchQuery.plan(from: "find Murray's closing note")
        XCTAssertTrue(plan?.variants.contains(where: { $0.contains("from:murray") }) == true)
        XCTAssertTrue(plan?.subjectTokens.contains("closing") == true)
        XCTAssertTrue(GmailSearchQuery.hasSenderPattern("find Murray's closing note"))
    }

    func testEmailAboutSubjectTokens() {
        let query = GmailSearchQuery.query(from: "email about the inspection window")
        XCTAssertTrue(query?.contains("inspection") == true)
        XCTAssertTrue(query?.contains("window") == true)
    }

    func testDidMurraySendSomethingUsesFrom() {
        let query = GmailSearchQuery.query(from: "Did Murray send me something?")
        XCTAssertTrue(query?.contains("from:murray") == true)
    }

    func testMarieLastEmailIsSenderFocusedWithoutBareLast() {
        let plan = GmailSearchQuery.plan(from: marieAsk)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.primary, "from:marie")
        XCTAssertTrue(plan?.senders.contains("marie") == true)
        for variant in plan?.variants ?? [] {
            XCTAssertTrue(variant.contains("from:marie"))
            let bare = GmailSearchQuery.bareLetterTokens(in: variant)
            XCTAssertFalse(bare.contains("last"), variant)
            XCTAssertFalse(bare.contains("give"), variant)
            XCTAssertFalse(bare.contains("full"), variant)
            XCTAssertFalse(bare.contains("summary"), variant)
            XCTAssertFalse(bare.contains("inbox"), variant)
        }
    }

    func testShowingTimeCapturesMultiWordBrand() {
        let plan = GmailSearchQuery.plan(from: showingAsk)
        XCTAssertNotNil(plan)
        let primary = plan?.primary ?? ""
        XCTAssertTrue(primary.contains("\"showing time\"") || primary.contains("showingtime"), primary)
        XCTAssertNotEqual(primary, "from:showing")
        XCTAssertFalse(primary.contains("from:showing "), "should not AND leftover time after from:showing")
        XCTAssertTrue(plan?.phrases.contains("showing time") == true)
        XCTAssertTrue(GmailSearchQuery.hasSenderPattern(showingAsk))
        XCTAssertEqual(GmailSearchQuery.fromSpokenPhrase(in: showingAsk), "showing time")
    }

    func testStraightApostropheMarieLastEmail() {
        let plan = GmailSearchQuery.plan(from: "full summary of Marie's last email")
        XCTAssertEqual(plan?.primary, "from:marie")
        XCTAssertFalse((plan?.variants ?? []).contains(where: {
            GmailSearchQuery.bareLetterTokens(in: $0).contains("last")
        }))
    }

    func testRankingMarieBeatsWaterfront() {
        XCTAssertGreaterThan(
            GmailSearchQuery.score(Self.marieEmail, ask: marieAsk),
            GmailSearchQuery.score(Self.waterfrontEmail, ask: marieAsk)
        )
        XCTAssertEqual(
            GmailSearchQuery.pick([Self.waterfrontEmail, Self.marieEmail], ask: marieAsk),
            .one(Self.marieEmail)
        )
        XCTAssertEqual(
            GmailSearchQuery.pick([Self.waterfrontEmail], ask: marieAsk),
            .none
        )
    }

    func testRankingShowingTimeBeatsWaterfrontSearch() {
        XCTAssertGreaterThan(
            GmailSearchQuery.score(Self.showingTimeEmail, ask: showingAsk),
            GmailSearchQuery.score(Self.waterfrontEmail, ask: showingAsk)
        )
        XCTAssertEqual(
            GmailSearchQuery.pick([Self.waterfrontEmail, Self.showingTimeEmail], ask: showingAsk),
            .one(Self.showingTimeEmail)
        )
        XCTAssertEqual(
            GmailSearchQuery.pick([Self.waterfrontEmail], ask: showingAsk),
            .none
        )
    }

    func testWeakSearchSubjectDoesNotAttach() {
        XCTAssertEqual(
            GmailSearchQuery.score(Self.waterfrontEmail, ask: showingAsk),
            0
        )
        XCTAssertEqual(
            GmailSearchQuery.pick([Self.waterfrontEmail, Self.searchNewsletter], ask: showingAsk),
            .none
        )
    }

    func testQuotedBrandQueryMatchesShowingTimeNotWaterfront() {
        let query = GmailSearchQuery.query(from: showingAsk) ?? ""
        XCTAssertTrue(GmailSearchQuery.matches(Self.showingTimeEmail, gmailQuery: query))
        XCTAssertFalse(GmailSearchQuery.matches(Self.waterfrontEmail, gmailQuery: query))
    }

    func testFromMarieQueryMatchesMarieNotWaterfront() {
        let query = GmailSearchQuery.query(from: marieAsk) ?? ""
        XCTAssertTrue(GmailSearchQuery.matches(Self.marieEmail, gmailQuery: query))
        XCTAssertFalse(GmailSearchQuery.matches(Self.waterfrontEmail, gmailQuery: query))
    }
}

private extension GmailSearchQueryTests {
    static let marieEmail = EmailItem(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        providerID: "msg-marie",
        fromName: "Marie Chen",
        fromEmail: "marie@example.com",
        sentAtLabel: "Yesterday 4:12 PM",
        subject: "Walk-through notes",
        preview: "Here is the latest on the lot.",
        body: "Here is the latest on the lot.",
        filterTag: "Inbox"
    )

    static let waterfrontEmail = EmailItem(
        id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
        providerID: "msg-waterfront",
        fromName: "Bridget Breland",
        fromEmail: "bridget@waterfrontsearch.com",
        sentAtLabel: "Today 8:02 AM",
        subject: "Waterfront Search",
        preview: "New waterfront matches this week.",
        body: "New waterfront matches this week.",
        filterTag: "Inbox"
    )

    static let showingTimeEmail = EmailItem(
        id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        providerID: "msg-showingtime",
        fromName: "ShowingTime",
        fromEmail: "noreply@showingtime.com",
        sentAtLabel: "Today 9:40 AM",
        subject: "New showing confirmed",
        preview: "A buyer booked a showing.",
        body: "A buyer booked a showing.",
        filterTag: "Inbox"
    )

    static let searchNewsletter = EmailItem(
        id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
        providerID: "msg-search-news",
        fromName: "Inman",
        fromEmail: "news@inman.com",
        sentAtLabel: "Today 7:00 AM",
        subject: "Search tips for listing alerts",
        preview: "How to search smarter this week.",
        filterTag: "Inbox"
    )
}
