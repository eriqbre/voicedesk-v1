import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

@MainActor
final class AppModelTests: XCTestCase {
    func testColdLaunchMountsConversation() {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        XCTAssertEqual(model.phase, .welcome)
        XCTAssertEqual(model.turns.first?.role, .assistant)
        XCTAssertEqual(model.turns.first?.text, ConversationPresence.firstRunWelcome)
        XCTAssertEqual(model.turns.first?.suggestions, ConversationPresence.starterChips)
        XCTAssertTrue(model.showsTalkCoach)
        XCTAssertTrue(model.turns.first?.cards.isEmpty == true)
        XCTAssertTrue(model.sendClient.sentDrafts.isEmpty)
    }

    func testGeneralChatDoesNotForceCards() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn("What's for dinner?")
        XCTAssertTrue(model.turns.flatMap(\.cards).isEmpty)
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("i can demo"))
    }

    func testDeskPreviewInsertsSampleEmailAndListing() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn(ConversationPresence.deskPreview)
        let kinds = model.turns.flatMap(\.cards).map(\.kind)
        XCTAssertEqual(Array(kinds.prefix(2)), [.email, .listing])
        XCTAssertTrue(kinds.contains(.connectGoogle))
        XCTAssertTrue(model.turns.contains { $0.text == ConversationPresence.deskPreviewReply })
        XCTAssertTrue(model.turns.contains { $0.text == ConversationPresence.connectCoach })
        XCTAssertEqual(model.phase, .ready)
    }

    func testTourInsertsRequiredCards() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn("give me a tour")
        let kinds = Set(model.turns.flatMap(\.cards).map(\.kind))
        for kind in TourScript.requiredKinds {
            XCTAssertTrue(kinds.contains(kind), "missing \(kind.rawValue)")
        }
        XCTAssertEqual(model.phase, .ready)
    }

    func testConfirmQueuesSendAndDoesNotMarkDelivered() async {
        let send = RecordingSendClient()
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            sendClient: send
        )
        await model.applyUserTurn("Draft a reply to Jordan")
        let draft = model.turns.flatMap(\.cards).compactMap { card -> DraftConfirmItem? in
            if case .draftConfirm(let item) = card { return item }
            return nil
        }.first
        XCTAssertNotNil(draft)
        XCTAssertTrue(send.sentDrafts.isEmpty)

        model.confirmDraft(draft!.id)
        XCTAssertEqual(send.sentDrafts.count, 1)
        XCTAssertTrue(model.activity.contains { $0.outcome.contains("Not sent") })
        XCTAssertFalse(model.activity.contains { $0.outcome == "Delivered." })
    }

    func testCancelDoesNotCallSendClient() async {
        let send = RecordingSendClient()
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            sendClient: send
        )
        await model.applyUserTurn("Draft a reply to Jordan")
        let draft = model.turns.flatMap(\.cards).compactMap { card -> DraftConfirmItem? in
            if case .draftConfirm(let item) = card { return item }
            return nil
        }.first
        model.cancelDraft(draft!.id)
        XCTAssertTrue(send.sentDrafts.isEmpty)
    }

    func testUnconfiguredTalkDoesNotFakeAConversation() async {
        let model = AppModel(voice: UnconfiguredVoiceService())
        XCTAssertTrue(model.voice.needsCredentials)
        XCTAssertFalse(model.voice.usesLiveLoop)
        model.tapTalk()
        await Task.yield()
        XCTAssertTrue(model.showVoiceSetup)
        XCTAssertEqual(model.turns.count, 1)
        XCTAssertEqual(model.turns.first?.text, ConversationPresence.firstRunWelcome)
        XCTAssertEqual(model.voice.state, .idle)
    }

    func testLiveTranscriptsMirrorIntoTheThreadAndAttachDeskCards() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(voice: fake)
        model.tapTalk()
        await waitUntil { fake.started }
        XCTAssertTrue(model.voice.usesLiveLoop)

        fake.emitUser("What’s in my inbox?", itemID: "item_1")
        fake.emitUser("What’s in my inbox?", itemID: "item_1")
        fake.emitUser("What’s in my inbox?", itemID: "item_echo")
        fake.emitAssistant("Jordan wrote this morning about Saturday.", isFinal: false)
        fake.emitAssistant("", isFinal: true)

        XCTAssertEqual(model.turns.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(model.turns[1].text, "What’s in my inbox?")
        XCTAssertEqual(model.turns.last?.role, .assistant)
        XCTAssertTrue((model.turns.last?.text ?? "").contains("Connect Google"))
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .connectGoogle } == true)
        XCTAssertFalse(model.turns.last?.cards.contains { $0.kind == .email } == true)
        XCTAssertFalse(model.turns.contains { $0.role == .assistant && $0.text.contains("Jordan wrote") })
    }

    func testLiveHowToConnectGoogleAttachesCardOnUserTranscript() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(voice: fake)
        model.tapTalk()
        await waitUntil { fake.started }

        fake.emitUser("how do I connect my Google account?", itemID: "connect_1")

        XCTAssertEqual(model.turns.filter { $0.role == .user }.last?.text, "how do I connect my Google account?")
        let assistant = model.turns.last
        XCTAssertEqual(assistant?.role, .assistant)
        XCTAssertEqual(assistant?.text, "Tap Connect Google on the card below.")
        XCTAssertTrue(assistant?.cards.contains { $0.kind == .connectGoogle } == true)
        XCTAssertFalse((assistant?.text ?? "").lowercased().contains("settings"))
        XCTAssertFalse((assistant?.text ?? "").contains("Integrations"))
        XCTAssertFalse((assistant?.text ?? "").lowercased().contains("can't connect"))

        fake.emitAssistant("I can’t connect it — go to Settings or Integrations.", isFinal: true)
        XCTAssertEqual(model.turns.last?.text, "Tap Connect Google on the card below.")
        XCTAssertFalse(model.turns.contains { $0.text.contains("Settings") && $0.role == .assistant })
    }

    func testTypedConnectGoogleWhenConnectedDoesNotAskGrok() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true, email: "bridgetsaiassistant@gmail.com")
        )
        await model.applyUserTurn("Connect google")
        XCTAssertTrue(fake.sentTurns.isEmpty)
        XCTAssertEqual(
            model.turns.last?.text,
            "You’re already connected as bridgetsaiassistant@gmail.com. Use Disconnect on the card if you need to switch."
        )
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("settings"))
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .connectGoogle } == true)
    }

    func testEmailDetailsLoadsBodyFromSync() async {
        var email = SampleData.syncedEmail()
        email.fromName = "Murray Cole"
        email.providerID = "msg-murray"
        let sync = MockGoogleSync(result: DeskSnapshot(emails: [email]))
        sync.bodies["msg-murray"] = "Walk the lot Saturday at 10."
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [email])),
            sync: sync
        )
        await model.applyUserTurn("pull up details on Murray's email")
        XCTAssertTrue((model.turns.last?.text ?? "").contains("Walk the lot Saturday"))
        XCTAssertFalse(EmailSummary.containsUIChrome(model.turns.last?.text ?? ""))
        XCTAssertTrue(model.deskSnapshot.emails.first?.hasFullBody == true)
        XCTAssertEqual(model.deskSnapshot.emails.first?.body, "Walk the lot Saturday at 10.")
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("gmail"))
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .email } == true)
    }

    func testEmailDetailsFetchFailureRetriesInVoiceDesk() async {
        var email = SampleData.syncedEmail()
        email.fromName = "Murray Cole"
        email.providerID = "msg-murray"
        let sync = MockGoogleSync(result: DeskSnapshot(emails: [email]))
        sync.error = "network down"
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [email])),
            sync: sync
        )
        await model.applyUserTurn("pull up details on Murray's email")
        let reply = model.turns.last?.text ?? ""
        XCTAssertTrue(reply.lowercased().contains("retry"))
        XCTAssertFalse(EmailSummary.containsUIChrome(reply))
        XCTAssertTrue(reply.contains("VoiceDesk"))
        XCTAssertFalse(reply.lowercased().contains("gmail"))
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .email } == true)
        XCTAssertEqual(model.deskSnapshot.emails.first?.preview, email.preview)
    }

    func testEmailDetailsRetriesOnceThenKeepsSnippet() async {
        var email = SampleData.syncedEmail()
        email.fromName = "Murray Cole"
        email.providerID = "msg-murray"
        let sync = MockGoogleSync(result: DeskSnapshot(emails: [email]))
        sync.failuresRemaining = 1
        sync.bodies["msg-murray"] = "Walk the lot Saturday at 10."
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [email])),
            sync: sync
        )
        await model.applyUserTurn("summarize Murray's email")
        XCTAssertEqual(sync.fetchCalls, 2)
        XCTAssertEqual(model.deskSnapshot.emails.first?.body, "Walk the lot Saturday at 10.")
        XCTAssertTrue((model.turns.last?.text ?? "").contains("Walk the lot Saturday"))
        XCTAssertFalse(EmailSummary.containsUIChrome(model.turns.last?.text ?? ""))
    }

    func testCalendarReservationDetailsOpensCalendarCard() async {
        let event = CalendarItem(
            title: "Dinner reservation",
            whenLabel: "Tonight 7:00 PM",
            location: "Oak & Stone",
            relatedPeople: ["Massimo Ricci"],
            notes: "Window table, party of 4."
        )
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [SampleData.syncedEmail()], events: [event]))
        )
        let epoch = model.conversationScrollEpoch
        await model.applyUserTurn("details for Massimo's reservation")
        XCTAssertTrue((model.turns.last?.text ?? "").contains("Dinner reservation"))
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("which message"))
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .calendar } == true)
        XCTAssertFalse(model.turns.last?.cards.contains { $0.kind == .email } == true)
        if case .calendar(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.location, "Oak & Stone")
            XCTAssertEqual(item.relatedPeople, ["Massimo Ricci"])
            XCTAssertEqual(item.notes, "Window table, party of 4.")
        } else {
            XCTFail("expected calendar card with details")
        }
        XCTAssertGreaterThan(model.conversationScrollEpoch, epoch)
        XCTAssertEqual(model.conversationScrollTarget, model.turns.last?.id)
        XCTAssertEqual(model.conversationScrollReason, .cardsPeek)
    }

    func testLiveCalendarReplyAttachesCardsAndScrolls() {
        let event = CalendarItem(
            title: "Dinner reservation",
            whenLabel: "Tonight 7:00 PM",
            location: "Oak & Stone",
            relatedPeople: ["Massimo Ricci"],
            notes: "Window table, party of 4."
        )
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(events: [event]))
        )
        fake.emitUser("What's on my calendar?", itemID: "cal-1")
        let epoch = model.conversationScrollEpoch
        fake.emitAssistant("Next up: Dinner reservation, Tonight 7:00 PM.", isFinal: true)
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .calendar } == true)
        if case .calendar(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.notes, "Window table, party of 4.")
        } else {
            XCTFail("expected attached calendar card")
        }
        XCTAssertGreaterThan(model.conversationScrollEpoch, epoch)
        XCTAssertEqual(model.conversationScrollTarget, model.turns.last?.id)
        XCTAssertEqual(model.conversationScrollAnchor, .top)
    }

    func testShowMurraysLatestEmailAttachesCardWithoutGrok() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray"
        murray.body = "Walk the lot Saturday at 10."
        var steve = SampleData.syncedEmail()
        steve.fromName = "Steve Brown"
        steve.providerID = "msg-steve"
        steve.subject = "Inspection note"
        steve.body = "Punch list is attached."
        let snapshot = DeskSnapshot(emails: [murray, steve])
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot)
        )

        let epoch = model.conversationScrollEpoch
        await model.applyUserTurn("Hey, show me Murray's latest email.")
        XCTAssertTrue(fake.sentTurns.isEmpty)
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .email } == true)
        XCTAssertGreaterThan(model.conversationScrollEpoch, epoch)
        XCTAssertEqual(model.conversationScrollTarget, model.turns.last?.id)
        XCTAssertEqual(model.conversationScrollReason, .cardsPeek)
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected Murray email card")
        }
        XCTAssertFalse(EmailSummary.containsUIChrome(model.turns.last?.text ?? ""))
        XCTAssertFalse(ConversationPresence.replyMentionsCard(model.turns.last?.text ?? ""))
        XCTAssertFalse(ConversationPresence.DeskEvidence(
            topic: .inbox,
            text: model.turns.last?.text ?? "",
            cards: model.turns.last?.cards ?? []
        ).claimsCardWithoutAttaching)

        fake.emitAssistant("The full message is waiting on the Email card.", isFinal: true)
        XCTAssertFalse(model.turns.contains { $0.role == .assistant && $0.text.contains("waiting on the Email card") })

        await model.applyUserTurn("Can you show it to me?")
        XCTAssertTrue(fake.sentTurns.isEmpty)
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected focused Murray card on follow-up")
        }

        await model.applyUserTurn("show me Steve Brown's note")
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "Steve Brown")
        } else {
            XCTFail("expected Steve email card")
        }

        await model.applyUserTurn("show me what other emails I have today")
        XCTAssertEqual(model.turns.last?.cards.filter { $0.kind == .email }.count, 2)
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("pull-to-refresh"))
    }

    func testSummarizeFullThreadFetchesAndExpandsEarlier() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-thread"
        murray.body = "Walk the lot Saturday at 10."
        murray.earlierMessages = [
            EmailThreadMessage(id: "e1", fromName: "Murray Mitchell", plainBody: "Can we walk the lot this week?")
        ]
        let snapshot = DeskSnapshot(emails: [murray])
        let sync = MockGoogleSync(result: snapshot)
        sync.bodies["msg-murray-thread"] = murray.body
        sync.earlierMessages["msg-murray-thread"] = murray.earlierMessages
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: sync
        )
        await model.applyUserTurn("Hey, show me Murray's latest email.")
        await model.applyUserTurn("Can you summarize the full thread?")
        XCTAssertTrue(fake.sentTurns.isEmpty)
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .email } == true)
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
            XCTAssertTrue(item.hasEarlierMessages)
            XCTAssertTrue(model.expandsEarlierMessages(item))
        } else {
            XCTFail("expected Murray thread card")
        }
        let reply = model.turns.last?.text ?? ""
        XCTAssertTrue(reply.lowercased().contains("thread") || reply.lowercased().contains("earlier"))
        XCTAssertFalse(reply.lowercased().contains("can't pull") || reply.lowercased().contains("cannot pull"))
        XCTAssertFalse(reply.lowercased().contains("not in my last sync"))
        XCTAssertFalse(reply.lowercased().contains("all i have is the latest"))
    }

    func testCacheMissSearchesGmailAndAttaches() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-search"
        murray.body = "Walk the lot Saturday at 10."
        let sync = MockGoogleSync(result: .empty)
        sync.searchable = [murray]
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(),
            sync: sync
        )
        await model.applyUserTurn("Hey, show me Murray's latest email.")
        XCTAssertTrue(fake.sentTurns.isEmpty)
        XCTAssertFalse(sync.searchQueries.isEmpty)
        XCTAssertTrue(sync.searchQueries[0].contains("murray"))
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .email } == true)
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected searched Murray card")
        }
        XCTAssertEqual(model.deskSnapshot.emails.first?.fromName, "Murray Mitchell")
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("not in last sync"))
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("not in my last sync"))
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("i can search"))
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("can search gmail"))
        XCTAssertFalse(model.turns.contains { $0.text.lowercased().contains("i can search gmail") })
    }

    func testMarieLastEmailDoesNotAndLastToken() async {
        var marie = SampleData.syncedEmail()
        marie.fromName = "Marie Chen"
        marie.fromEmail = "marie@example.com"
        marie.providerID = "msg-marie"
        marie.subject = "Walk-through notes"
        marie.body = "Here is the latest on the lot."
        var waterfront = SampleData.syncedEmail()
        waterfront.fromName = "Bridget Breland"
        waterfront.fromEmail = "bridget@waterfrontsearch.com"
        waterfront.providerID = "msg-waterfront"
        waterfront.subject = "Waterfront Search"
        waterfront.body = "New waterfront matches this week."
        let sync = MockGoogleSync(result: .empty)
        sync.searchable = [marie, waterfront]
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(),
            sync: sync
        )
        await model.applyUserTurn("Hey, can you give me a full summary of Marie’s last email?")
        XCTAssertFalse(sync.searchQueries.isEmpty)
        for query in sync.searchQueries {
            XCTAssertTrue(query.contains("from:marie"), query)
            XCTAssertFalse(GmailSearchQuery.bareLetterTokens(in: query).contains("last"), query)
        }
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "Marie Chen")
        } else {
            XCTFail("expected Marie email card")
        }
    }

    func testShowingTimeSearchDoesNotAttachWaterfront() async {
        var waterfront = SampleData.syncedEmail()
        waterfront.fromName = "Bridget Breland"
        waterfront.fromEmail = "bridget@waterfrontsearch.com"
        waterfront.providerID = "msg-waterfront"
        waterfront.subject = "Waterfront Search"
        waterfront.body = "New waterfront matches this week."
        var showing = SampleData.syncedEmail()
        showing.fromName = "ShowingTime"
        showing.fromEmail = "noreply@showingtime.com"
        showing.providerID = "msg-showingtime"
        showing.subject = "New showing confirmed"
        showing.body = "A buyer booked a showing."
        let sync = MockGoogleSync(result: .empty)
        sync.searchable = [waterfront, showing]
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [waterfront])),
            sync: sync
        )
        await model.applyUserTurn("You search my inbox for emails from showing time?")
        XCTAssertFalse(sync.searchQueries.isEmpty)
        let query = sync.searchQueries[0]
        XCTAssertTrue(query.contains("\"showing time\"") || query.contains("showingtime"), query)
        XCTAssertNotEqual(query, "from:showing")
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "ShowingTime")
        } else {
            XCTFail("expected ShowingTime card, not waterfront")
        }
    }

    func testShowingTimeWrongHitsStayEmpty() async {
        var waterfront = SampleData.syncedEmail()
        waterfront.fromName = "Bridget Breland"
        waterfront.fromEmail = "bridget@waterfrontsearch.com"
        waterfront.providerID = "msg-waterfront"
        waterfront.subject = "Waterfront Search"
        waterfront.body = "New waterfront matches this week."
        let sync = MockGoogleSync(result: .empty)
        sync.searchable = [waterfront]
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(),
            sync: sync
        )
        await model.applyUserTurn("You search my inbox for emails from showing time?")
        XCTAssertEqual(model.turns.last?.text, ConversationPresence.gmailSearchEmptyReply)
        XCTAssertTrue(model.turns.last?.cards.isEmpty == true)
    }

    func testMostRecentEmailByShowingTimeSearches() async {
        var showing = SampleData.syncedEmail()
        showing.fromName = "ShowingTime"
        showing.fromEmail = "noreply@showingtime.com"
        showing.providerID = "msg-showingtime"
        showing.subject = "New showing confirmed"
        showing.body = "A buyer booked a showing."
        let sync = MockGoogleSync(result: .empty)
        sync.searchable = [showing]
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(),
            sync: sync
        )
        await model.applyUserTurn("Show me the most recent email by showing time.")
        XCTAssertFalse(sync.searchQueries.isEmpty)
        XCTAssertNotEqual(model.turns.last?.text, ConversationPresence.emailNeedMoreReply)
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "ShowingTime")
        } else {
            XCTFail("expected ShowingTime card")
        }
    }

    func testBareShowingTimeAfterNeedMoreSearches() async {
        var showing = SampleData.syncedEmail()
        showing.fromName = "ShowingTime"
        showing.fromEmail = "noreply@showingtime.com"
        showing.providerID = "msg-showingtime-bare"
        showing.subject = "New showing confirmed"
        showing.body = "A buyer booked a showing."
        let sync = MockGoogleSync(result: .empty)
        sync.searchable = [showing]
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(),
            sync: sync
        )
        await model.applyUserTurn("show me the email")
        XCTAssertEqual(model.turns.last?.text, ConversationPresence.emailNeedMoreReply)
        await model.applyUserTurn("Showing time")
        XCTAssertFalse(sync.searchQueries.isEmpty)
        XCTAssertNotEqual(model.turns.last?.text, ConversationPresence.emailNeedMoreReply)
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "ShowingTime")
        } else {
            XCTFail("expected ShowingTime card after clarify")
        }
    }

    func testFullSummaryOfFocusedMurrayExpandsThread() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-full"
        murray.subject = "Closing / notarization"
        murray.body = "Need you to notarize the closing package today. The buyer is coming at 3."
        murray.earlierMessages = [
            EmailThreadMessage(id: "e1", fromName: "Murray Mitchell", plainBody: "Can we walk the lot this week?")
        ]
        let snapshot = DeskSnapshot(emails: [murray])
        let sync = MockGoogleSync(result: snapshot)
        sync.bodies["msg-murray-full"] = murray.body
        sync.earlierMessages["msg-murray-full"] = murray.earlierMessages
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: sync
        )
        await model.applyUserTurn("full summary of Murray’s latest email")
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
            XCTAssertTrue(model.expandsEarlierMessages(item))
        } else {
            XCTFail("expected Murray thread card")
        }
        let reply = model.turns.last?.text ?? ""
        XCTAssertTrue(reply.contains("Need you to notarize") || reply.contains("buyer is coming"))
        XCTAssertTrue(reply.lowercased().contains("earlier") || reply.contains("walk the lot"))
    }

    func testGmailSearchEmptyIsHonest() async {
        let sync = MockGoogleSync(result: .empty)
        sync.searchable = []
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(),
            sync: sync
        )
        await model.applyUserTurn("show me Priya's email")
        XCTAssertEqual(model.turns.last?.text, ConversationPresence.gmailSearchEmptyReply)
        XCTAssertTrue(model.turns.last?.cards.isEmpty == true)
    }

    func testDeskReplyIsSpokenWhileLiveGrokStaysMuted() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-speak"
        murray.body = "Need you to notarize the closing package today."
        murray.earlierMessages = [
            EmailThreadMessage(id: "e1", fromName: "Murray Mitchell", plainBody: "Can we walk the lot this week?")
        ]
        let snapshot = DeskSnapshot(emails: [murray])
        let sync = MockGoogleSync(result: snapshot)
        sync.bodies["msg-murray-speak"] = murray.body
        sync.earlierMessages["msg-murray-speak"] = murray.earlierMessages
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: sync
        )
        await model.applyUserTurn("full summary of Murray’s latest email")
        let reply = model.turns.last?.text ?? ""
        XCTAssertTrue(reply.contains("Need you to notarize"))
        XCTAssertEqual(fake.spoken, [reply])
        XCTAssertFalse(fake.spoken.contains(ConversationPresence.gmailSearchingBeat))
        XCTAssertTrue(fake.assistantOutputSuppressed)
        XCTAssertTrue(fake.sentTurns.isEmpty)

        await model.applyUserTurn("full summary of Murray’s latest email")
        XCTAssertEqual(fake.spoken, [reply], "same desk reply must not be spoken twice")
        XCTAssertTrue(fake.assistantOutputSuppressed)
    }

    func testNeedMoreAndSearchResultsAreSpokenNotTheSearchingBeat() async {
        var showing = SampleData.syncedEmail()
        showing.fromName = "ShowingTime"
        showing.fromEmail = "noreply@showingtime.com"
        showing.providerID = "msg-showing-speak"
        showing.subject = "New showing confirmed"
        showing.body = "A buyer booked a showing."
        let sync = MockGoogleSync(result: .empty)
        sync.searchable = [showing]
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(),
            sync: sync
        )
        await model.applyUserTurn("show me the email")
        XCTAssertEqual(model.turns.last?.text, ConversationPresence.emailNeedMoreReply)
        XCTAssertEqual(fake.spoken, [ConversationPresence.emailNeedMoreReply])

        await model.applyUserTurn("Showing time")
        let reply = model.turns.last?.text ?? ""
        XCTAssertEqual(fake.spoken, [ConversationPresence.emailNeedMoreReply, reply])
        XCTAssertFalse(fake.spoken.contains(ConversationPresence.gmailSearchingBeat))
        XCTAssertTrue(fake.assistantOutputSuppressed)
    }

    func testLiveRefusalIsScrubbedWhenLocalEmailAttaches() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-scrub"
        murray.body = "Need you to notarize the closing package today."
        let snapshot = DeskSnapshot(emails: [murray])
        let sync = MockGoogleSync(result: snapshot)
        sync.bodies["msg-murray-scrub"] = murray.body
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: sync
        )
        fake.emitAssistant("I can’t pull the full email — that’s not in my last sync.", isFinal: true)
        XCTAssertTrue(model.turns.contains { ConversationPresence.isGrokDeskRefusal($0.text) })
        await model.applyUserTurn("full summary of Murray’s latest email")
        XCTAssertFalse(model.turns.contains { ConversationPresence.isGrokDeskRefusal($0.text) })
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .email } == true)
        XCTAssertTrue((model.turns.last?.text ?? "").contains("Need you to notarize"))
        XCTAssertTrue(fake.spoken.contains { $0.contains("Need you to notarize") })
    }

    func testHandoffMetaIsDroppedAndEveStillSpeaksDeskSummary() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-handoff"
        murray.body = "Need you to notarize the closing package today."
        let snapshot = DeskSnapshot(emails: [murray])
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot)
        )
        fake.emitAssistant("I’ll let the app handle that.", isFinal: true)
        XCTAssertTrue(model.turns.contains { ConversationPresence.isGrokDeskHandoff($0.text) })
        await model.applyUserTurn("summarize the Murray email")
        XCTAssertFalse(model.turns.contains { ConversationPresence.isGrokDeskHandoff($0.text) })
        XCTAssertFalse(model.turns.contains { $0.text.localizedCaseInsensitiveContains("let the app handle") })
        let reply = model.turns.last?.text ?? ""
        XCTAssertTrue(reply.contains("Murray Mitchell") || reply.contains("Need you to notarize"), reply)
        XCTAssertEqual(fake.spoken.last, reply)
        XCTAssertFalse(fake.spoken.contains { $0.localizedCaseInsensitiveContains("let the app handle") })
        fake.emitAssistant("I'll have the app look that up.", isFinal: true)
        XCTAssertFalse(model.turns.contains { $0.text.localizedCaseInsensitiveContains("look that up") })
        XCTAssertFalse(fake.grokSpoken.contains { $0.localizedCaseInsensitiveContains("look that up") })
    }

    func testMurrayQuickSummaryDropsRefusalFromSpokenPathAndStillSpeaksVerbatim() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-quick-summary"
        murray.body = "Need you to notarize the closing package today."
        let snapshot = DeskSnapshot(emails: [murray])
        let sync = MockGoogleSync(result: snapshot)
        sync.bodies["msg-murray-quick-summary"] = murray.body
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: sync
        )
        fake.emitAssistant("I can’t help with that.", isFinal: true)
        fake.emitAssistant("I’m not able to do that.", isFinal: true)
        await model.applyUserTurn("Give me a quick summary of Murray's latest email.")
        // Claim already owns the spoken path. Further Grok must not speak.
        fake.grokSpoken.removeAll()
        fake.emitAssistant("I’ll let the app handle that.", isFinal: true)
        fake.emitAssistant("I can't help with that.", isFinal: true)
        fake.emitAssistant("I'm not able to.", isFinal: true)

        func threadOrEveHas(_ needle: String) -> Bool {
            let haystacks = model.turns.map(\.text) + fake.spoken
            return haystacks.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
        XCTAssertFalse(threadOrEveHas("can't help") || threadOrEveHas("can’t help"))
        XCTAssertFalse(threadOrEveHas("not able to"))
        XCTAssertFalse(threadOrEveHas("let the app handle"))
        XCTAssertTrue(fake.grokSpoken.isEmpty, "claimed desk turn must drop Grok refusal/meta audio")
        XCTAssertTrue(fake.speakInvoked, "SPEAK_VERBATIM / voice.speak must still run")
        XCTAssertTrue(fake.assistantOutputSuppressed)
        let reply = model.turns.last?.text ?? ""
        XCTAssertTrue(reply.contains("Murray") || reply.contains("notarize"), reply)
        XCTAssertEqual(fake.spoken.last, reply)
        XCTAssertTrue(fake.spoken.contains { $0.contains("Murray") || $0.contains("notarize") })
        XCTAssertFalse(fake.spoken.contains { DeskSpokenPath.isForbiddenLiveSpeech($0) })
    }

    func testInboxOverviewAttachesCompactRowsAndSpeaksDigest() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-list"
        murray.subject = "Closing / notarization"
        murray.body = "Need you to notarize the closing package today."
        var steve = SampleData.syncedEmail()
        steve.fromName = "Steve Brown"
        steve.fromEmail = "steve@example.com"
        steve.providerID = "msg-steve-list"
        steve.subject = "Inspection note"
        steve.body = "Punch list is attached."
        let snapshot = DeskSnapshot(emails: [murray, steve])
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot)
        )
        await model.applyUserTurn("summary of my latest emails")
        let cards = model.turns.last?.cards ?? []
        XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(cards.allSatisfy { card in
            if case .email(let item) = card { return item.isCompactListRow }
            return false
        })
        let reply = model.turns.last?.text ?? ""
        XCTAssertTrue(reply.contains("Murray Mitchell"))
        XCTAssertTrue(reply.contains("Steve Brown"))
        XCTAssertEqual(fake.spoken.last, reply)
        XCTAssertFalse(reply.contains("<html"))
        XCTAssertFalse(EmailSummary.containsUIChrome(reply))

        let epoch = model.conversationScrollEpoch
        let target = model.conversationScrollTarget
        if case .email(let item) = cards.first {
            model.expandCompactEmail(item)
            XCTAssertEqual(model.conversationScrollEpoch, epoch, "expand must stay in place")
            XCTAssertEqual(model.conversationScrollTarget, target)
        } else {
            XCTFail("expected compact email to expand")
        }
    }

    func testSingleEmailSummaryNamesConcreteAsksNotCardChrome() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-asks"
        murray.subject = "Closing / notarization"
        murray.body = """
        Hey — two quick questions:
        1. Can you notarize the closing package Thursday?
        2. Is the buyer still set for 3pm on Beach Drive?
        """
        let snapshot = DeskSnapshot(emails: [murray])
        let sync = MockGoogleSync(result: snapshot)
        sync.bodies["msg-murray-asks"] = murray.body
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: sync
        )
        await model.applyUserTurn("summarize the Murray email")
        let reply = model.turns.last?.text ?? ""
        XCTAssertTrue(reply.localizedCaseInsensitiveContains("notarize"), reply)
        XCTAssertTrue(
            reply.localizedCaseInsensitiveContains("Thursday")
                || reply.localizedCaseInsensitiveContains("Beach Drive")
                || reply.localizedCaseInsensitiveContains("buyer"),
            reply
        )
        XCTAssertFalse(EmailSummary.containsUIChrome(reply), reply)
        XCTAssertEqual(fake.spoken.last, reply)
        XCTAssertEqual(model.conversationScrollTarget, model.turns.last?.id)
        XCTAssertEqual(model.conversationScrollAnchor, .top)
    }

    func testSeeLatestEmailsAndJohnMadisonFollowUpBothInvokeSpeak() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-overview"
        murray.subject = "Closing / notarization"
        murray.body = "Need you to notarize the closing package today."
        var madison = SampleData.syncedEmail()
        madison.fromName = "John Madison"
        madison.fromEmail = "john@example.com"
        madison.providerID = "msg-madison-overview"
        madison.subject = "Beach Drive"
        madison.body = "Can we talk numbers on Beach Drive."
        let snapshot = DeskSnapshot(emails: [murray, madison])
        let sync = MockGoogleSync(result: snapshot)
        sync.bodies["msg-madison-overview"] = madison.body
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: sync
        )

        await model.applyUserTurn("see my latest emails")
        XCTAssertEqual(fake.spoken.count, 1, "inbox-overview digest must Eve-speak")
        XCTAssertEqual(fake.spoken.last, model.turns.last?.text)
        XCTAssertTrue((model.turns.last?.text ?? "").contains("Murray Mitchell"))
        XCTAssertTrue(model.turns.last?.cards.allSatisfy { card in
            if case .email(let item) = card { return item.isCompactListRow }
            return false
        } == true)

        await model.applyUserTurn("summarize that email from John Madison")
        XCTAssertEqual(fake.spoken.count, 2, "desk-person follow-up must Eve-speak")
        XCTAssertEqual(fake.spoken.last, model.turns.last?.text)
        XCTAssertTrue((model.turns.last?.text ?? "").contains("John Madison")
                      || (model.turns.last?.text ?? "").contains("Beach Drive")
                      || (model.turns.last?.text ?? "").contains("talk numbers"))
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "John Madison")
            XCTAssertFalse(item.isCompactListRow)
        } else {
            XCTFail("expected John Madison full card")
        }
        XCTAssertTrue(fake.assistantOutputSuppressed)
        XCTAssertTrue(fake.sentTurns.isEmpty)
    }

    func testTypedTurnOnLiveServiceGoesToGrokNotLocalPlan() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(voice: fake)
        await model.applyUserTurn("What's for dinner?")
        XCTAssertEqual(fake.sentTurns, ["What's for dinner?"])
        XCTAssertEqual(model.turns.last?.role, .user)
        XCTAssertEqual(model.turns.filter { $0.role == .user }.count, 1)
        XCTAssertTrue(model.turns.flatMap(\.cards).isEmpty)

        fake.emitUser("What's for dinner?", itemID: "typed_echo")
        XCTAssertEqual(model.turns.filter { $0.role == .user }.count, 1)
    }

    func testReturningLaunchSkipsPlaybookChips() {
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            playbook: InMemoryPlaybookStore(completed: true, lastConnectSoftPromptAt: Date())
        )
        XCTAssertEqual(model.turns.first?.text, ConversationPresence.returningWelcome)
        XCTAssertTrue(model.turns.first?.suggestions.isEmpty == true)
        XCTAssertFalse(model.showsTalkCoach)
    }

    func testReturningLaunchSoftPromptsConnectOnce() {
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            playbook: InMemoryPlaybookStore(completed: true)
        )
        XCTAssertEqual(model.turns.first?.suggestions, [ConversationPresence.connectGoogleChip])
        XCTAssertNotNil(model.playbook.lastConnectSoftPromptAt)
    }

    func testJustTalkChipPointsAtTalkWithoutTour() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn(ConversationPresence.justTalk)
        XCTAssertTrue(model.hasCompletedPlaybook)
        XCTAssertTrue(model.turns.contains { $0.text == ConversationPresence.justTalkReply })
        XCTAssertTrue(model.turns.contains { $0.text == ConversationPresence.connectCoach })
    }

    func testLiveCancelStopsSessionWithoutFakeUtterance() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(voice: fake)
        model.tapTalk()
        await waitUntil { fake.started }
        model.tapTalk()
        XCTAssertTrue(fake.cancelled)
        XCTAssertEqual(model.turns.count, 1)
        XCTAssertEqual(model.voice.state, .idle)
    }

    func testClientSecretExtraction() {
        XCTAssertEqual(
            LiveGrokVoiceClient.extractClientSecret(from: ["value": "tok_1"]),
            "tok_1"
        )
        XCTAssertEqual(
            LiveGrokVoiceClient.extractClientSecret(from: ["client_secret": "tok_2"]),
            "tok_2"
        )
        XCTAssertEqual(
            LiveGrokVoiceClient.extractClientSecret(from: ["client_secret": ["value": "tok_3"]]),
            "tok_3"
        )
        XCTAssertNil(LiveGrokVoiceClient.extractClientSecret(from: [:]))
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<40 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out waiting for voice service")
    }
}

@MainActor
final class FakeLiveVoiceService: VoiceServicing {
    private var session = VoiceSession()
    let backendLabel = "Fake live"
    let isInstant = true
    let needsCredentials = false
    let usesLiveLoop = true
    var eventHandler: ((VoiceServiceEvent) -> Void)?
    var started = false
    var cancelled = false
    var sentTurns: [String] = []
    var spoken: [String] = []
    /// Live Grok assistant text that would have been spoken (not Eve `speak`).
    var grokSpoken: [String] = []
    var assistantOutputSuppressed = false
    var speakInvoked = false

    var state: VoiceState { session.state }

    func startListening() async -> String {
        started = true
        session.apply(.cancel)
        session.apply(.tapTalk)
        eventHandler?(.state(session.state))
        return ""
    }

    func speak(_ text: String) async {
        speakInvoked = true
        spoken.append(text)
        eventHandler?(.timing(.firstAudio))
        eventHandler?(.timing(.replyDone))
    }

    func sendTextTurn(_ text: String) async {
        sentTurns.append(text)
    }

    func cancel() {
        cancelled = true
        session.apply(.cancel)
        eventHandler?(.state(session.state))
    }

    func emitUser(_ text: String, itemID: String? = nil) {
        eventHandler?(.userTranscript(text, isFinal: true, itemID: itemID))
    }

    func emitAssistant(_ text: String, isFinal: Bool) {
        if !assistantOutputSuppressed {
            grokSpoken.append(text)
        }
        eventHandler?(.assistantTranscript(text, isFinal: isFinal))
    }

    func updatePresenceInstructions(_ text: String) {
        _ = text
    }

    func interruptResponse() {}

    func suppressAssistantOutput(_ suppress: Bool) {
        assistantOutputSuppressed = suppress
    }
}

@MainActor
final class GoogleSliceTests: XCTestCase {
    func testMissingClientIDDoesNotFakeConnected() async {
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .missingClientID()
        )
        await model.connectGoogle()
        XCTAssertFalse(model.google.isConnected)
        XCTAssertTrue(model.google.setupNeeded)
        XCTAssertTrue((model.turns.last?.text ?? "").contains("GOOGLE_CLIENT_ID"))
        XCTAssertTrue(model.activity.contains { $0.outcome.contains("Not connected") })
    }

    func testConnectSyncsRealCardsNotSampleDesk() async {
        let cache = MemoryDeskCache()
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(),
            cache: cache,
            sync: MockGoogleSync(result: DeskSnapshot(emails: [SampleData.syncedEmail()]))
        )
        await model.connectGoogle()
        XCTAssertTrue(model.google.isConnected)
        XCTAssertEqual(model.deskSnapshot.emails.first?.subject, "Inspection questions")
        XCTAssertEqual(cache.load().emails.first?.fromName, "Ada Cole")

        await model.applyUserTurn("What's in my inbox?")
        let emails = model.turns.flatMap(\.cards).compactMap { card -> EmailItem? in
            if case .email(let item) = card { return item }
            return nil
        }
        XCTAssertEqual(emails.first?.subject, "Inspection questions")
        XCTAssertFalse(emails.contains { $0.fromName.contains("Jordan") })
    }

    func testSignOutClearsCachedMail() async {
        let cache = MemoryDeskCache()
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(),
            cache: cache,
            sync: MockGoogleSync()
        )
        await model.connectGoogle()
        XCTAssertFalse(cache.load().emails.isEmpty)
        model.disconnectGoogle()
        XCTAssertFalse(model.google.isConnected)
        XCTAssertTrue(model.deskSnapshot.emails.isEmpty)
        XCTAssertTrue(cache.load().emails.isEmpty)
        XCTAssertTrue(model.activity.contains { $0.outcome.contains("Signed out") })
    }

    func testOfflineConfirmQueuesAndDoesNotClaimDelivered() async {
        let send = RecordingSendClient(isOnline: false)
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            sendClient: send,
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [SampleData.syncedEmail()])),
            isOnline: false
        )
        await model.applyUserTurn("Draft a reply to Jordan")
        let draft = model.turns.flatMap(\.cards).compactMap { card -> DraftConfirmItem? in
            if case .draftConfirm(let item) = card { return item }
            return nil
        }.first
        XCTAssertNotNil(draft)
        XCTAssertTrue(draft!.toLine.contains("ada.cole@example.com"))
        model.confirmDraft(draft!.id)
        XCTAssertEqual(send.sentDrafts.count, 1)
        XCTAssertTrue(model.activity.contains { $0.outcome.contains("Queued") })
        XCTAssertFalse(model.activity.contains { $0.outcome == "Delivered." })
    }

    func testInboxAskWhenDisconnectedOffersConnectNotSampleMail() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn("What's in my inbox?")
        let kinds = model.turns.flatMap(\.cards).map(\.kind)
        XCTAssertTrue(kinds.contains(.connectGoogle))
        XCTAssertFalse(kinds.contains(.email))
    }

    func testConnectTimesOutInsteadOfHanging() async {
        let google = GoogleSession(backend: HangingGoogleAuthBackend(), clientIDConfigured: true)
        await google.connect(timeoutSeconds: 0.15)
        XCTAssertFalse(google.isConnected)
        XCTAssertEqual(google.snapshot.state, .failed)
        XCTAssertTrue((google.snapshot.message ?? "").contains("timed out"))
    }
}

@MainActor
final class HangingGoogleAuthBackend: GoogleAuthBackend {
    func signIn() async throws -> (email: String, token: String) {
        try await Task.sleep(for: .seconds(30))
        return ("ada@example.com", "token")
    }

    func signOut() {}

    func restore() async -> (email: String, token: String)? { nil }

    func handleURL(_ url: URL) -> Bool { false }
}
