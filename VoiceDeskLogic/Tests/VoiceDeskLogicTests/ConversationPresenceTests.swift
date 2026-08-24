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
        XCTAssertEqual(ConversationPresence.connectHowToReply, "Tap Connect Google on the card below.")
        XCTAssertEqual(ConversationPresence.connectCoach, ConversationPresence.connectHowToReply)
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
            XCTAssertEqual(plan.text, "Tap Connect Google on the card below.", ask)
            assertDoesNotContradictConnectCard(plan.text, ask)
            XCTAssertTrue(plan.text.contains("Tap Connect Google"), ask)
            let cards = ConversationPresence.cards(for: plan.topic, googleConnected: false)
            XCTAssertEqual(cards.map(\.kind), [.connectGoogle], ask)
        }
        XCTAssertFalse(ConversationPresence.wantsConnectGoogle("What's in my inbox?"))
        XCTAssertFalse(ConversationPresence.wantsConnectGoogle("What's for dinner?"))
    }

    func testConnectGoogleWhenAlreadyConnectedDoesNotMentionSettings() {
        let context = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(accountEmail: "bridgetsaiassistant@gmail.com"),
            auth: GoogleAuthSnapshot.reduce(.signedOut, .connectSucceeded(email: "bridgetsaiassistant@gmail.com"))
        )
        let plan = ConversationPresence.plan(for: "Connect google", context: context)
        XCTAssertEqual(plan.topic, .google)
        XCTAssertEqual(
            plan.text,
            "You’re already connected as bridgetsaiassistant@gmail.com. Use Disconnect on the card if you need to switch."
        )
        assertDoesNotContradictConnectCard(plan.text)
        XCTAssertEqual(ConversationPresence.cards(for: .google, context: context).map(\.kind), [.connectGoogle])
    }

    func testEmailDetailAskMatchesSenderAndStaysInVoiceDesk() {
        let murray = EmailItem(
            providerID: "m-murray",
            fromName: "Murray Cole",
            fromEmail: "murray@example.com",
            sentAtLabel: "Today 9:00 AM",
            subject: "Lot walk",
            preview: "Snippet only",
            filterTag: "Inbox"
        )
        XCTAssertTrue(ConversationPresence.wantsEmailBody("details on Murray's email"))
        XCTAssertTrue(ConversationPresence.wantsEmailBody("pull up details on Murray's email"))
        XCTAssertTrue(ConversationPresence.wantsEmailBody("summarize Murray's email"))
        XCTAssertEqual(
            ConversationPresence.matchingEmail(for: "pull up details on Murray's email", in: [murray])?.providerID,
            "m-murray"
        )
        let withoutBody = ConversationPresence.emailBodyReply(murray)
        XCTAssertEqual(withoutBody, ConversationPresence.emailBodySyncFailedReply(murray))
        XCTAssertTrue(withoutBody.lowercased().contains("retry"))
        XCTAssertFalse(EmailSummary.containsUIChrome(withoutBody))
        XCTAssertTrue(withoutBody.contains("VoiceDesk"))
        assertDoesNotBounceToGmail(withoutBody)
        var loaded = murray
        loaded.body = "Walk the lot Saturday at 10.\n\n> On Tuesday Jordan wrote:\n>> old quote"
        let withBody = ConversationPresence.emailBodyReply(loaded)
        XCTAssertTrue(withBody.contains("Walk the lot Saturday"))
        XCTAssertFalse(EmailSummary.containsUIChrome(withBody))
        XCTAssertFalse(withBody.contains(">>"))
        assertDoesNotBounceToGmail(withBody)
        assertDoesNotBounceToGmail(ConversationPresence.emailBodyUnknownReply(hasInbox: true))
        assertDoesNotBounceToGmail(ConversationPresence.emailBodyUnknownReply(hasInbox: false))
    }

    func testDogfoodShowEmailUtterancesAttachCards() {
        let murray = EmailItem(
            providerID: "m-murray",
            fromName: "Murray Mitchell",
            fromEmail: "murray@example.com",
            sentAtLabel: "Today 9:00 AM",
            subject: "Lot walk",
            preview: "Walk the lot Saturday",
            body: "Walk the lot Saturday at 10.",
            filterTag: "Inbox"
        )
        let steve = EmailItem(
            providerID: "m-steve",
            fromName: "Steve Brown",
            fromEmail: "steve@example.com",
            sentAtLabel: "Today 8:00 AM",
            subject: "Inspection note",
            preview: "Punch list",
            body: "Punch list is attached.",
            filterTag: "Inbox"
        )
        let context = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [murray, steve])
        )

        XCTAssertTrue(ConversationPresence.wantsEmailBody("Hey, show me Murray's latest email."))
        XCTAssertTrue(ConversationPresence.wantsShowEmail("Hey, show me Murray's latest email."))
        XCTAssertTrue(ConversationPresence.wantsEmailBody("show me Steve Brown's note"))
        XCTAssertTrue(ConversationPresence.wantsEmailFollowUp("Can you show it to me?"))
        XCTAssertTrue(ConversationPresence.wantsEmailFollowUp("I’m not seeing any email cards."))
        XCTAssertTrue(ConversationPresence.wantsInbox("show me what other emails I have today"))
        XCTAssertEqual(
            ConversationPresence.matchingEmail(for: "Hey, show me Murray's latest email.", in: [murray, steve])?.fromName,
            "Murray Mitchell"
        )
        XCTAssertEqual(
            ConversationPresence.matchingEmail(for: "show me Steve Brown's note", in: [murray, steve])?.fromName,
            "Steve Brown"
        )

        let murrayAsk = ConversationPresence.deskEvidence(
            for: "Hey, show me Murray's latest email.",
            context: context
        )
        XCTAssertNotNil(murrayAsk)
        XCTAssertFalse(murrayAsk?.claimsCardWithoutAttaching == true)
        XCTAssertEqual(murrayAsk?.cards.count, 1)
        if case .email(let item) = murrayAsk?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected Murray email card")
        }
        XCTAssertFalse(EmailSummary.containsUIChrome(murrayAsk?.text ?? ""), murrayAsk?.text ?? "")
        XCTAssertFalse(ConversationPresence.replyMentionsCard(murrayAsk?.text ?? ""))

        let steveAsk = ConversationPresence.deskEvidence(
            for: "show me Steve Brown's note",
            context: context
        )
        XCTAssertFalse(steveAsk?.claimsCardWithoutAttaching == true)
        if case .email(let item) = steveAsk?.cards.first {
            XCTAssertEqual(item.fromName, "Steve Brown")
        } else {
            XCTFail("expected Steve email card")
        }

        let follow = ConversationPresence.deskEvidence(
            for: "Can you show it to me?",
            context: context,
            focusedEmail: murray
        )
        XCTAssertFalse(follow?.claimsCardWithoutAttaching == true)
        if case .email(let item) = follow?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected focused email card on follow-up")
        }

        let missing = ConversationPresence.deskEvidence(
            for: "I’m not seeing any email cards.",
            context: context
        )
        XCTAssertFalse(missing?.claimsCardWithoutAttaching == true)
        XCTAssertEqual(missing?.cards.count, 2)
        XCTAssertTrue(missing?.cards.allSatisfy { $0.kind == .email } == true)

        let inbox = ConversationPresence.deskEvidence(
            for: "show me what other emails I have today",
            context: context
        )
        XCTAssertEqual(inbox?.topic, .inbox)
        XCTAssertEqual(inbox?.cards.count, 2)
        XCTAssertFalse(inbox?.claimsCardWithoutAttaching == true)
        XCTAssertFalse((inbox?.text ?? "").lowercased().contains("pull-to-refresh"))
    }

    func testSummarizeFullThreadUsesFocusedEmailNotGrokInvention() {
        var email = SampleData.syncedEmail()
        email.fromName = "Murray Mitchell"
        email.body = "Walk the lot Saturday at 10."
        email.earlierMessages = [
            EmailThreadMessage(id: "e1", fromName: "Murray Mitchell", plainBody: "Can we walk the lot this week?")
        ]
        let context = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [email, SampleData.syncedEmail()])
        )
        XCTAssertTrue(ConversationPresence.wantsFullThread("Can you summarize the full thread?"))
        XCTAssertNil(ConversationPresence.matchingEmail(for: "Can you summarize the full thread?", in: context.snapshot.emails))
        let evidence = ConversationPresence.deskEvidence(
            for: "Can you summarize the full thread?",
            context: context,
            focusedEmail: email
        )
        XCTAssertNotNil(evidence)
        XCTAssertTrue(evidence?.expandEarlierMessages == true)
        XCTAssertTrue(evidence?.cards.contains { $0.kind == .email } == true)
        if case .email(let item) = evidence?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
            XCTAssertTrue(item.hasEarlierMessages)
        } else {
            XCTFail("expected focused email card")
        }
        let reply = evidence?.text ?? ""
        XCTAssertFalse(ConversationPresence.replyMentionsCard(reply) && (evidence?.cards.isEmpty ?? true))
        XCTAssertFalse(evidence?.claimsCardWithoutAttaching == true)
        assertNotGrokThreadInvention(reply)
        XCTAssertTrue(reply.lowercased().contains("thread") || reply.lowercased().contains("earlier"))
    }

    func testWhenWasMurraysLastEmailSentMatchesMurrayNotWasMurrayQuery() {
        let ask = "When was Murray's last email sent?"
        XCTAssertTrue(ConversationPresence.hasDeskMailIntent(ask))
        XCTAssertTrue(ConversationPresence.looksLikeMailAsk(ask))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(ask))
        XCTAssertEqual(GmailSearchQuery.query(from: ask), "from:murray")
        XCTAssertFalse((GmailSearchQuery.query(from: ask) ?? "").contains("was murray"))

        let context = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [VoiceRegressionDesk.murray, VoiceRegressionDesk.steve])
        )
        let evidence = ConversationPresence.deskEvidence(for: ask, context: context)
        XCTAssertNotEqual(evidence?.shouldSearchGmail, true)
        if case .email(let item) = evidence?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected Murray card for when-was last email")
        }
        XCTAssertFalse((evidence?.gmailQuery ?? "").lowercased().contains("was murray"))
        XCTAssertFalse((evidence?.gmailQuery ?? "").contains("from:(\"was murray\")"))

        let empty = ConversationPresence.deskEvidence(
            for: ask,
            context: DeskContext(isConnected: true, snapshot: .empty)
        )
        XCTAssertEqual(empty?.shouldSearchGmail, true)
        XCTAssertEqual(empty?.gmailQuery, "from:murray")
        XCTAssertFalse((empty?.gmailQuery ?? "").contains("was murray"))

        let contrast = "When did I last get an email from Murray?"
        XCTAssertTrue(GmailSearchQuery.query(from: contrast)?.contains("from:murray") == true)
        let contrastEvidence = ConversationPresence.deskEvidence(for: contrast, context: context)
        if case .email(let item) = contrastEvidence?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected Murray card for when-did-I-last-get")
        }
    }

    func testHowAboutMurraysLatestEmailMatchesMurrayNotHowMurrayQuery() {
        let ask = "Okay, perfect. How about Murray's latest email?"
        XCTAssertTrue(ConversationPresence.hasDeskMailIntent(ask))
        XCTAssertTrue(ConversationPresence.looksLikeMailAsk(ask))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(ask))
        XCTAssertEqual(GmailSearchQuery.query(from: ask), "from:murray")
        XCTAssertFalse((GmailSearchQuery.query(from: ask) ?? "").lowercased().contains("how murray"))

        let context = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [VoiceRegressionDesk.murray, VoiceRegressionDesk.steve])
        )
        let evidence = ConversationPresence.deskEvidence(for: ask, context: context)
        XCTAssertNotEqual(evidence?.shouldSearchGmail, true)
        if case .email(let item) = evidence?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected Murray card for how-about latest email")
        }
        XCTAssertFalse((evidence?.gmailQuery ?? "").lowercased().contains("how murray"))
        XCTAssertFalse((evidence?.gmailQuery ?? "").contains("from:(\"how murray\")"))

        let empty = ConversationPresence.deskEvidence(
            for: ask,
            context: DeskContext(isConnected: true, snapshot: .empty)
        )
        XCTAssertEqual(empty?.shouldSearchGmail, true)
        XCTAssertEqual(empty?.gmailQuery, "from:murray")
        XCTAssertFalse((empty?.gmailQuery ?? "").lowercased().contains("how murray"))
        XCTAssertEqual(empty?.text, ConversationPresence.gmailSearchingBeat)
        XCTAssertTrue(ConversationPresence.isGmailSearchingBeat(empty?.text ?? ""))
        XCTAssertFalse(ConversationPresence.isGmailSearchingBeat(ConversationPresence.gmailSearchEmptyReply))
    }

    func testCacheMissSpecificEmailRequestsGmailSearch() {
        let context = DeskContext(isConnected: true, snapshot: .empty)
        let evidence = ConversationPresence.deskEvidence(
            for: "Hey, show me Murray's latest email.",
            context: context
        )
        XCTAssertEqual(evidence?.shouldSearchGmail, true)
        XCTAssertNotNil(evidence?.gmailQuery)
        XCTAssertTrue(evidence?.gmailQuery?.contains("murray") == true)
        XCTAssertTrue(evidence?.cards.isEmpty == true)
        XCTAssertFalse(evidence?.claimsCardWithoutAttaching == true)
        assertNotFakeSearchCapability(evidence?.text ?? "")
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn("Hey, show me Murray's latest email."))
    }

    func testMarieLastEmailSearchesFromMarieWithoutBareLast() {
        let ask = "Hey, can you give me a full summary of Marie’s last email?"
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(ask))
        XCTAssertTrue(ConversationPresence.looksLikeMailAsk(ask))
        let evidence = ConversationPresence.deskEvidence(
            for: ask,
            context: DeskContext(isConnected: true, snapshot: .empty)
        )
        XCTAssertEqual(evidence?.shouldSearchGmail, true)
        XCTAssertEqual(evidence?.gmailQuery, "from:marie")
        XCTAssertEqual(evidence?.searchAsk, ask)
        XCTAssertTrue(evidence?.gmailPlan?.variants.contains(where: { $0.contains("from:marie") }) == true)
        for variant in evidence?.gmailPlan?.variants ?? [] {
            XCTAssertFalse(GmailSearchQuery.bareLetterTokens(in: variant).contains("last"), variant)
        }
        XCTAssertTrue(evidence?.cards.isEmpty == true)
        XCTAssertEqual(evidence?.text, ConversationPresence.gmailSearchingBeat)
        XCTAssertEqual(evidence?.expandEarlierMessages, true)
        assertNotFakeSearchCapability(evidence?.text ?? "")
    }

    func testMostRecentEmailByShowingTimeSearches() {
        let ask = "Show me the most recent email by showing time."
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(ask))
        XCTAssertNotNil(GmailSearchQuery.plan(from: ask))
        let evidence = ConversationPresence.deskEvidence(
            for: ask,
            context: DeskContext(isConnected: true, snapshot: .empty)
        )
        XCTAssertEqual(evidence?.shouldSearchGmail, true)
        XCTAssertNotEqual(evidence?.text, ConversationPresence.emailNeedMoreReply)
        let query = evidence?.gmailQuery ?? ""
        XCTAssertTrue(query.contains("\"showing time\"") || query.contains("showingtime"), query)
    }

    func testBareShowingTimeAfterNeedMoreSearches() {
        let evidence = ConversationPresence.deskEvidence(
            for: "Showing time",
            context: DeskContext(isConnected: true, snapshot: .empty),
            pendingSearchClarify: true
        )
        XCTAssertEqual(evidence?.shouldSearchGmail, true)
        XCTAssertTrue(evidence?.gmailQuery?.contains("showing") == true)
        XCTAssertNotEqual(evidence?.text, ConversationPresence.emailNeedMoreReply)
    }

    func testFullSummaryOfMurraysEmailExpandsThread() {
        let murray = EmailItem(
            providerID: "m-murray",
            fromName: "Murray Mitchell",
            fromEmail: "murray@example.com",
            sentAtLabel: "Today 9:00 AM",
            subject: "Closing / notarization",
            preview: "Need you to notarize",
            body: "Need you to notarize the closing package today. The buyer is coming at 3. Please confirm the walk-through window.",
            earlierMessages: [
                EmailThreadMessage(id: "e1", fromName: "Murray Mitchell", plainBody: "Can we walk the lot this week?")
            ],
            filterTag: "Inbox"
        )
        let ask = "full summary of Murray’s latest email"
        XCTAssertTrue(ConversationPresence.wantsFullThread(ask))
        let evidence = ConversationPresence.deskEvidence(
            for: ask,
            context: DeskContext(isConnected: true, snapshot: DeskSnapshot(emails: [murray])),
            focusedEmail: murray
        )
        XCTAssertEqual(evidence?.expandEarlierMessages, true)
        XCTAssertEqual(evidence?.shouldFetchBody, true)
        XCTAssertNotEqual(evidence?.shouldSearchGmail, true)
        if case .email(let item) = evidence?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected Murray thread card")
        }
        let reply = evidence?.text ?? ""
        XCTAssertTrue(reply.contains("Need you to notarize"))
        XCTAssertTrue(reply.contains("buyer is coming") || reply.lowercased().contains("earlier"))
        XCTAssertFalse(EmailSummary.containsUIChrome(reply), reply)
    }

    func testShowingTimeAskUsesQuotedBrandAndDoesNotAttachWaterfront() {
        let ask = "You search my inbox for emails from showing time?"
        let waterfront = EmailItem(
            providerID: "msg-waterfront",
            fromName: "Bridget Breland",
            fromEmail: "bridget@waterfrontsearch.com",
            sentAtLabel: "Today 8:02 AM",
            subject: "Waterfront Search",
            preview: "New waterfront matches this week.",
            filterTag: "Inbox"
        )
        XCTAssertNil(ConversationPresence.matchingEmail(for: ask, in: [waterfront]))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(ask))
        let evidence = ConversationPresence.deskEvidence(
            for: ask,
            context: DeskContext(isConnected: true, snapshot: DeskSnapshot(emails: [waterfront]))
        )
        XCTAssertEqual(evidence?.shouldSearchGmail, true)
        XCTAssertTrue(evidence?.cards.isEmpty == true)
        let query = evidence?.gmailQuery ?? ""
        XCTAssertTrue(query.contains("\"showing time\"") || query.contains("showingtime"), query)
        XCTAssertNotEqual(query, "from:showing")
        XCTAssertFalse(query.contains("from:showing "))
        assertNotFakeSearchCapability(evidence?.text ?? "")
    }

    func testFindClosingNoteWithoutEmailWordStillSearches() {
        let context = DeskContext(isConnected: true, snapshot: .empty)
        XCTAssertTrue(ConversationPresence.looksLikeMailAsk("find Murray's closing note"))
        let evidence = ConversationPresence.deskEvidence(
            for: "find Murray's closing note",
            context: context
        )
        XCTAssertEqual(evidence?.shouldSearchGmail, true)
        XCTAssertTrue(evidence?.gmailQuery?.contains("murray") == true)
        assertNotFakeSearchCapability(evidence?.text ?? "")
    }

    func testConnectedMailAskWithoutTokensStaysLocal() {
        let context = DeskContext(isConnected: true, snapshot: .empty)
        let evidence = ConversationPresence.deskEvidence(
            for: "Can you summarize the full thread?",
            context: context
        )
        XCTAssertNotNil(evidence)
        XCTAssertNotEqual(evidence?.shouldSearchGmail, true)
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn("Can you summarize the full thread?"))
        assertNotFakeSearchCapability(evidence?.text ?? "")
        XCTAssertFalse((evidence?.text ?? "").lowercased().contains("i can search"))
    }

    func testCalendarReservationDoesNotSearchGmail() {
        let context = DeskContext(isConnected: true, snapshot: .empty)
        let evidence = ConversationPresence.deskEvidence(
            for: "details for Massimo's reservation",
            context: context
        )
        XCTAssertNotNil(evidence)
        XCTAssertNotEqual(evidence?.shouldSearchGmail, true)
        XCTAssertEqual(evidence?.text, ConversationPresence.calendarMissReply)
        assertNotFakeSearchCapability(evidence?.text ?? "")
    }

    func testLatestOnMyCalendarIsOverviewNotMiss() {
        let event = CalendarItem(
            title: "Massimo showing",
            whenLabel: "Today 3:00 PM",
            location: "1842 Beach Drive",
            relatedPeople: ["Massimo Ricci"]
        )
        let context = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(events: [event])
        )
        for ask in [
            "What's the latest on my calendar?",
            "whats the latest on my calendar",
            "What's on my calendar this week",
            "latest on my calendar"
        ] {
            XCTAssertTrue(ConversationPresence.wantsCalendarAsk(ask), ask)
            XCTAssertTrue(ConversationPresence.wantsCalendarOverview(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsCalendarDetails(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertFalse(GmailSearchQuery.hasSenderPattern(ask), ask)
            let evidence = ConversationPresence.deskEvidence(for: ask, context: context)
            XCTAssertEqual(evidence?.topic, .calendar, ask)
            XCTAssertNotEqual(evidence?.text, ConversationPresence.calendarMissReply, ask)
            XCTAssertTrue((evidence?.text ?? "").contains("Massimo showing"), ask)
            XCTAssertEqual(evidence?.cards.count, 1, ask)
            if case .calendar(let item) = evidence?.cards.first {
                XCTAssertEqual(item.title, "Massimo showing")
            } else {
                XCTFail("expected calendar card for \(ask)")
            }
        }
    }

    func testLatestOnMyCalendarEmptySnapshotIsHonestOverview() {
        let context = DeskContext(isConnected: true, snapshot: .empty)
        let ask = "What's the latest on my calendar?"
        let evidence = ConversationPresence.deskEvidence(for: ask, context: context)
        XCTAssertEqual(evidence?.topic, .calendar)
        XCTAssertNotEqual(evidence?.text, ConversationPresence.calendarMissReply)
        XCTAssertTrue((evidence?.text ?? "").lowercased().contains("not inventing"))
        XCTAssertTrue(evidence?.cards.isEmpty == true)
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

    func testCalendarDetailsMatchReservationNotEmail() {
        let event = CalendarItem(
            title: "Dinner reservation",
            whenLabel: "Tonight 7:00 PM",
            location: "Oak & Stone",
            relatedPeople: ["Massimo Ricci"],
            notes: "Window table, party of 4."
        )
        XCTAssertTrue(ConversationPresence.wantsCalendarDetails("details for Massimo's reservation"))
        XCTAssertEqual(
            ConversationPresence.matchingCalendar(for: "details for Massimo's reservation", in: [event])?.title,
            "Dinner reservation"
        )
        XCTAssertNil(ConversationPresence.matchingEmail(for: "details for Massimo's reservation", in: []))
        let reply = ConversationPresence.calendarDetailsReply(event)
        XCTAssertTrue(reply.contains("Dinner reservation"))
        XCTAssertTrue(reply.contains("Oak & Stone"))
        XCTAssertTrue(reply.contains("Massimo Ricci"))
        XCTAssertTrue(reply.contains("calendar card"))
        XCTAssertFalse(reply.lowercased().contains("which message"))
        let evidence = ConversationPresence.deskEvidence(
            for: "details for Massimo's reservation",
            context: DeskContext(isConnected: true, snapshot: DeskSnapshot(events: [event]))
        )
        XCTAssertEqual(evidence?.cards.count, 1)
        if case .calendar(let item) = evidence?.cards.first {
            XCTAssertEqual(item.notes, "Window table, party of 4.")
            XCTAssertEqual(item.location, "Oak & Stone")
            XCTAssertEqual(item.relatedPeople, ["Massimo Ricci"])
        } else {
            XCTFail("expected calendar card with details")
        }
        XCTAssertFalse(evidence?.claimsCardWithoutAttaching == true)
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

    func testDisconnectedInboxPointsAtConnectCard() {
        let plan = ConversationPresence.plan(for: "What's in my inbox?")
        XCTAssertTrue(plan.text.contains("Tap Connect Google on the card below."))
        assertDoesNotContradictConnectCard(plan.text)
    }

    func testInboxOverviewDoesNotReuseStickyMurray() {
        let murray = EmailItem(
            providerID: "m-murray-overview",
            fromName: "Murray Mitchell",
            fromEmail: "murray@example.com",
            sentAtLabel: "Today 9:00 AM",
            subject: "Closing / notarization",
            preview: "Need you to notarize",
            body: "Need you to notarize the closing package today.",
            filterTag: "Inbox"
        )
        let steve = EmailItem(
            providerID: "m-steve-overview",
            fromName: "Steve Brown",
            fromEmail: "steve@example.com",
            sentAtLabel: "Today 8:00 AM",
            subject: "Inspection note",
            preview: "Punch list is attached.",
            body: "Punch list is attached.",
            filterTag: "Inbox"
        )
        let context = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [murray, steve])
        )

        for ask in [
            "summary of my latest emails",
            "summarize my recent email",
            "what's in my inbox",
            "latest emails",
            "recent emails",
            "see my latest emails",
            "Can you pull my latest emails?",
            "pull my latest emails"
        ] {
            XCTAssertTrue(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsFullThread(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsEmailFollowUp(ask), ask)
            let evidence = ConversationPresence.deskEvidence(
                for: ask,
                context: context,
                focusedEmail: murray
            )
            XCTAssertEqual(evidence?.topic, .inbox, ask)
            XCTAssertEqual(evidence?.resetsFocusedEmail, true, ask)
            XCTAssertNil(evidence?.focusedEmail, ask)
            XCTAssertNotEqual(evidence?.shouldFetchBody, true, ask)
            XCTAssertNotEqual(evidence?.expandEarlierMessages, true, ask)
            XCTAssertEqual(evidence?.cards.count, 2, ask)
            XCTAssertTrue(evidence?.cards.allSatisfy { $0.kind == .email } == true, ask)
            XCTAssertTrue(
                evidence?.cards.allSatisfy({
                    if case .email(let item) = $0 { return item.isCompactListRow }
                    return false
                }) == true,
                "inbox-overview must attach compact rows, not full readers: \(ask)"
            )
            let reply = evidence?.text ?? ""
            XCTAssertTrue(reply.contains("Murray Mitchell") || reply.contains("Steve Brown"), ask)
            XCTAssertTrue(reply.contains("Closing") || reply.contains("Inspection") || reply.lowercased().contains("recent inbox"), ask)
            XCTAssertFalse(reply.contains("Need you to notarize the closing package") && !reply.contains("Steve"), "must not be a single Murray thread summary: \(ask)")
        }

        let murrayAsk = "summarize the Murray email"
        XCTAssertFalse(ConversationPresence.wantsInboxOverview(murrayAsk))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(murrayAsk))
        let murrayEvidence = ConversationPresence.deskEvidence(
            for: murrayAsk,
            context: context,
            focusedEmail: steve
        )
        if case .email(let item) = murrayEvidence?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected Murray card for person-specific summary")
        }
        XCTAssertNotEqual(murrayEvidence?.resetsFocusedEmail, true)
        if case .email(let item) = murrayEvidence?.cards.first {
            XCTAssertFalse(item.isCompactListRow, "single Murray thread stays the full reader")
        }
    }

    func testSeeLatestEmailsThenJohnMadisonFollowUpIsSpeakableDeskTurn() {
        let madison = EmailItem(
            fromName: "John Madison",
            fromEmail: "john@example.com",
            sentAtLabel: "Today",
            subject: "Beach Drive",
            preview: "Can we talk numbers",
            body: "Can we talk numbers on Beach Drive.",
            filterTag: "Inbox"
        )
        let context = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [madison, VoiceRegressionDesk.murray])
        )
        let overviewAsk = "see my latest emails"
        XCTAssertTrue(ConversationPresence.wantsInboxOverview(overviewAsk))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(overviewAsk))
        let overview = ConversationPresence.deskEvidence(for: overviewAsk, context: context, focusedEmail: nil)
        XCTAssertEqual(overview?.resetsFocusedEmail, true)
        XCTAssertNotEqual(overview?.shouldFetchBody, true)
        let digest = overview?.text ?? ""
        XCTAssertEqual(DeskReplySpeech.textToSpeak(digest, lastSpoken: nil), digest)
        XCTAssertFalse(ConversationPresence.isGrokDeskMeta(digest))

        let follow = "summarize that email from John Madison"
        XCTAssertFalse(ConversationPresence.wantsInboxOverview(follow))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(follow))
        let person = ConversationPresence.deskEvidence(for: follow, context: context, focusedEmail: nil)
        XCTAssertEqual(person?.shouldFetchBody, true)
        if case .email(let item) = person?.cards.first {
            XCTAssertEqual(item.fromName, "John Madison")
            XCTAssertFalse(item.isCompactListRow)
        } else {
            XCTFail("expected John Madison full card")
        }
        let spoken = ConversationPresence.emailBodyReply(madison)
        XCTAssertEqual(DeskReplySpeech.textToSpeak(spoken, lastSpoken: digest), spoken)
        XCTAssertFalse(ConversationPresence.isGrokDeskMeta(spoken))
    }

    func testGrokDeskHandoffIsMetaNotASpokenDeskSummary() {
        XCTAssertTrue(ConversationPresence.isGrokDeskHandoff("I’ll let the app handle that."))
        XCTAssertTrue(ConversationPresence.isGrokDeskHandoff("I'll have the app look that up."))
        XCTAssertTrue(ConversationPresence.isGrokDeskMeta("I’ll let the app handle that."))
        XCTAssertTrue(ConversationPresence.isGrokDeskRefusal("I’ll let the app handle that."))
        XCTAssertFalse(ConversationPresence.isGrokDeskHandoff("Murray wrote: Need you to notarize today."))
        XCTAssertFalse(ConversationPresence.isGrokDeskMeta("Here’s the recent inbox. Murray Mitchell: Closing / notarization."))
        XCTAssertFalse(ConversationPresence.isGrokDeskMeta(ConversationPresence.gmailSearchingBeat))
    }

    func testJohnWickTriviaIsNotADeskTurn() {
        let ask = "What year did John Wick get released"
        XCTAssertFalse(ConversationPresence.ownsConnectedDeskTurn(ask))
        XCTAssertFalse(ConversationPresence.looksLikeMailAsk(ask))
        XCTAssertFalse(ConversationPresence.hasDeskMailIntent(ask))
        XCTAssertNil(
            ConversationPresence.deskEvidence(
                for: ask,
                context: DeskContext(isConnected: true, snapshot: .empty)
            )
        )
        for trivia in [
            "Who directed John Wick",
            "How tall is John Wick",
            "When was John Wick released"
        ] {
            XCTAssertFalse(ConversationPresence.ownsConnectedDeskTurn(trivia), trivia)
        }

        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn("show me John's latest email"))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn("did Murray email me?"))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn("find Murray's closing note"))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn("email from John Madison"))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn("Did Murray send me something?"))
        XCTAssertTrue(ConversationPresence.hasDeskMailIntent("Did Murray send me something?"))
        XCTAssertTrue(ConversationPresence.looksLikeMailAsk("Did Murray send me something?"))
    }

    func testOwnsConnectedDeskTurnForFullEmailPhrases() {
        for ask in [
            "pull the full email",
            "read the whole email",
            "full body of Murray's note",
            "give me a full summary of Murray’s latest email",
            "full email from Marie"
        ] {
            XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(ask), ask)
            XCTAssertTrue(ConversationPresence.looksLikeMailAsk(ask), ask)
        }
    }

    func testGrokDeskRefusalFilter() {
        XCTAssertTrue(ConversationPresence.isGrokDeskRefusal("I can’t pull the full email from here."))
        XCTAssertTrue(ConversationPresence.isGrokDeskRefusal("That’s not in my last sync."))
        XCTAssertTrue(ConversationPresence.isGrokDeskRefusal("All I have is the latest note."))
        XCTAssertTrue(ConversationPresence.isGrokDeskRefusal("I don’t have the full body."))
        XCTAssertFalse(ConversationPresence.isGrokDeskRefusal("Murray wrote: Need you to notarize today."))
        XCTAssertFalse(ConversationPresence.isGrokDeskRefusal(ConversationPresence.gmailSearchingBeat))
    }

    private func assertDoesNotContradictConnectCard(_ text: String, _ ask: String = "") {
        let lower = text.lowercased()
        XCTAssertFalse(lower.contains("can't connect") || lower.contains("cannot connect") || lower.contains("can’t connect"), ask)
        XCTAssertFalse(lower.contains("settings"), ask)
        XCTAssertFalse(text.contains("Integrations"), ask)
        XCTAssertFalse(lower.contains("do it yourself"), ask)
    }

    private func assertNotFakeSearchCapability(_ text: String) {
        let lower = text.lowercased()
        XCTAssertFalse(lower.contains("i can search"))
        XCTAssertFalse(lower.contains("i will search"))
        XCTAssertFalse(lower.contains("can search gmail"))
        XCTAssertFalse(lower.contains("looking in gmail"))
        XCTAssertFalse(lower.contains("not in last sync"))
        XCTAssertFalse(lower.contains("not in my last sync"))
    }

    private func assertNotGrokThreadInvention(_ text: String) {
        let lower = text.lowercased()
        XCTAssertFalse(lower.contains("can't pull") || lower.contains("cannot pull") || lower.contains("can’t pull"))
        XCTAssertFalse(lower.contains("not in my last sync"))
        XCTAssertFalse(lower.contains("not in the last sync"))
        XCTAssertFalse(lower.contains("all i have is the latest"))
    }

    private func assertDoesNotBounceToGmail(_ text: String) {
        let lower = text.lowercased()
        XCTAssertFalse(lower.contains("open it in gmail"))
        XCTAssertFalse(lower.contains("open in gmail"))
        XCTAssertFalse(lower.contains("need gmail for the rest"))
        XCTAssertFalse(lower.contains("you'll need gmail") || lower.contains("you’ll need gmail"))
        XCTAssertFalse(lower.contains("go to gmail"))
    }
}
