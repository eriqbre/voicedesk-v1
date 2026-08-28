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

    func testTappingAlreadyOpenEmailCardCollapsesToCompact() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn(ConversationPresence.deskPreview)
        let email = model.turns.flatMap(\.cards).compactMap { card -> EmailItem? in
            if case .email(let item) = card { return item }
            return nil
        }.first
        guard let email else {
            XCTFail("expected an already-open preview email")
            return
        }
        XCTAssertEqual(email.cardPresentation, .full)
        XCTAssertFalse(email.isCompactListRow)

        let epoch = model.conversationScrollEpoch
        let turns = model.turns.count
        model.toggleEmailCard(email)
        XCTAssertEqual(emailPresentation(in: model, matching: email), .compact)
        XCTAssertTrue(emailItem(in: model, matching: email)?.isCompactListRow == true)
        XCTAssertEqual(model.conversationScrollEpoch, epoch)
        XCTAssertEqual(model.turns.count, turns)

        model.toggleEmailCard(email)
        XCTAssertEqual(emailPresentation(in: model, matching: email), .full)
        XCTAssertFalse(emailItem(in: model, matching: email)?.isCompactListRow == true)

        model.toggleEmailCard(email)
        XCTAssertEqual(emailPresentation(in: model, matching: email), .compact)
        XCTAssertEqual(model.turns.count, turns)
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

    func testUnconfiguredTalkDoesNotFakeAConversation() async throws {
        try Self.skipLiveTalkSessionOnSimulatorHAL()
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

    func testLiveTranscriptsMirrorIntoTheThreadAndAttachDeskCards() async throws {
        try Self.skipLiveTalkSessionOnSimulatorHAL()
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

    func testLiveHowToConnectGoogleAttachesCardOnUserTranscript() async throws {
        try Self.skipLiveTalkSessionOnSimulatorHAL()
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
        let voice = MockVoiceService(label: "test", instant: true)
        let model = AppModel(
            voice: voice,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [email])),
            sync: sync
        )
        await model.applyUserTurn("pull up details on Murray's email")
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""),
            model.turns.last?.text ?? ""
        )
        XCTAssertTrue(voice.spoken.contains { $0.contains("Walk the lot Saturday") })
        XCTAssertFalse(voice.spoken.contains { EmailSummary.containsUIChrome($0) })
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
        let voice = MockVoiceService(label: "test", instant: true)
        let model = AppModel(
            voice: voice,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [email])),
            sync: sync
        )
        await model.applyUserTurn("summarize Murray's email")
        XCTAssertEqual(sync.fetchCalls, 2)
        XCTAssertEqual(model.deskSnapshot.emails.first?.body, "Walk the lot Saturday at 10.")
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""))
        XCTAssertTrue(voice.spoken.contains { $0.contains("Walk the lot Saturday") })
        XCTAssertFalse(voice.spoken.contains { EmailSummary.containsUIChrome($0) })
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

    func testLiveCalendarReplyAttachesCardsAndScrolls() async {
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
        let epoch = model.conversationScrollEpoch
        await model.applyUserTurn("What's on my calendar?")
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .calendar } == true)
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""),
            "calendar overview is cards-only: \(model.turns.last?.text ?? "")"
        )
        XCTAssertTrue(fake.spoken.contains { InboxGlance.isShortSpokenSummary($0) })
        XCTAssertFalse(fake.spoken.contains { InboxGlance.isShortSpokenAck($0) })
        XCTAssertTrue(fake.sentTurns.isEmpty, "calendar is on-device TTS; Grok stays in listen")
        if case .calendar(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.notes, "Window table, party of 4.")
        } else {
            XCTFail("expected attached calendar card")
        }
        XCTAssertGreaterThan(model.conversationScrollEpoch, epoch)
        XCTAssertEqual(model.conversationScrollTarget, model.turns.last?.id)
        XCTAssertEqual(model.conversationScrollAnchor, .top)
    }

    func testVersionAskSpeaksFixtureMarketingWithoutCardsOrGmail() async {
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
            sync: MockGoogleSync(result: snapshot),
            buildIdentity: .fixture
        )

        await model.applyUserTurn("Hey, show me Murray's latest email.")
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .email } == true)

        await model.applyUserTurn("what's on the phone")
        XCTAssertEqual(model.turns.last?.text, "VoiceDesk point 1, build 6.")
        XCTAssertTrue(model.turns.last?.cards.isEmpty == true)
        XCTAssertTrue(fake.spoken.contains("VoiceDesk point 1, build 6."))
        XCTAssertTrue(fake.sentTurns.isEmpty, "version is on-device TTS, not a Grok turn")

        await model.applyUserTurn("Can you show it to me?")
        XCTAssertNotEqual(model.turns.last?.text, "VoiceDesk point 1, build 6.")
        XCTAssertGreaterThanOrEqual(
            model.turns.last?.cards.count ?? 0,
            2,
            "cleared sticky must list inbox, not reopen Murray as the focused thread"
        )
    }

    func testWhatsOnMyCalendarStaysCalendarWhenVersionExists() async {
        let event = CalendarItem(
            title: "Dinner reservation",
            whenLabel: "Tonight 7:00 PM",
            location: "Oak & Stone",
            relatedPeople: ["Massimo Ricci"]
        )
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(events: [event])),
            buildIdentity: .fixture
        )
        await model.applyUserTurn("what's on my calendar")
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .calendar } == true)
        XCTAssertNotEqual(model.turns.last?.text, "VoiceDesk point 1, build 6.")

        await model.applyUserTurn("what's on the phone")
        XCTAssertEqual(model.turns.last?.text, "VoiceDesk point 1, build 6.")
        XCTAssertTrue(model.turns.last?.cards.isEmpty == true)
    }

    func testLiveEchoAfterVersionSpeakIsDroppedAndRealAsksStay() async {
        let event = CalendarItem(
            title: "Dinner reservation",
            whenLabel: "Tonight 7:00 PM",
            location: "Oak & Stone",
            relatedPeople: ["Massimo Ricci"]
        )
        var lauren = SampleData.syncedEmail()
        lauren.fromName = "Laren Cole"
        lauren.providerID = "msg-laren"
        lauren.subject = "Walk-through window"
        lauren.body = "Can we do Thursday at 11?"
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [lauren], events: [event])),
            buildIdentity: .fixture
        )
        await model.applyUserTurn("what's on the phone")
        XCTAssertTrue(fake.spoken.contains("VoiceDesk point 1, build 6."))
        XCTAssertTrue(fake.sentTurns.isEmpty)

        await model.applyUserTurn("what's on my calendar")
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .calendar } == true)
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""))
        XCTAssertNotEqual(model.turns.last?.text, "VoiceDesk point 1, build 6.")

        await model.applyUserTurn("latest email from Lauren")
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .email } == true)
    }

    func testSHAAskSpeaksFixtureSHAWithoutInventing() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            buildIdentity: .fixture
        )
        await model.applyUserTurn("what SHA is this")
        XCTAssertEqual(model.turns.last?.text, "VoiceDesk 1fa0a0e.")
        XCTAssertTrue(fake.spoken.contains("VoiceDesk 1fa0a0e."))
        XCTAssertTrue(model.turns.last?.cards.isEmpty == true)
    }

    func testUnknownBuildIdentityNeverInventsAVersionOrSHA() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            buildIdentity: .unknown
        )
        await model.applyUserTurn("what's on the phone")
        XCTAssertEqual(model.turns.last?.text, "VoiceDesk, unknown version.")
        XCTAssertTrue(fake.spoken.contains("VoiceDesk, unknown version."))
        XCTAssertFalse((model.turns.last?.text ?? "").contains("1fa0a0e"))
        XCTAssertFalse((model.turns.last?.text ?? "").contains("0.1"))

        await model.applyUserTurn("what SHA is this")
        XCTAssertEqual(model.turns.last?.text, "VoiceDesk, unknown SHA.")
        XCTAssertTrue(fake.spoken.contains("VoiceDesk, unknown SHA."))
        XCTAssertFalse((model.turns.last?.text ?? "").contains("1fa0a0e"))
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
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""),
            "thread summary is spoken, not reprinted: \(model.turns.last?.text ?? "")"
        )
        XCTAssertTrue(
            fake.spoken.contains {
                $0.lowercased().contains("thread") || $0.lowercased().contains("earlier")
                    || $0.lowercased().contains("walk the lot")
            },
            "\(fake.spoken)"
        )
        XCTAssertFalse(fake.spoken.contains { $0.lowercased().contains("can't pull") })
        XCTAssertFalse(fake.spoken.contains { $0.lowercased().contains("not in my last sync") })
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
        XCTAssertTrue(
            model.deskSnapshot.emails.isEmpty,
            "search hits must not replace the inbox snapshot"
        )
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("not in last sync"))
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("not in my last sync"))
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("i can search"))
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("can search gmail"))
        XCTAssertFalse(model.turns.contains { $0.text.lowercased().contains("i can search gmail") })
    }

    func testMurraySeveralMatchesThenMostRecentPicksNewestNotGrok() async {
        func murray(id: String, subject: String, label: String, body: String) -> EmailItem {
            var item = SampleData.syncedEmail()
            item.fromName = "Murray Mitchell"
            item.fromEmail = "murray@example.com"
            item.providerID = id
            item.subject = subject
            item.sentAtLabel = label
            item.preview = body
            item.body = body
            return item
        }
        let oldest = murray(
            id: "msg-murray-old",
            subject: "Old walk-through",
            label: "Yesterday 4:00 PM",
            body: "Can we walk the lot next week?"
        )
        let middle = murray(
            id: "msg-murray-mid",
            subject: "Closing / notarization",
            label: "Today 9:00 AM",
            body: "Need you to notarize the closing package today."
        )
        let newest = murray(
            id: "msg-murray-new",
            subject: "Walk-through today",
            label: "Today 2:00 PM",
            body: "Buyer is at the lot now — can you meet?"
        )
        let sync = MockGoogleSync(result: .empty)
        sync.searchable = [oldest, middle, newest]
        sync.bodies[oldest.providerID ?? ""] = oldest.body ?? ""
        sync.bodies[middle.providerID ?? ""] = middle.body ?? ""
        sync.bodies[newest.providerID ?? ""] = newest.body ?? ""
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(),
            sync: sync
        )

        await model.applyUserTurn("Give me a summary of Murray's last email.")
        XCTAssertTrue(fake.sentTurns.isEmpty, "named-sender clarify is on-device TTS")
        XCTAssertEqual(model.turns.last?.text, ConversationPresence.gmailSearchSeveralReply)
        XCTAssertEqual(model.turns.last?.cards.filter { $0.kind == .email }.count, 3)

        await model.applyUserTurn("The last one.")
        XCTAssertTrue(fake.sentTurns.isEmpty, "clarify pick must not inject a Grok user turn")
        XCTAssertNotEqual(model.turns.last?.text, ConversationPresence.gmailSearchSeveralReply)
        XCTAssertFalse((model.turns.last?.text ?? "").localizedCaseInsensitiveContains("stay quiet"))
        XCTAssertFalse((model.turns.last?.text ?? "").localizedCaseInsensitiveContains("ios app handles"))
        XCTAssertFalse((model.turns.last?.text ?? "").localizedCaseInsensitiveContains("i’ll stay quiet"))
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
            XCTAssertEqual(item.subject, "Walk-through today")
            XCTAssertEqual(item.providerID, "msg-murray-new")
        } else {
            XCTFail("expected newest Murray card")
        }
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""),
            model.turns.last?.text ?? ""
        )
        let spoken = fake.spoken.last ?? ""
        XCTAssertTrue(
            spoken.localizedCaseInsensitiveContains("lot")
                || spoken.localizedCaseInsensitiveContains("buyer")
                || spoken.localizedCaseInsensitiveContains("meet"),
            spoken
        )
        XCTAssertNotEqual(fake.spoken.last, ConversationPresence.gmailSearchSeveralReply)
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
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
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
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""),
            "full summary is spoken, not reprinted: \(model.turns.last?.text ?? "")"
        )
        XCTAssertTrue(
            fake.spoken.contains { $0.contains("Need you to notarize") || $0.contains("buyer is coming") },
            "\(fake.spoken)"
        )
        XCTAssertTrue(
            fake.spoken.contains { $0.lowercased().contains("earlier") || $0.contains("walk the lot") },
            "\(fake.spoken)"
        )
        XCTAssertTrue(fake.sentTurns.isEmpty)
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

    func testDeskReplySpeaksOnDeviceWithoutGrokTurn() async {
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
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""),
            model.turns.last?.text ?? ""
        )
        XCTAssertEqual(fake.spoken.count, 1)
        let spoken = fake.spoken[0]
        XCTAssertTrue(spoken.contains("Need you to notarize"), spoken)
        XCTAssertFalse(fake.spoken.contains(ConversationPresence.gmailSearchingBeat))
        XCTAssertTrue(fake.sentTurns.isEmpty, "desk speak is client TTS; do not inject a Grok turn")

        await model.applyUserTurn("full summary of Murray’s latest email")
        XCTAssertEqual(fake.spoken, [spoken], "same desk reply must not be spoken twice")
        XCTAssertTrue(fake.sentTurns.isEmpty)
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
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""),
            "search hit is cards-only: \(model.turns.last?.text ?? "")"
        )
        XCTAssertEqual(fake.spoken.first, ConversationPresence.emailNeedMoreReply)
        XCTAssertTrue(
            (fake.spoken.last ?? "").contains("ShowingTime")
                || (fake.spoken.last ?? "").localizedCaseInsensitiveContains("showing"),
            "\(fake.spoken)"
        )
        XCTAssertFalse(fake.spoken.contains(ConversationPresence.gmailSearchingBeat))
        XCTAssertTrue(fake.sentTurns.isEmpty)
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .email } == true)
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
        XCTAssertFalse(
            model.turns.contains { ConversationPresence.isGrokDeskRefusal($0.text) },
            "live refusal must never become a turn"
        )
        await model.applyUserTurn("full summary of Murray’s latest email")
        XCTAssertFalse(model.turns.contains { ConversationPresence.isGrokDeskRefusal($0.text) })
        XCTAssertTrue(model.turns.last?.cards.contains { $0.kind == .email } == true)
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""))
        XCTAssertTrue(fake.spoken.contains { $0.contains("Need you to notarize") })
        XCTAssertFalse(fake.spoken.contains { ConversationPresence.isGrokDeskRefusal($0) })
        XCTAssertTrue(fake.sentTurns.isEmpty)
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
        XCTAssertFalse(
            model.turns.contains { ConversationPresence.isGrokDeskHandoff($0.text) },
            "handoff meta must never become a turn"
        )
        await model.applyUserTurn("summarize the Murray email")
        XCTAssertFalse(model.turns.contains { ConversationPresence.isGrokDeskHandoff($0.text) })
        XCTAssertFalse(model.turns.contains { $0.text.localizedCaseInsensitiveContains("let the app handle") })
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""))
        let spoken = fake.spoken.last ?? ""
        XCTAssertTrue(spoken.contains("Murray Mitchell") || spoken.contains("Need you to notarize"), spoken)
        XCTAssertNotEqual(spoken, model.turns.last?.text)
        XCTAssertFalse(fake.spoken.contains { $0.localizedCaseInsensitiveContains("let the app handle") })
        fake.emitAssistant("I'll have the app look that up.", isFinal: true)
        XCTAssertFalse(model.turns.contains { $0.text.localizedCaseInsensitiveContains("look that up") })
        XCTAssertTrue(fake.sentTurns.isEmpty)
    }

    func testInboxOverviewAttachesCompactRowsAndSpeaksDigest() async throws {
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
        let ask = "summary of my latest emails"
        let dump = InboxGlance.spokenInbox(ask: ask, emails: snapshot.emails)
        XCTAssertTrue(InboxGlance.isFromSubjectGlanceDump(dump), dump)
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot)
        )
        await model.applyUserTurn(ask)
        let cards = model.turns.last?.cards ?? []
        XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(cards.allSatisfy { card in
            if case .email(let item) = card { return item.isCompactListRow }
            return false
        })
        let onScreen = model.turns.last?.text ?? ""
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(onScreen),
            "glance is cards-only: \(onScreen)"
        )
        XCTAssertFalse(
            fake.spoken.contains { InboxGlance.isFromSubjectGlanceDump($0) },
            "677abb9 client digest: \(fake.spoken)"
        )
        XCTAssertFalse(fake.spoken.contains { InboxGlance.isShortSpokenAck($0) }, "\(fake.spoken)")
        XCTAssertFalse(fake.spoken.contains { $0 == "Here they are." })
        XCTAssertFalse(fake.spoken.contains(dump))
        XCTAssertTrue(fake.sentTurns.isEmpty)

        let epoch = model.conversationScrollEpoch
        let target = model.conversationScrollTarget
        let spokenCount = fake.spoken.count
        let turnCount = model.turns.count
        if case .email(let item) = cards.first {
            model.toggleEmailCard(item)
            XCTAssertEqual(model.conversationScrollEpoch, epoch, "expand must stay in place")
            XCTAssertEqual(model.conversationScrollTarget, target)
            XCTAssertEqual(emailPresentation(in: model, matching: item), .full)
            XCTAssertFalse(emailItem(in: model, matching: item)?.isCompactListRow == true)

            model.toggleEmailCard(item)
            XCTAssertEqual(model.conversationScrollEpoch, epoch, "collapse must stay in place")
            XCTAssertEqual(model.conversationScrollTarget, target)
            XCTAssertEqual(emailPresentation(in: model, matching: item), .compact)
            XCTAssertTrue(emailItem(in: model, matching: item)?.isCompactListRow == true)
            XCTAssertEqual(model.turns.count, turnCount, "toggle must not add a bubble")
            XCTAssertEqual(fake.spoken.count, spokenCount, "toggle must not re-speak the card")
        } else {
            XCTFail("expected compact email to expand")
        }

        // Live overview: Eve after tool-done, not a client dump, not empty-then-cards.
        // Different synonym so TranscriptDedupe does not swallow the typed ask.
        _ = await fake.startListening()
        fake.emitUser("show me my latest emails")
        let deadline = ContinuousClock.now + .milliseconds(2000)
        while ContinuousClock.now < deadline {
            if fake.endToolWaitCount > 0 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(fake.beginToolWaitCount, 0, "fd4a772 never waited on tools")
        XCTAssertGreaterThan(fake.endToolWaitCount, 0, "fd4a772 no Eve create after tools")
        XCTAssertTrue(
            fake.sentResponseCreate,
            "fd4a772 create-without-words: endToolWait with no tool-done payload"
        )
        XCTAssertTrue(fake.sawThinkingDuringTools, "client loading at tool start")
        let payload = try XCTUnwrap(fake.toolDoneOutputs.first)
        XCTAssertFalse(InboxGlance.isFromSubjectGlanceDump(payload), payload)
        XCTAssertNotEqual(payload, dump)
        XCTAssertTrue(payload.contains(murray.fromName), payload)
        XCTAssertTrue(payload.contains(murray.subject), payload)
        XCTAssertFalse(
            fake.spoken.contains { InboxGlance.isFromSubjectGlanceDump($0) },
            "\(fake.spoken)"
        )
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
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""))
        let spoken = fake.spoken.last ?? ""
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("notarize"), spoken)
        XCTAssertTrue(
            spoken.localizedCaseInsensitiveContains("Thursday")
                || spoken.localizedCaseInsensitiveContains("Beach Drive")
                || spoken.localizedCaseInsensitiveContains("buyer"),
            spoken
        )
        XCTAssertFalse(EmailSummary.containsUIChrome(spoken), spoken)
        XCTAssertEqual(fake.spoken.last, spoken)
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
        XCTAssertFalse(
            fake.spoken.contains { InboxGlance.isFromSubjectGlanceDump($0) },
            "677abb9 typed glance dump: \(fake.spoken)"
        )
        XCTAssertFalse(fake.spoken.contains { $0.contains("Murray Mitchell") }, "\(fake.spoken)")
        XCTAssertFalse(fake.spoken.contains { InboxGlance.isShortSpokenAck($0) }, "\(fake.spoken)")
        let onScreen = model.turns.last?.text ?? ""
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(onScreen),
            "cards are the list; bubble must not reprint the glance: \(onScreen)"
        )
        XCTAssertFalse(InboxGlance.repeatsGlanceLines(onScreen), onScreen)
        XCTAssertTrue(model.turns.last?.cards.allSatisfy { card in
            if case .email(let item) = card { return item.isCompactListRow }
            return false
        } == true)

        await model.applyUserTurn("summarize that email from John Madison")
        XCTAssertEqual(fake.spoken.count, 1, "Madison follow-up speaks; glance dump does not")
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""))
        XCTAssertTrue((fake.spoken.last ?? "").contains("John Madison")
                      || (fake.spoken.last ?? "").contains("Beach Drive")
                      || (fake.spoken.last ?? "").contains("talk numbers"))
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "John Madison")
            XCTAssertFalse(item.isCompactListRow)
        } else {
            XCTFail("expected John Madison full card")
        }
        XCTAssertTrue(fake.sentTurns.isEmpty)
    }

    func testLiveGlanceBeatAmbientDoesNotCancelAndCommandTakesTurn() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-barge"
        murray.subject = "Closing / notarization"
        murray.body = "Need you to notarize the closing package today."
        var steve = SampleData.syncedEmail()
        steve.fromName = "Steve Brown"
        steve.fromEmail = "steve@example.com"
        steve.providerID = "msg-steve-barge"
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
        await model.applyUserTurn("see my latest emails")
        let afterGlance = model.turns.count
        XCTAssertFalse(
            fake.spoken.contains { InboxGlance.isFromSubjectGlanceDump($0) },
            "677abb9 typed glance dump: \(fake.spoken)"
        )
        XCTAssertFalse(fake.spoken.contains { InboxGlance.isShortSpokenAck($0) })

        fake.hasPendingPlayback = true
        fake.emitPartial("radio in the other room")
        XCTAssertEqual(fake.interruptCount, 0, "energy / partial must not cancel her")
        XCTAssertEqual(model.turns.count, afterGlance)

        fake.emitUser("and now the weather")
        XCTAssertEqual(fake.interruptCount, 0, "ambient speech must not cancel her")
        XCTAssertEqual(model.turns.count, afterGlance, "radio stays ignored")

        fake.emitUser("Can you hear me?")
        XCTAssertEqual(fake.interruptCount, 0)
        XCTAssertEqual(model.turns.count, afterGlance)

        fake.emitUser("show me Murray's latest email")
        XCTAssertEqual(fake.interruptCount, 1, "command intent drops playback")
        XCTAssertFalse(fake.hasPendingPlayback)
        XCTAssertGreaterThan(model.turns.count, afterGlance, "command-shaped ask is the next turn")
        XCTAssertTrue(fake.sentTurns.isEmpty)
    }

    /// DD56F6A9 8:56 "Show me my latest emails." 677abb9 spoke
    /// InboxGlance.spokenInbox (from/subject dump) then 5 cards.
    /// handleLiveUser must not client-speak that dump. Tools, then Eve
    /// via endToolWaitCreate. Not empty-then-cards. Not Here they are.
    func testLiveLatestEmailsDoesNotSpeakFromSubjectGlanceThenCards() async throws {
        let snapshot = DeskSnapshot(emails: [
            VoiceRegressionDesk.murray,
            VoiceRegressionDesk.steve,
            VoiceRegressionDesk.greenacre
        ])
        let ask = "Show me my latest emails."
        let dump = InboxGlance.spokenInbox(ask: ask, emails: snapshot.emails)
        XCTAssertTrue(
            InboxGlance.isFromSubjectGlanceDump(dump),
            "677abb9 mouth was this dump: \(dump)"
        )
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot)
        )
        _ = await fake.startListening()
        fake.emitUser(ask)
        let deadline = ContinuousClock.now + .milliseconds(2000)
        while ContinuousClock.now < deadline {
            if fake.endToolWaitCount > 0 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(
            fake.beginToolWaitCount,
            0,
            "fd4a772 empty-reply-then-cards never waited on tools"
        )
        XCTAssertGreaterThan(
            fake.endToolWaitCount,
            0,
            "fd4a772 empty-reply-then-cards: no Eve create after tools"
        )
        XCTAssertTrue(
            fake.sentResponseCreate,
            "fd4a772 create-without-words: endToolWait with no tool-done payload"
        )
        XCTAssertTrue(fake.sawThinkingDuringTools, "client loading at tool start")
        XCTAssertNotEqual(fake.state, .thinking, "loading false when cards/tool done land")
        let payload = try XCTUnwrap(fake.toolDoneOutputs.first)
        XCTAssertFalse(
            InboxGlance.isFromSubjectGlanceDump(payload),
            "677abb9 dump on tool done: \(payload)"
        )
        XCTAssertNotEqual(payload, dump)
        XCTAssertTrue(payload.contains(VoiceRegressionDesk.murray.fromName), payload)
        XCTAssertTrue(payload.contains(VoiceRegressionDesk.murray.subject), payload)
        XCTAssertFalse(
            fake.spoken.contains { InboxGlance.isFromSubjectGlanceDump($0) },
            "677abb9 glance-then-cards mouth: \(fake.spoken)"
        )
        XCTAssertFalse(
            fake.spoken.contains(dump),
            "677abb9 spoke spokenInbox then cards: \(fake.spoken)"
        )
        XCTAssertFalse(fake.spoken.contains { InboxGlance.isShortSpokenAck($0) }, "\(fake.spoken)")
        XCTAssertFalse(fake.spoken.contains { $0 == "Here they are." })
        XCTAssertFalse(
            model.turns.contains { ConversationPresence.isThinkingBeat($0.text) },
            "thinking beat must clear when cards / tool-done land"
        )
        _ = model
    }

    /// Same leftover family on calendar overview. Do not lock
    /// spokenCalendar as the live mouth.
    func testLiveCalendarTomorrowDoesNotSpeakGlanceDumpThenCards() async throws {
        let snapshot = DeskSnapshot(events: [
            CalendarItem(title: "Walk the lot", whenLabel: "Tomorrow 9:00 AM"),
            CalendarItem(title: "Massimo showing", whenLabel: "Tomorrow 3:00 PM")
        ])
        let ask = "what's on my calendar tomorrow"
        let dump = InboxGlance.spokenCalendar(ask: ask, events: snapshot.events)
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot)
        )
        _ = await fake.startListening()
        fake.emitUser(ask)
        let deadline = ContinuousClock.now + .milliseconds(2000)
        while ContinuousClock.now < deadline {
            if fake.endToolWaitCount > 0 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(fake.beginToolWaitCount, 0, "must wait on tools")
        XCTAssertGreaterThan(
            fake.endToolWaitCount,
            0,
            "fd4a772 empty-reply-then-cards: no Eve create after tools"
        )
        XCTAssertTrue(
            fake.sentResponseCreate,
            "fd4a772 create-without-words: endToolWait with no tool-done payload"
        )
        XCTAssertTrue(fake.sawThinkingDuringTools, "client loading at tool start")
        XCTAssertNotEqual(fake.state, .thinking, "loading false when cards land")
        let payload = try XCTUnwrap(fake.toolDoneOutputs.first)
        XCTAssertNotEqual(payload, dump)
        XCTAssertTrue(payload.contains("Walk the lot"), payload)
        XCTAssertFalse(
            fake.spoken.contains(dump),
            "677abb9 spoke spokenCalendar then cards: \(fake.spoken)"
        )
        XCTAssertFalse(fake.spoken.contains { $0 == "Here they are." })
        XCTAssertFalse(
            model.turns.contains { ConversationPresence.isThinkingBeat($0.text) },
            "thinking beat must clear when cards land"
        )
        _ = model
    }

    /// bdbace4 walk 14B69B95: leftover Authentisign cards already on
    /// screen, then live latest-emails, then live calendar while Eve
    /// still had playback. yieldGrokInterruptAnswer returned before
    /// fulfill — mouth moved, cards stayed email, tape never wrote
    /// user/reply/cardsAttached. Tool-done must replace cards AND write
    /// the calendar tape. Not a log-only paper.
    func testLiveCalendarAfterLatestEmailsReplacesEmailCards() async throws {
        VoiceInteractionLog.resetForTests()
        let leftoverEmails = [
            EmailItem(
                fromName: "Authentisign",
                fromEmail: "notify@authentisign.example",
                sentAtLabel: "Yesterday 4:10 PM",
                subject: "Signature required 1650",
                preview: "Please review and sign",
                filterTag: "Inbox"
            ),
            EmailItem(
                fromName: "Authentisign",
                fromEmail: "notify@authentisign.example",
                sentAtLabel: "Yesterday 3:02 PM",
                subject: "Documents ready for signature",
                preview: "Your packet is ready",
                filterTag: "Inbox"
            ),
            EmailItem(
                fromName: "Authentisign",
                fromEmail: "notify@authentisign.example",
                sentAtLabel: "Yesterday 1:18 PM",
                subject: "Reminder: signature requested",
                preview: "Still waiting on a signature",
                filterTag: "Inbox"
            )
        ]
        let snapshot = DeskSnapshot(
            emails: leftoverEmails,
            events: [
                CalendarItem(title: "20th anniversary", whenLabel: "Tomorrow 5:30 PM"),
                CalendarItem(title: "Massimo showing", whenLabel: "Tomorrow 3:00 PM")
            ]
        )
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot)
        )
        model.turns.append(
            ConversationTurn(
                role: .assistant,
                text: "",
                cards: EmailItem.listCards(leftoverEmails)
            )
        )
        _ = await fake.startListening()
        fake.emitUser("Show me my latest emails.")
        var deadline = ContinuousClock.now + .milliseconds(2000)
        while ContinuousClock.now < deadline {
            if fake.endToolWaitCount > 0 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(fake.endToolWaitCount, 0)
        let afterMail = model.turns.last?.cards ?? []
        XCTAssertTrue(afterMail.contains { $0.kind == .email }, "\(afterMail)")

        let creates = fake.endToolWaitCount
        fake.hasPendingPlayback = true
        fake.emitUser("what's on my calendar tomorrow")
        deadline = ContinuousClock.now + .milliseconds(2000)
        while ContinuousClock.now < deadline {
            if fake.endToolWaitCount > creates { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(
            fake.endToolWaitCount,
            creates,
            "bdbace4 yield returned before fulfill — calendar never parked"
        )
        XCTAssertEqual(fake.interruptCount, 1, "command barge still drops leftover playback")
        XCTAssertTrue(fake.sentResponseCreate, "fd4a772 create-without-words")
        let visible = model.turns.last?.cards ?? []
        let calendarCards = snapshot.events.map { ContentCard.calendar($0) }
        XCTAssertFalse(
            LiveToolMouth.isStickyPriorDeskCards(visible: visible, current: calendarCards),
            "bdbace4 leftover Authentisign cards after calendar mouth: \(visible)"
        )
        XCTAssertFalse(visible.contains { $0.kind == .email }, "\(visible)")
        XCTAssertTrue(visible.contains { $0.kind == .calendar }, "\(visible)")
        XCTAssertTrue(
            model.turns.contains { $0.role == .user && $0.text == "what's on my calendar tomorrow" },
            "spoken calendar vanished from the transcript: \(model.turns.map(\.text))"
        )
        let tape = VoiceInteractionLog.snapshot().filter {
            !$0.userTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let calendarTape = tape.filter {
            $0.userTranscript.localizedCaseInsensitiveContains("calendar")
        }
        XCTAssertFalse(
            calendarTape.isEmpty,
            "bdbace4 vanished calendar tape (spoken-loop phantom only): \(VoiceInteractionLog.snapshot().map { $0.userTranscript })"
        )
        XCTAssertTrue(
            calendarTape.contains { entry in
                entry.cardsAttached.contains { $0.hasPrefix("calendar:") }
                    && !entry.cardsAttached.contains { $0.hasPrefix("email:") }
            },
            "calendar tape must attach calendar cards, not leftover email: \(calendarTape.map(\.cardsAttached))"
        )
        XCTAssertFalse(
            fake.spoken.contains { InboxGlance.isFromSubjectGlanceDump($0) },
            "\(fake.spoken)"
        )
        XCTAssertFalse(fake.spoken.contains { $0 == "Here they are." })
        _ = model
        VoiceInteractionLog.resetForTests()
    }

    /// 9cf53c4 9B23C3AA 9:01:32 leftover inbound `response.created`,
    /// then "What are my newest emails?" finishLiveTool wrote empty
    /// onScreenText + 5 cards and leftover inbound skipped the done
    /// mouth. Drive leftover inbound create, not a planted empty
    /// transcript. Cards + one done mouth after function_call_output.
    /// Do not force a looking-mouth.
    func testLiveNewestEmailsDoesNotAttachCardsOntoEmptyVADMouth() async throws {
        let inbox = [
            VoiceRegressionDesk.murray,
            VoiceRegressionDesk.steve,
            VoiceRegressionDesk.greenacre,
            VoiceRegressionDesk.laren,
            VoiceRegressionDesk.ericGross
        ]
        XCTAssertEqual(inbox.count, 5)
        XCTAssertTrue(InboxGlance.onScreenText(compactCardCount: 5).isEmpty)
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: inbox)),
            sync: MockGoogleSync(result: DeskSnapshot(emails: inbox))
        )
        _ = await fake.startListening()
        fake.emitLeftoverVADCreate()
        XCTAssertEqual(fake.leftoverInboundCreateCount, 1)
        XCTAssertFalse(
            fake.createdThisUserTurn,
            "leftover inbound response.created is not alreadyCreated"
        )
        fake.emitUser("What are my newest emails?")
        let deadline = ContinuousClock.now + .milliseconds(2000)
        while ContinuousClock.now < deadline {
            if fake.endToolWaitCount > 0 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(fake.beginToolWaitCount, 0, "tool start missing")
        XCTAssertTrue(
            fake.wireItems.contains { GrokRealtime.conversationItemType(inCreate: $0) == "function_call" },
            "start report must be on the existing wire: \(fake.wireItems)"
        )
        XCTAssertTrue(
            fake.wireItems.contains { GrokRealtime.conversationItemType(inCreate: $0) == "function_call_output" },
            "tool-done missing: \(fake.wireItems)"
        )
        XCTAssertTrue(
            fake.sentResponseCreate,
            "one done mouth after function_call_output — leftover inbound is not alreadyCreated"
        )
        XCTAssertTrue(fake.spoken.isEmpty, "do not force a looking-mouth: \(fake.spoken)")
        let emptyMouthCards = model.turns.filter {
            $0.role == .assistant
                && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.cards.isEmpty
        }
        XCTAssertTrue(
            emptyMouthCards.isEmpty,
            "9B23C3AA leftover inbound + empty + 5 cards: \(model.turns.map { "\($0.text) cards=\($0.cards.count)" })"
        )
        XCTAssertTrue(
            model.turns.flatMap(\.cards).contains { $0.kind == .email },
            "cards land with tool-done, not onto an empty leftover mouth"
        )
        _ = model
    }

    /// 9cf53c4 9B23C3AA 9:01:56 leftover inbound then
    /// “Read me the one from Costco.” ownsConnectedDeskTurn was false
    /// (hasDeskMailIntent required an “email” word). Fall-through let
    /// leftover VAD speak Costco with no function_call. No planted
    /// leftover empty mouth. Assistant-only — user text has Costco.
    func testLiveCostcoDoesNotSpeakWithoutToolReport() async throws {
        let snapshot = DeskSnapshot(
            emails: [
                VoiceRegressionDesk.murray,
                EmailItem(
                    providerID: "fixture-costco",
                    fromName: "Costco",
                    fromEmail: "receipts@costco.example",
                    sentAtLabel: "Yesterday 6:12 PM",
                    subject: "Your Costco.com order",
                    preview: "Thanks for your order",
                    filterTag: "Inbox"
                )
            ]
        )
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot)
        )
        _ = await fake.startListening()
        fake.emitLeftoverVADCreate()
        XCTAssertEqual(fake.leftoverInboundCreateCount, 1)
        XCTAssertFalse(fake.createdThisUserTurn)
        fake.emitUser("Read me the one from Costco.")
        let deadline = ContinuousClock.now + .milliseconds(2000)
        while ContinuousClock.now < deadline {
            if fake.endToolWaitCount > 0 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(fake.beginToolWaitCount, 0, "9cf53c4 Costco never commanded a tool")
        XCTAssertTrue(
            fake.wireItems.contains { GrokRealtime.conversationItemType(inCreate: $0) == "function_call" },
            "Costco must be on the existing wire: \(fake.wireItems)"
        )
        XCTAssertTrue(
            fake.wireItems.contains { GrokRealtime.conversationItemType(inCreate: $0) == "function_call_output" },
            "tool-done missing: \(fake.wireItems)"
        )
        XCTAssertTrue(fake.spoken.isEmpty, "do not force a looking-mouth: \(fake.spoken)")
        XCTAssertFalse(
            model.turns.contains {
                $0.role == .assistant && $0.text.localizedCaseInsensitiveContains("Costco")
            },
            "leftover VAD desk answer landed without a tool report: \(model.turns.map { "\($0.role) \($0.text)" })"
        )
        _ = model
    }

    /// 9cf53c4 9B23C3AA leftover inbound then the walk phrase.
    /// Presence used to list Massimo on the session so leftover VAD
    /// could speak him with no function_call. Delete that injection.
    /// Do not invent a command. No planted leftover empty mouth.
    func testLiveAppointmentsTonightDoesNotSpeakWithoutToolReport() async throws {
        let snapshot = DeskSnapshot(
            emails: [VoiceRegressionDesk.murray],
            events: [
                CalendarItem(
                    title: "Massimo showing",
                    whenLabel: "Tonight 5:30 PM",
                    relatedPeople: ["Massimo Ricci"]
                )
            ]
        )
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot)
        )
        _ = await fake.startListening()
        XCTAssertFalse(
            fake.lastPresenceInstructions.contains("Massimo showing"),
            "9cf53c4 calendar leak: \(fake.lastPresenceInstructions)"
        )
        fake.emitLeftoverVADCreate()
        XCTAssertEqual(fake.leftoverInboundCreateCount, 1)
        XCTAssertFalse(fake.createdThisUserTurn)
        fake.emitUser("Do I have any appointments tonight?")
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(
            fake.beginToolWaitCount,
            0,
            "do not invent a command for the walk phrase"
        )
        XCTAssertFalse(
            fake.wireItems.contains { GrokRealtime.conversationItemType(inCreate: $0) == "function_call" },
            "walk phrase still no-tool: \(fake.wireItems)"
        )
        XCTAssertTrue(fake.spoken.isEmpty, "do not force a looking-mouth: \(fake.spoken)")
        XCTAssertFalse(
            fake.spoken.contains { $0.localizedCaseInsensitiveContains("Massimo") }
        )
        XCTAssertFalse(
            model.turns.contains {
                $0.role == .assistant && $0.text.localizedCaseInsensitiveContains("Massimo")
            },
            "leftover VAD desk answer landed without a tool report: \(model.turns.map { "\($0.role) \($0.text)" })"
        )
        _ = model
    }

    /// a85473b leftover: leftover Authentisign already on screen, then a
    /// real calendar user bubble. Tools / Eve have not landed yet. Prior
    /// email cards must already be gone (empty/cleared). Not barge-only.
    /// Not emitAssistant. Not a fabricated tape row.
    func testLiveCalendarUserBubbleDropsLeftoverEmailCardsBeforeTools() async throws {
        let leftoverEmails = [
            EmailItem(
                fromName: "Authentisign",
                fromEmail: "notify@authentisign.example",
                sentAtLabel: "Yesterday 4:10 PM",
                subject: "Signature required 1650",
                preview: "Please review and sign",
                filterTag: "Inbox"
            ),
            EmailItem(
                fromName: "Authentisign",
                fromEmail: "notify@authentisign.example",
                sentAtLabel: "Yesterday 3:02 PM",
                subject: "CR-7_Q",
                preview: "Signature packet",
                filterTag: "Inbox"
            ),
            EmailItem(
                fromName: "Authentisign",
                fromEmail: "notify@authentisign.example",
                sentAtLabel: "Yesterday 1:18 PM",
                subject: "Bridget signature",
                preview: "Please sign",
                filterTag: "Inbox"
            )
        ]
        let leftoverCards = EmailItem.listCards(leftoverEmails)
        let snapshot = DeskSnapshot(
            emails: leftoverEmails,
            events: [
                CalendarItem(title: "20th anniversary", whenLabel: "Tomorrow 5:30 PM"),
                CalendarItem(title: "Massimo showing", whenLabel: "Tomorrow 3:00 PM")
            ]
        )
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot)
        )
        model.turns.append(
            ConversationTurn(role: .assistant, text: "", cards: leftoverCards)
        )
        _ = await fake.startListening()
        XCTAssertTrue(
            model.turns.flatMap(\.cards).contains { $0.kind == .email },
            "precondition: leftover Authentisign cards on screen"
        )

        fake.emitUser("what's on my calendar tomorrow")
        XCTAssertTrue(
            model.turns.contains { $0.role == .user && $0.text == "what's on my calendar tomorrow" },
            "user-visible calendar turn must draw: \(model.turns.map(\.text))"
        )
        let visible = model.turns.flatMap(\.cards)
        XCTAssertFalse(
            visible.contains { $0.kind == .email },
            "a85473b leftover Authentisign cards after calendar user bubble: \(visible)"
        )
        XCTAssertTrue(
            visible.isEmpty || visible.allSatisfy { $0.kind == .calendar },
            "turn start must clear leftover email, or already show this turn's calendar: \(visible)"
        )
        XCTAssertFalse(fake.spoken.contains { $0 == "Here they are." })
        XCTAssertFalse(
            fake.spoken.contains { InboxGlance.isFromSubjectGlanceDump($0) },
            "\(fake.spoken)"
        )
        _ = model
    }

    /// Live service path after version + glance write→player. Same loop
    /// as `FirstHearTapLoop.versionThenGlanceWritePlayerThenThird`.
    func testVersionThenGlanceWritePlayerStayLiveThirdCommandIsATurn() async {
        let snapshot = DeskSnapshot(emails: [SampleData.syncedEmail()])
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot),
            buildIdentity: .fixture
        )

        await model.applyUserTurn("what version are we on")
        XCTAssertTrue(fake.spoken.contains { $0.contains("VoiceDesk") })
        XCTAssertTrue(fake.stayLiveAfterSpeak)
        XCTAssertTrue(fake.listenArmedAfterSpeak)
        XCTAssertFalse(fake.parkedSpeaking)
        XCTAssertNotEqual(fake.close1000AfterSpeak, .stayIdle)
        XCTAssertEqual(fake.startCount, 0)

        await model.applyUserTurn("show me my emails")
        XCTAssertTrue(fake.spoken.contains { $0.contains("VoiceDesk") })
        XCTAssertFalse(
            fake.spoken.contains { InboxGlance.isFromSubjectGlanceDump($0) },
            "677abb9 glance dump after version: \(fake.spoken)"
        )
        XCTAssertFalse(fake.spoken.contains { InboxGlance.isShortSpokenAck($0) })
        XCTAssertTrue(fake.stayLiveAfterSpeak, "glance write→player must stayLive")
        XCTAssertTrue(fake.listenArmedAfterSpeak)
        XCTAssertFalse(fake.parkedSpeaking, "leftover created/done must not park speaking")
        XCTAssertNotEqual(fake.close1000AfterSpeak, .stayIdle, "close 1000 stayIdle after glance is a fail")
        XCTAssertEqual(fake.startCount, 0, "write→player must not audio.start")

        let afterGlanceUsers = model.turns.filter { $0.role == .user }.map(\.text)
        fake.emitUser("what's on my calendar")
        XCTAssertEqual(
            model.turns.filter { $0.role == .user }.map(\.text),
            afterGlanceUsers + ["what's on my calendar"],
            "third command after glance is the next turn"
        )

        fake.hasPendingPlayback = true
        let turns = model.turns.count
        fake.emitUser("Can you hear me?")
        XCTAssertEqual(fake.interruptCount, 0, "ambient must not interruptPlayback")
        XCTAssertEqual(model.turns.count, turns)
        fake.emitUser("show calendar")
        XCTAssertEqual(fake.interruptCount, 1, "command intent drops playback")
        XCTAssertGreaterThan(model.turns.count, turns)
    }

    func testSpokenSentenceContainingStopDoesNotKillTheSession() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(voice: fake)
        fake.emitUser("I need to stop by the office at five")
        XCTAssertFalse(fake.cancelled)
        XCTAssertEqual(
            model.turns.filter { $0.role == .user }.last?.text,
            "I need to stop by the office at five"
        )
        fake.emitUser("Stop")
        XCTAssertTrue(fake.cancelled)
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

    func testLiveCancelStopsSessionWithoutFakeUtterance() async throws {
        try Self.skipLiveTalkSessionOnSimulatorHAL()
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

    /// `tapTalk()` plays `VoiceEarcon` through AVAudioPlayer. Simulator HAL
    /// hangs those live-session tests. Gate them — do not add more live audio.
    static func skipLiveTalkSessionOnSimulatorHAL() throws {
        throw XCTSkip(
            "Live-session only: tapTalk() / VoiceEarcon hangs on Simulator HAL audio. Do not add live audio."
        )
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<40 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out waiting for voice service")
    }

    private func emailItem(in model: AppModel, matching item: EmailItem) -> EmailItem? {
        for card in model.turns.flatMap(\.cards) {
            if case .email(let existing) = card,
               existing.id == item.id || (existing.providerID != nil && existing.providerID == item.providerID) {
                return existing
            }
        }
        return nil
    }

    private func emailPresentation(in model: AppModel, matching item: EmailItem) -> EmailCardPresentation? {
        emailItem(in: model, matching: item)?.cardPresentation
    }
}

/// Live Grok stand-in. Desk speak is `speak` (on-device TTS). `sentTurns` is
/// a fake Grok user turn — desk replies must not use it. The socket stays
/// in listen. No mute / suppress flags.
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
    var hasPendingPlayback = false
    var listenLoopBargeConsumed = false
    var interruptCount = 0
    /// Mic tap. Client TTS must not tear this down (fe1ffc8 resumeCapture).
    var tapLive = true
    /// Fired while client TTS is in-flight. Inject at this boundary once.
    var onClientTTS: (() -> Void)?
    /// Product startListening. Client TTS must not increment this.
    var startCount = 0
    var stayLiveAfterSpeak = false
    var listenArmedAfterSpeak = false
    var parkedSpeaking = false
    var close1000AfterSpeak: ListenResumeDecision = .stayIdle

    var state: VoiceState { session.state }

    func startListening() async -> String {
        started = true
        startCount += 1
        tapLive = true
        session.apply(.cancel)
        session.apply(.tapTalk)
        eventHandler?(.state(session.state))
        return ""
    }

    func speak(_ text: String) async {
        spoken.append(text)
        let after = ListenResumePolicy.afterClientTTSFinished(
            session: &session,
            userWantsVoiceOff: false,
            liveSessionArmed: true,
            captureRunning: tapLive
        )
        stayLiveAfterSpeak = after.stayLive
        listenArmedAfterSpeak = after.listenArmed
        parkedSpeaking = session.state == .speaking
        close1000AfterSpeak = after.close1000
        if after.startAgain {
            startCount += 1
        }
        onClientTTS?()
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
        guard tapLive else { return }
        eventHandler?(.userTranscript(text, isFinal: true, itemID: itemID))
    }

    /// 9B23C3AA leftover inbound `response.created` before the user
    /// transcript. Same alreadyCreated rule as GrokVoiceService
    /// (`response.created` does not set createdThisUserTurn). Not an
    /// empty assistantTranscript. Not a planted ConversationTurn.
    func emitLeftoverVADCreate() {
        leftoverInboundCreateCount += 1
    }

    func emitPartial(_ text: String, itemID: String? = nil) {
        guard tapLive else { return }
        eventHandler?(.userTranscript(text, isFinal: false, itemID: itemID))
    }

    func emitAssistant(_ text: String, isFinal: Bool) {
        eventHandler?(.assistantTranscript(text, isFinal: isFinal))
    }

    var lastPresenceInstructions = ""

    func updatePresenceInstructions(_ text: String) {
        lastPresenceInstructions = text
    }

    func interruptResponse() {
        guard hasPendingPlayback else { return }
        interruptCount += 1
        hasPendingPlayback = false
        listenLoopBargeConsumed = true
    }

    var beginToolWaitCount = 0
    var endToolWaitCount = 0
    var toolDoneOutputs: [String] = []
    var sawThinkingDuringTools = false
    var sentResponseCreate = false
    var createdThisUserTurn = false
    var leftoverInboundCreateCount = 0
    var wireItems: [String] = []

    func beginToolWaitCreate() {
        beginToolWaitCount += 1
        createdThisUserTurn = false
        session.apply(.listenFinished)
        eventHandler?(.state(session.state))
        if session.state == .thinking {
            sawThinkingDuringTools = true
        }
        appendWire(GrokRealtime.functionCallItemObject(
            name: LiveToolMouth.deskGlanceToolName,
            callID: "fake-call"
        ))
    }

    func reportToolResult(_ output: String) {
        toolDoneOutputs.append(output)
        appendWire(GrokRealtime.functionCallOutputItemObject(
            callID: "fake-call",
            output: output
        ))
        if session.state == .thinking {
            session.apply(.turnFinished)
            eventHandler?(.state(session.state))
        }
    }

    func endToolWaitCreate() {
        endToolWaitCount += 1
        sentResponseCreate = LiveToolMouth.shouldSendResponseCreate(
            toolWait: false,
            alreadyCreated: createdThisUserTurn,
            hasToolResult: !toolDoneOutputs.isEmpty
        )
        if sentResponseCreate {
            createdThisUserTurn = true
        }
    }

    private func appendWire(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let raw = String(data: data, encoding: .utf8) else { return }
        wireItems.append(raw)
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

    func testRestoreWithCachedAccountStillSyncsInbox() async {
        var stale = SampleData.syncedEmail()
        stale.fromName = "Old Sender"
        stale.subject = "Day-one snapshot"
        stale.providerID = "msg-restore-stale"
        var fresh = SampleData.syncedEmail()
        fresh.fromName = "New Sender"
        fresh.subject = "Arrived this morning"
        fresh.providerID = "msg-restore-fresh"
        fresh.body = "Signed this morning."
        let cache = MemoryDeskCache(
            snapshot: DeskSnapshot(
                accountEmail: "ada@example.com",
                lastSyncedAt: Date(timeIntervalSince1970: 100),
                emails: [stale]
            )
        )
        let sync = MockGoogleSync(result: DeskSnapshot(emails: [fresh]))
        let backend = MockGoogleAuthBackend()
        backend.restoreOnLaunch = true
        let google = GoogleSession(backend: backend, clientIDConfigured: true)
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: google,
            cache: cache,
            sync: sync
        )
        model.launchStatusHold = .zero
        XCTAssertEqual(model.deskSnapshot.emails.first?.subject, "Day-one snapshot")
        XCTAssertFalse(model.google.isConnected)

        await model.restoreGoogleIfNeeded()
        XCTAssertEqual(model.launchSyncPhase, .idle)
        XCTAssertFalse(model.turns.contains { LaunchSyncStatus.isSilent($0.text) })
        XCTAssertTrue(model.google.isConnected)
        XCTAssertEqual(sync.syncCalls, 1, "restore must hit Gmail even when cache already has accountEmail")
        XCTAssertEqual(model.deskSnapshot.emails.first?.subject, "Arrived this morning")
        XCTAssertTrue(
            model.deskSnapshot.emails.contains { $0.subject == "Day-one snapshot" },
            "restore merge must keep cached mail that is not in the latest pull"
        )
        XCTAssertEqual(model.deskSnapshot.accountEmail, "ada@example.com")
    }

    func testRestoreOfflineKeepsCachedInboxWithoutSync() async {
        var stale = SampleData.syncedEmail()
        stale.subject = "Day-one snapshot"
        stale.providerID = "msg-restore-offline"
        let cache = MemoryDeskCache(
            snapshot: DeskSnapshot(
                accountEmail: "ada@example.com",
                lastSyncedAt: Date(timeIntervalSince1970: 100),
                emails: [stale]
            )
        )
        let sync = MockGoogleSync(result: DeskSnapshot(emails: [SampleData.syncedEmail()]))
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: cache,
            sync: sync,
            isOnline: false
        )
        model.launchStatusHold = .zero
        await model.restoreGoogleIfNeeded()
        XCTAssertEqual(model.launchSyncPhase, .idle)
        XCTAssertFalse(model.turns.contains { LaunchSyncStatus.isSilent($0.text) })
        XCTAssertEqual(sync.syncCalls, 0)
        XCTAssertEqual(model.deskSnapshot.emails.first?.subject, "Day-one snapshot")
    }

    func testInboxOverviewWithCachedLatestFiveSkipsListRefresh() async {
        var stale = SampleData.syncedEmail()
        stale.fromName = "Old Sender"
        stale.subject = "Day-one snapshot"
        stale.providerID = "msg-overview-stale"
        stale.body = "Yesterday's mail."
        var fresh = SampleData.syncedEmail()
        fresh.fromName = "New Sender"
        fresh.subject = "Arrived this morning"
        fresh.providerID = "msg-overview-fresh"
        fresh.body = "Signed this morning."
        let cache = MemoryDeskCache(
            snapshot: DeskSnapshot(
                accountEmail: "ada@example.com",
                lastSyncedAt: Date(timeIntervalSince1970: 100),
                emails: [stale]
            )
        )
        let sync = MockGoogleSync(result: DeskSnapshot(emails: [fresh]))
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: cache,
            sync: sync
        )
        XCTAssertEqual(model.deskSnapshot.emails.first?.subject, "Day-one snapshot")
        await model.applyUserTurn("Can you pull my latest emails?")
        XCTAssertEqual(
            sync.syncCalls,
            0,
            "cache already has latest-5 — first glance must not wait on a Gmail list"
        )
        XCTAssertEqual(model.deskSnapshot.emails.first?.subject, "Day-one snapshot")
        XCTAssertTrue(
            model.turns.last?.cards.contains { card in
                if case .email(let item) = card { return item.subject == "Day-one snapshot" }
                return false
            } == true,
            "cards attach from the snapshot"
        )
    }

    func testInboxSyncMergesAgedOutFleemanInsteadOfReplacingStore() async {
        let fleeman = VoiceRegressionDesk.larenJansen
        let newer = (0..<GoogleSyncPolicy.recentInboxLimit).map { index in
            EmailItem(
                providerID: "inbox-newer-\(index)",
                fromName: index == 0 ? "Eriq Breland" : "Inbox \(index)",
                fromEmail: "inbox\(index)@example.com",
                sentAtLabel: "Today 4:00 PM",
                subject: "Newer inbox \(index)",
                preview: "Newer than Fleeman.",
                filterTag: "Inbox"
            )
        }
        let cache = MemoryDeskCache(
            snapshot: DeskSnapshot(
                accountEmail: "ada@example.com",
                lastSyncedAt: Date(timeIntervalSince1970: 100),
                emails: [fleeman]
            )
        )
        let sync = MockGoogleSync(result: DeskSnapshot(emails: newer))
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: cache,
            sync: sync
        )
        await model.syncDesk()
        XCTAssertEqual(model.deskSnapshot.emails.count, 26)
        XCTAssertTrue(model.deskSnapshot.emails.contains { $0.providerID == fleeman.providerID })
        XCTAssertEqual(model.deskSnapshot.glanceEmails.count, 5)
        XCTAssertFalse(model.deskSnapshot.glanceEmails.contains { $0.providerID == fleeman.providerID })
        XCTAssertEqual(cache.load().emails.count, 26)
    }

    func testPersonEmailAskDoesNotInboxSync() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-no-inbox-sync"
        murray.body = "Walk the lot Saturday at 10."
        let snapshot = DeskSnapshot(emails: [murray])
        let sync = MockGoogleSync(result: snapshot)
        sync.bodies["msg-murray-no-inbox-sync"] = murray.body
        let voice = MockVoiceService(label: "test", instant: true)
        let model = AppModel(
            voice: voice,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: sync
        )
        await model.applyUserTurn("summarize the Murray email")
        XCTAssertEqual(sync.syncCalls, 0, "person-specific desk turns must not pull the whole inbox")
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""))
        XCTAssertTrue(voice.spoken.contains { $0.contains("Walk the lot") })
    }

    func testInboxOverviewOfflineSkipsSyncAndShowsCache() async {
        var stale = SampleData.syncedEmail()
        stale.fromName = "Old Sender"
        stale.subject = "Day-one snapshot"
        stale.providerID = "msg-overview-offline"
        let cache = MemoryDeskCache(
            snapshot: DeskSnapshot(
                accountEmail: "ada@example.com",
                lastSyncedAt: Date(timeIntervalSince1970: 100),
                emails: [stale]
            )
        )
        let sync = MockGoogleSync(result: DeskSnapshot(emails: [SampleData.syncedEmail()]))
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: cache,
            sync: sync,
            isOnline: false
        )
        await model.applyUserTurn("what's in my inbox?")
        XCTAssertEqual(sync.syncCalls, 0)
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""),
            "offline glance is still cards-only: \(model.turns.last?.text ?? "")"
        )
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.subject, "Day-one snapshot")
        } else {
            XCTFail("offline inbox-overview must still attach cached cards")
        }
    }

    func testSearchEricThenLatestEmailsShowsInboxNotSearchHits() async {
        var laren = SampleData.syncedEmail()
        laren.fromName = "Laren Cole"
        laren.fromEmail = "laren@example.com"
        laren.subject = "Today's walkthrough"
        laren.providerID = "msg-laren-inbox"
        laren.body = "Signed this morning."
        laren.sentAtLabel = "Today 9:14 AM"

        func eric(_ n: Int, subject: String) -> EmailItem {
            var item = SampleData.syncedEmail()
            item.fromName = "Eric Gross"
            item.fromEmail = "eric.gross@example.com"
            item.subject = subject
            item.providerID = "msg-eric-\(n)"
            item.body = "Eric thread \(n)."
            item.sentAtLabel = "Mar 2"
            return item
        }
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.fromEmail = "murray@example.com"
        murray.subject = "Old closing"
        murray.providerID = "msg-murray-old"
        murray.body = "From last month."

        let inbox = DeskSnapshot(
            accountEmail: "ada@example.com",
            lastSyncedAt: Date(timeIntervalSince1970: 100),
            emails: [laren],
            events: [
                CalendarItem(
                    title: "Massimo showing",
                    whenLabel: "Today 3:00 PM",
                    relatedPeople: ["Massimo Ricci"]
                )
            ],
            tasks: [TaskItem(title: "Call the title company")]
        )
        let sync = MockGoogleSync(result: inbox)
        sync.searchable = [eric(1, subject: "Lot walk"), eric(2, subject: "Offer"), eric(3, subject: "Follow-up"), murray]
        let cache = MemoryDeskCache(snapshot: inbox)
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: cache,
            sync: sync
        )
        let desk = DeskContext(isConnected: true, snapshot: inbox)

        await model.applyUserTurn("Can you find the last email by Eric?")
        XCTAssertEqual(sync.syncCalls, 0, "person search must not replace inbox via sync")
        let searchCards = model.turns.last?.cards.compactMap { card -> EmailItem? in
            if case .email(let item) = card { return item }
            return nil
        } ?? []
        // Same-sender hits collapse to the newest card. One Eric card vs three
        // search rows is the product outcome — assert identity, not hit count.
        XCTAssertFalse(searchCards.isEmpty, "Eric search must attach a desk card")
        XCTAssertEqual(Set(searchCards.map(\.fromName)), ["Eric Gross"])
        XCTAssertFalse(searchCards.contains { $0.fromName == "Laren Cole" })
        XCTAssertFalse(searchCards.contains { $0.fromName == "Murray Mitchell" })
        XCTAssertEqual(model.deskSnapshot.emails.map(\.fromName), ["Laren Cole"])
        XCTAssertEqual(model.deskSnapshot.events.first?.title, "Massimo showing")
        XCTAssertEqual(model.deskSnapshot.tasks.first?.title, "Call the title company")
        XCTAssertEqual(cache.load().emails.map(\.fromName), ["Laren Cole"])

        let latestFamily = [
            "Show me my latest emails.",
            "see my latest emails",
            "Just show me my latest emails.",
            "latest emails",
            "Can you pull my latest emails?"
        ]
        for ask in latestFamily {
            XCTAssertTrue(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertFalse(ConversationPresence.isClarifyPick(ask), ask)
            XCTAssertEqual(
                VoiceTurnReplay.play(
                    utterance: ask,
                    context: desk,
                    focusedEmail: VoiceRegressionDesk.ericGross,
                    pendingSearchClarify: true,
                    clarifyMatches: sync.searchable.filter { $0.fromName == "Eric Gross" }
                ).intent,
                "inbox-overview",
                ask
            )
        }

        await model.applyUserTurn("Show me my latest emails.")
        XCTAssertEqual(
            sync.syncCalls,
            0,
            "inbox already has latest-5 — glance must not list-refresh after a search"
        )
        XCTAssertEqual(model.deskSnapshot.emails.map(\.fromName), ["Laren Cole"])
        XCTAssertEqual(cache.load().emails.map(\.fromName), ["Laren Cole"])
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""))
        XCTAssertFalse(InboxGlance.repeatsGlanceLines(model.turns.last?.text ?? ""))
        XCTAssertFalse((model.turns.last?.text ?? "").contains("Eric Gross"))
        XCTAssertFalse((model.turns.last?.text ?? "").contains("Murray Mitchell"))
        let overviewNames = model.turns.last?.cards.compactMap { card -> String? in
            if case .email(let item) = card { return item.fromName }
            return nil
        } ?? []
        XCTAssertEqual(overviewNames, ["Laren Cole"])
    }

    func testInboxOverviewThenMurraySummaryIsMurrayNotGreenacre() async {
        var greenacre = SampleData.syncedEmail()
        greenacre.fromName = "Greenacre Properties, Inc."
        greenacre.fromEmail = "board@greenacre.example.com"
        greenacre.subject = "Board meeting notice"
        greenacre.providerID = "msg-greenacre-top"
        greenacre.body = "The quarterly board meeting is Thursday at 2pm."
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.fromEmail = "murray@example.com"
        murray.subject = "Closing / notarization"
        murray.providerID = "msg-murray-after-inbox"
        murray.body = "Need you to notarize the closing package today."
        var laren = SampleData.syncedEmail()
        laren.fromName = "Laren Cole"
        laren.fromEmail = "laren@example.com"
        laren.subject = "Walk-through window"
        laren.providerID = "msg-laren-after-inbox"
        laren.body = "Can we do the walk-through Thursday at 11?"
        let snapshot = DeskSnapshot(emails: [greenacre, murray, laren])
        let sync = MockGoogleSync(result: snapshot)
        sync.bodies[greenacre.providerID!] = greenacre.body
        sync.bodies[murray.providerID!] = murray.body
        sync.bodies[laren.providerID!] = laren.body
        let voice = MockVoiceService(label: "test", instant: true)
        let model = AppModel(
            voice: voice,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: sync
        )

        await model.applyUserTurn("Just show me my latest emails.")
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""))
        XCTAssertFalse(InboxGlance.repeatsGlanceLines(model.turns.last?.text ?? ""))
        let overviewNames = model.turns.last?.cards.compactMap { card -> String? in
            if case .email(let item) = card { return item.fromName }
            return nil
        } ?? []
        XCTAssertEqual(overviewNames.first, "Greenacre Properties, Inc.")

        await model.applyUserTurn("Give me a summary of Murray's last email.")
        XCTAssertEqual(sync.searchQueries.filter { $0.contains("murray") }.count, 0, "Murray was in cache")
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""))
        XCTAssertTrue(voice.spoken.contains { $0.contains("Murray Mitchell") || $0.contains("notarize") })
        XCTAssertFalse(voice.spoken.contains { $0.contains("Greenacre") && !$0.contains("Murray") })
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected Murray card after inbox overview")
        }

        await model.applyUserTurn("Give me a summary of Lauren's latest, latest email.")
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""))
        XCTAssertFalse((model.turns.last?.text ?? "").contains("Greenacre"))
        XCTAssertTrue(voice.spoken.contains { $0.contains("Laren") || $0.contains("walk-through") || $0.contains("Thursday") })
        if case .email(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.fromName, "Laren Cole")
        } else {
            XCTFail("expected Laren card after Lauren ask")
        }
    }

    func testNamedMurrayMissDoesNotAttachGreenacre() async {
        var greenacre = SampleData.syncedEmail()
        greenacre.fromName = "Greenacre Properties, Inc."
        greenacre.fromEmail = "board@greenacre.example.com"
        greenacre.subject = "Board meeting notice"
        greenacre.providerID = "msg-greenacre-only"
        greenacre.body = "The quarterly board meeting is Thursday at 2pm."
        let snapshot = DeskSnapshot(emails: [greenacre])
        let sync = MockGoogleSync(result: snapshot)
        sync.searchable = []
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: sync
        )
        await model.applyUserTurn("Give me a summary of Murray's last email.")
        XCTAssertFalse(sync.searchQueries.isEmpty)
        XCTAssertTrue(sync.searchQueries.contains { $0.contains("from:murray") })
        XCTAssertEqual(model.turns.last?.text, ConversationPresence.gmailSearchEmptyReply)
        XCTAssertTrue(model.turns.last?.cards.isEmpty == true)
        XCTAssertFalse((model.turns.last?.text ?? "").contains("Greenacre"))
    }

    func testLatestOnMyCalendarShowsUpcomingEventsNotMiss() async {
        let event = CalendarItem(
            title: "Massimo showing",
            whenLabel: "Today 3:00 PM",
            location: "1842 Beach Drive",
            relatedPeople: ["Massimo Ricci"]
        )
        let snapshot = DeskSnapshot(
            accountEmail: "ada@example.com",
            emails: [SampleData.syncedEmail()],
            events: [event]
        )
        let sync = MockGoogleSync(result: snapshot)
        let voice = MockVoiceService(label: "test", instant: true)
        let model = AppModel(
            voice: voice,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: sync
        )
        await model.applyUserTurn("What's the latest on my calendar?")
        XCTAssertEqual(sync.syncCalls, 0, "non-empty calendar uses the synced snapshot")
        XCTAssertNotEqual(model.turns.last?.text, ConversationPresence.calendarMissReply)
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""),
            "cards are the list; bubble must not reprint Eve: \(model.turns.last?.text ?? "")"
        )
        XCTAssertFalse((model.turns.last?.text ?? "").contains("Massimo showing"))
        XCTAssertTrue(voice.spoken.contains { InboxGlance.isShortSpokenSummary($0) }, "\(voice.spoken)")
        XCTAssertFalse(voice.spoken.contains { InboxGlance.isShortSpokenAck($0) }, "\(voice.spoken)")
        XCTAssertEqual(model.turns.last?.cards.count, 1)
        if case .calendar(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.title, "Massimo showing")
        } else {
            XCTFail("expected calendar overview card")
        }
    }

    func testLatestOnMyCalendarEmptyEventsSyncsThenShows() async {
        let event = CalendarItem(
            title: "Massimo showing",
            whenLabel: "Today 3:00 PM",
            relatedPeople: ["Massimo Ricci"]
        )
        let stale = DeskSnapshot(
            accountEmail: "ada@example.com",
            emails: [SampleData.syncedEmail()]
        )
        let sync = MockGoogleSync(result: DeskSnapshot(emails: stale.emails, events: [event]))
        let voice = MockVoiceService(label: "test", instant: true)
        let model = AppModel(
            voice: voice,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: stale),
            sync: sync
        )
        XCTAssertTrue(model.deskSnapshot.events.isEmpty)
        await model.applyUserTurn("What's the latest on my calendar?")
        XCTAssertEqual(sync.syncCalls, 1, "empty calendar must sync before speaking")
        XCTAssertNotEqual(model.turns.last?.text, ConversationPresence.calendarMissReply)
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(model.turns.last?.text ?? ""),
            "cards are the list; bubble must not reprint Eve: \(model.turns.last?.text ?? "")"
        )
        XCTAssertFalse((model.turns.last?.text ?? "").contains("Massimo showing"))
        XCTAssertTrue(voice.spoken.contains { InboxGlance.isShortSpokenSummary($0) }, "\(voice.spoken)")
        XCTAssertFalse(voice.spoken.contains { InboxGlance.isShortSpokenAck($0) }, "\(voice.spoken)")
        if case .calendar(let item) = model.turns.last?.cards.first {
            XCTAssertEqual(item.title, "Massimo showing")
        } else {
            XCTFail("expected calendar card after sync")
        }
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
