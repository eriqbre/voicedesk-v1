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

    func testWhenWasMurraysLastEmailSentIsFromMurrayNotWasMurray() {
        for ask in [
            "When was Murray's last email sent?",
            "When was Murray’s last email sent?",
            "when was Murray's last email"
        ] {
            let plan = GmailSearchQuery.plan(from: ask)
            XCTAssertEqual(plan?.primary, "from:murray", ask)
            XCTAssertTrue(plan?.senders.contains("murray") == true, ask)
            XCTAssertFalse(plan?.senders.contains("was") == true, ask)
            XCTAssertFalse(plan?.phrases.contains(where: { $0.contains("was") }) == true, ask)
            for variant in plan?.variants ?? [] {
                XCTAssertTrue(variant.contains("from:murray"), "\(ask) \(variant)")
                XCTAssertFalse(variant.lowercased().contains("was murray"), variant)
                XCTAssertFalse(variant.contains("from:(\"was murray\")"), variant)
                XCTAssertFalse(GmailSearchQuery.bareLetterTokens(in: variant).contains("was"), variant)
            }
        }
        let working = GmailSearchQuery.query(from: "When did I last get an email from Murray?")
        XCTAssertTrue(working?.contains("from:murray") == true, working ?? "nil")
        XCTAssertFalse((working ?? "").lowercased().contains("was murray"))
    }

    func testHowAboutMurraysLatestEmailIsFromMurrayNotHowMurray() {
        for ask in [
            "How about Murray's latest email?",
            "Okay, perfect. How about Murray's latest email?",
            "okay how about Murray's latest email",
            "what about Murray's latest email",
            "Okay, perfect. What about Murray"
        ] {
            let plan = GmailSearchQuery.plan(from: ask)
            XCTAssertNotNil(plan, ask)
            XCTAssertTrue(
                plan?.senders.contains("murray") == true
                    || (plan?.primary ?? "").contains("from:murray"),
                "\(ask) \(plan?.primary ?? "nil")"
            )
            XCTAssertTrue((plan?.primary ?? "").contains("murray"), "\(ask) \(plan?.primary ?? "nil")")
            XCTAssertFalse(plan?.senders.contains("how") == true, ask)
            XCTAssertFalse(plan?.senders.contains("okay") == true, ask)
            XCTAssertFalse(plan?.senders.contains("perfect") == true, ask)
            XCTAssertFalse(plan?.phrases.contains(where: { $0.contains("how") }) == true, ask)
            for variant in plan?.variants ?? [] {
                XCTAssertFalse(variant.lowercased().contains("how murray"), variant)
                XCTAssertFalse(variant.contains("from:(\"how murray\")"), variant)
                XCTAssertFalse(GmailSearchQuery.bareLetterTokens(in: variant).contains("how"), variant)
                XCTAssertFalse(GmailSearchQuery.bareLetterTokens(in: variant).contains("okay"), variant)
                XCTAssertFalse(GmailSearchQuery.bareLetterTokens(in: variant).contains("perfect"), variant)
            }
        }
        let primary = GmailSearchQuery.query(from: "Okay, perfect. How about Murray's latest email?")
        XCTAssertEqual(primary, "from:murray", primary ?? "nil")
    }

    func testLatestOnMyCalendarIsNotASenderPattern() {
        for ask in [
            "What's the latest on my calendar?",
            "whats the latest on my calendar",
            "latest on my calendar",
            "What's on my calendar this week"
        ] {
            XCTAssertFalse(GmailSearchQuery.hasSenderPattern(ask), ask)
            XCTAssertNil(GmailSearchQuery.query(from: ask), ask)
            XCTAssertFalse(GmailSearchQuery.letterTokens(in: ask).contains("calendar"), ask)
            XCTAssertFalse(GmailSearchQuery.letterTokens(in: ask).contains("latest"), ask)
        }
    }

    func testQuickSummaryOfMurraysEmailIsFromMurrayNotQuickMurray() {
        let ask = "Give me a quick summary of Murray's latest email."
        let plan = GmailSearchQuery.plan(from: ask)
        XCTAssertEqual(plan?.primary, "from:murray", plan?.primary ?? "nil")
        XCTAssertFalse(plan?.phrases.contains(where: { $0.contains("quick") }) == true)
        for variant in plan?.variants ?? [] {
            XCTAssertFalse(variant.lowercased().contains("quick murray"), variant)
            XCTAssertFalse(variant.contains("from:(\"quick murray\")"), variant)
        }
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

    func testJohnWickTriviaDoesNotInventFromJohn() {
        let ask = "What year did John Wick get released"
        XCTAssertFalse(GmailSearchQuery.hasSenderPattern(ask))
        let plan = GmailSearchQuery.plan(from: ask)
        XCTAssertNil(plan)
        XCTAssertFalse(plan?.variants.contains(where: { $0.contains("from:john") }) == true)
        XCTAssertFalse(plan?.senders.contains("john") == true)

        XCTAssertTrue(GmailSearchQuery.hasSenderPattern("show me John's latest email"))
        XCTAssertTrue(GmailSearchQuery.query(from: "did Murray email me?")?.contains("from:murray") == true)
        XCTAssertTrue(GmailSearchQuery.hasSenderPattern("find Murray's closing note"))
        XCTAssertTrue(GmailSearchQuery.hasSenderPattern("email from John Madison"))
        XCTAssertTrue(GmailSearchQuery.query(from: "email from John Madison")?.contains("john") == true)
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

    func testMostRecentEmailByShowingTimeBuildsPlan() {
        let ask = "Show me the most recent email by showing time."
        let plan = GmailSearchQuery.plan(from: ask)
        XCTAssertNotNil(plan)
        XCTAssertEqual(GmailSearchQuery.fromSpokenPhrase(in: ask), "showing time")
        XCTAssertTrue(plan?.phrases.contains("showing time") == true)
        let primary = plan?.primary ?? ""
        XCTAssertTrue(primary.contains("\"showing time\"") || primary.contains("showingtime"), primary)
        XCTAssertFalse(GmailSearchQuery.bareLetterTokens(in: primary).contains("most"))
        XCTAssertFalse(GmailSearchQuery.bareLetterTokens(in: primary).contains("recent"))
    }

    func testShowingTimeCompactAndByPhrase() {
        XCTAssertEqual(GmailSearchQuery.fromSpokenPhrase(in: "email by ShowingTime"), "showingtime")
        XCTAssertEqual(GmailSearchQuery.spokenBrandPhrase(in: "ShowingTime"), "showing time")
        XCTAssertEqual(GmailSearchQuery.spokenBrandPhrase(in: "Showing time"), "showing time")
        let compact = GmailSearchQuery.plan(from: "from ShowingTime")
        XCTAssertTrue(compact?.phrases.contains("showing time") == true)
        XCTAssertTrue(compact?.variants.contains(where: { $0.contains("showingtime") }) == true)
    }

    func testBareBrandAfterClarifyTreatAsBrand() {
        let plan = GmailSearchQuery.plan(from: "Showing time", treatAsBrand: true)
        XCTAssertNotNil(plan)
        XCTAssertTrue(plan?.phrases.contains("showing time") == true)
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

    func testLaurenFuzzyMatchesLarenAndNotGreenacre() {
        let ask = "Give me a summary of Lauren's latest, latest email."
        XCTAssertEqual(GmailSearchQuery.query(from: ask), "from:lauren")
        XCTAssertGreaterThan(
            GmailSearchQuery.score(VoiceRegressionDesk.laren, ask: ask),
            GmailSearchQuery.senderAttachThreshold - 1
        )
        XCTAssertEqual(
            GmailSearchQuery.pick(
                [VoiceRegressionDesk.greenacre, VoiceRegressionDesk.laren],
                ask: ask
            ),
            .one(VoiceRegressionDesk.laren)
        )
        XCTAssertEqual(
            GmailSearchQuery.pick([VoiceRegressionDesk.greenacre], ask: ask),
            .none
        )
        XCTAssertTrue(
            GmailSearchQuery.namedSenderMismatches(VoiceRegressionDesk.greenacre, ask: ask)
        )
        XCTAssertFalse(
            GmailSearchQuery.namedSenderMismatches(VoiceRegressionDesk.laren, ask: ask)
        )
        XCTAssertEqual(GmailSearchQuery.editDistance("lauren", "laren"), 1)
    }

    func testLatestEmailFromLaurenDoesNotSilentlyPickJointAlexAndLaren() {
        let ask = "What's the latest email from Lauren?"
        let plan = GmailSearchQuery.plan(from: ask)
        XCTAssertEqual(plan?.primary, "from:lauren", plan?.primary ?? "nil")
        XCTAssertFalse(plan?.subjectTokens.contains("lauren") == true, "\(plan?.subjectTokens ?? [])")
        for variant in plan?.variants ?? [] {
            XCTAssertFalse(variant.contains("from:lauren lauren"), variant)
        }
        XCTAssertEqual(GmailSearchQuery.query(from: ask), "from:lauren")
        switch GmailSearchQuery.pick(
            [VoiceRegressionDesk.alexAndLaren, VoiceRegressionDesk.larenJansen],
            ask: ask
        ) {
        case .several(let list):
            let names = Set(list.map(\.fromName))
            XCTAssertTrue(names.contains("Alex & Laren"), "\(names)")
            XCTAssertTrue(names.contains("Laren Jansen"), "\(names)")
            XCTAssertFalse(list.contains { $0.fromName == "Alex & Laren" } && list.count == 1)
        default:
            XCTFail("expected clarify across distinct Lauren/Laren senders")
        }
        XCTAssertNil(
            ConversationPresence.matchingEmail(
                for: ask,
                in: [VoiceRegressionDesk.alexAndLaren, VoiceRegressionDesk.larenJansen]
            ),
            "must not silently take newest-of-fuzzy"
        )
    }

    func testFleemanTopicConstrainsLaurenToLarenJansen() {
        let ask = "No. Not that one. I'm looking for the one that Lauren wrote regarding Fleeman Road."
        let plan = GmailSearchQuery.plan(from: ask)
        XCTAssertTrue(plan?.senders.contains("lauren") == true, "\(plan?.senders ?? [])")
        XCTAssertTrue(plan?.subjectTokens.contains("fleeman") == true, "\(plan?.subjectTokens ?? [])")
        XCTAssertTrue(plan?.subjectTokens.contains("road") == true, "\(plan?.subjectTokens ?? [])")
        XCTAssertEqual(plan?.primary, "from:lauren fleeman road", plan?.primary ?? "nil")
        XCTAssertEqual(
            GmailSearchQuery.pick(
                [VoiceRegressionDesk.alexAndLaren, VoiceRegressionDesk.larenJansen],
                ask: ask
            ),
            .one(VoiceRegressionDesk.larenJansen)
        )
    }

    func testSummaryFromLaurenAboutFleemanDropsFamilyFunDay() {
        let ask = "Hey, give me a summary of the email from Lauren about Fleeman Road."
        let plan = GmailSearchQuery.plan(from: ask)
        XCTAssertTrue(plan?.senders.contains("lauren") == true, "\(plan?.senders ?? [])")
        XCTAssertTrue(plan?.subjectTokens.contains("fleeman") == true, "\(plan?.subjectTokens ?? [])")
        XCTAssertEqual(plan?.primary, "from:lauren fleeman road", plan?.primary ?? "nil")
        XCTAssertEqual(
            GmailSearchQuery.pick(
                [VoiceRegressionDesk.alexAndLaren, VoiceRegressionDesk.larenJansen],
                ask: ask
            ),
            .one(VoiceRegressionDesk.larenJansen)
        )
        XCTAssertFalse(
            GmailSearchQuery.topicHit(VoiceRegressionDesk.alexAndLaren, plan: plan!),
            "Family Fun Day must not match Fleeman"
        )
    }

    func testSameSenderEricHitsCollapseToNewestOneNotSeveral() {
        func eric(_ n: Int, subject: String, label: String) -> EmailItem {
            EmailItem(
                providerID: "fixture-eric-\(n)",
                fromName: "Eric Gross",
                fromEmail: "eric.gross@example.com",
                sentAtLabel: label,
                subject: subject,
                preview: "Eric thread \(n).",
                body: "Eric thread \(n).",
                filterTag: "Inbox"
            )
        }
        let oldest = eric(1, subject: "Lot walk", label: "Mar 1")
        let middle = eric(2, subject: "Offer", label: "Mar 2")
        let newest = eric(3, subject: "Follow-up", label: "Today 3:00 PM")
        let murray = VoiceRegressionDesk.murray
        let ask = "Can you find the last email by Eric?"

        switch GmailSearchQuery.pick([oldest, middle, newest, murray], ask: ask) {
        case .one(let email):
            XCTAssertEqual(email.fromName, "Eric Gross")
            XCTAssertEqual(email.fromEmail, "eric.gross@example.com")
            XCTAssertNotEqual(email.fromName, "Murray Mitchell")
            XCTAssertNotEqual(email.fromName, "Laren Cole")
        case .several(let emails):
            XCTFail("same-sender Eric hits must collapse to one card, got \(emails.map(\.subject))")
        default:
            XCTFail("Eric ask must attach the newest Eric card")
        }
    }

    func testEricDoesNotFuzzyMapToMailboxOwnerEriq() {
        let ask = "When was Eric's last email?"
        XCTAssertEqual(GmailSearchQuery.query(from: ask), "from:eric")
        let owner = MailboxOwner(email: "eriq@example.com")
        XCTAssertEqual(GmailSearchQuery.editDistance("eric", "eriq"), 1)
        XCTAssertEqual(
            GmailSearchQuery.pick(
                [VoiceRegressionDesk.eriqSelf, VoiceRegressionDesk.ericGross],
                ask: ask,
                owner: owner
            ),
            .one(VoiceRegressionDesk.ericGross)
        )
        switch GmailSearchQuery.pick(
            [VoiceRegressionDesk.eriqSelf],
            ask: ask,
            owner: owner
        ) {
        case .selfOnly(let email):
            XCTAssertEqual(email.fromEmail, "eriq@example.com")
        default:
            XCTFail("only self fuzzy hit must clarify, not attach")
        }
        XCTAssertEqual(
            GmailSearchQuery.pick(
                [VoiceRegressionDesk.eriqSelf],
                ask: "When was Eriq's last email?",
                owner: owner
            ),
            .one(VoiceRegressionDesk.eriqSelf)
        )
        XCTAssertTrue(GmailSearchQuery.isSelfAsk("When was the email I sent?"))
        XCTAssertEqual(
            GmailSearchQuery.pick(
                [VoiceRegressionDesk.eriqSelf],
                ask: "When was Eric's last email I sent?",
                owner: owner
            ),
            .one(VoiceRegressionDesk.eriqSelf)
        )
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
