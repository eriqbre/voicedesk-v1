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
        XCTAssertTrue(withoutBody.contains("card"))
        XCTAssertTrue(withoutBody.contains("VoiceDesk"))
        assertDoesNotBounceToGmail(withoutBody)
        var loaded = murray
        loaded.body = "Walk the lot Saturday at 10.\n\n> On Tuesday Jordan wrote:\n>> old quote"
        let withBody = ConversationPresence.emailBodyReply(loaded)
        XCTAssertTrue(withBody.contains("Walk the lot Saturday"))
        XCTAssertTrue(withBody.contains("on the card"))
        XCTAssertFalse(withBody.contains(">>"))
        XCTAssertLessThan(withBody.count, 220)
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
        XCTAssertTrue(ConversationPresence.replyMentionsCard(murrayAsk?.text ?? ""))

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

    func testCacheMissSpecificEmailRequestsGmailSearch() {
        let context = DeskContext(isConnected: true, snapshot: .empty)
        let evidence = ConversationPresence.deskEvidence(
            for: "Hey, show me Murray's latest email.",
            context: context
        )
        XCTAssertEqual(evidence?.shouldSearchGmail, true)
        XCTAssertTrue(evidence?.gmailQuery?.contains("murray") == true)
        XCTAssertTrue(evidence?.cards.isEmpty == true)
        XCTAssertFalse(evidence?.claimsCardWithoutAttaching == true)
        XCTAssertFalse((evidence?.text ?? "").lowercased().contains("not in last sync"))
        XCTAssertFalse((evidence?.text ?? "").lowercased().contains("not in my last sync"))
    }

    func testCalendarReservationDoesNotSearchGmail() {
        let context = DeskContext(isConnected: true, snapshot: .empty)
        let evidence = ConversationPresence.deskEvidence(
            for: "details for Massimo's reservation",
            context: context
        )
        XCTAssertNotEqual(evidence?.shouldSearchGmail, true)
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

    private func assertDoesNotContradictConnectCard(_ text: String, _ ask: String = "") {
        let lower = text.lowercased()
        XCTAssertFalse(lower.contains("can't connect") || lower.contains("cannot connect") || lower.contains("can’t connect"), ask)
        XCTAssertFalse(lower.contains("settings"), ask)
        XCTAssertFalse(text.contains("Integrations"), ask)
        XCTAssertFalse(lower.contains("do it yourself"), ask)
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
