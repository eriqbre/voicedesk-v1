import XCTest
@testable import VoiceDeskLogic

/// Policy helpers + leftover gates that are still honest.
/// The 12:14 device miss is gated in VoiceDeskTests
/// `GrokVoiceServiceSpeakTests` (loopback wire), not a CreateTrace factory.
final class LiveToolMouthTests: XCTestCase {
    func testShouldSendResponseCreateOnlyAfterToolsLand() {
        XCTAssertFalse(
            LiveToolMouth.shouldSendResponseCreate(
                toolWait: false,
                alreadyCreated: false,
                hasToolResult: false
            ),
            "fd4a772 create-without-words: bare create after wait"
        )
        XCTAssertTrue(
            LiveToolMouth.shouldSendResponseCreate(
                toolWait: false,
                alreadyCreated: false,
                hasToolResult: true
            )
        )
        XCTAssertFalse(
            LiveToolMouth.shouldSendResponseCreate(
                toolWait: true,
                alreadyCreated: false,
                hasToolResult: true
            )
        )
        XCTAssertFalse(
            LiveToolMouth.shouldSendResponseCreate(
                toolWait: false,
                alreadyCreated: true,
                hasToolResult: true
            ),
            "our response.create already fired — do not stack a second"
        )
        XCTAssertTrue(
            LiveToolMouth.shouldSendResponseCreate(
                toolWait: false,
                alreadyCreated: false,
                hasToolResult: true
            ),
            "leftover inbound create is not alreadyCreated — done mouth after tools"
        )
        XCTAssertFalse(
            LiveToolMouth.shouldParkLiveDeskCards(hasToolResult: false),
            "59 parked cards at handleLiveUser start, before any tool report"
        )
        XCTAssertTrue(LiveToolMouth.shouldParkLiveDeskCards(hasToolResult: true))
        let leftover = EmailItem.listCards([
            EmailItem(
                fromName: "Authentisign",
                fromEmail: "notify@authentisign.example",
                sentAtLabel: "Yesterday 4:10 PM",
                subject: "Signature required 1650",
                preview: "Please review and sign",
                filterTag: "Inbox"
            )
        ])
        let events: [ContentCard] = [
            .calendar(CalendarItem(title: "20th anniversary", whenLabel: "Tomorrow 5:30 PM"))
        ]
        XCTAssertTrue(
            LiveToolMouth.isStickyPriorDeskCards(visible: leftover, current: events),
            "bdbace4 14B69B95: calendar spoken, Authentisign email cards still up"
        )
        XCTAssertFalse(LiveToolMouth.isStickyPriorDeskCards(visible: events, current: events))
        XCTAssertTrue(
            LiveToolMouth.isStickyPriorDeskCards(visible: leftover, current: []),
            "empty calendar done must still replace leftover email cards"
        )
    }

    func testListenResumeStaysCreateResponseTrue() throws {
        let resume = GrokRealtime.listenResumeSessionUpdateObject()
        let data = try JSONSerialization.data(withJSONObject: resume)
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(GrokRealtime.createResponse(inSessionUpdate: raw), true)
        let wait = GrokRealtime.toolWaitSessionUpdateObject()
        let waitData = try JSONSerialization.data(withJSONObject: wait)
        let waitRaw = try XCTUnwrap(String(data: waitData, encoding: .utf8))
        XCTAssertEqual(GrokRealtime.createResponse(inSessionUpdate: waitRaw), false)
    }

    func testNeedsClientToolsOnLiveMailNotVersion() {
        let snapshot = DeskSnapshot(
            accountEmail: "agent@example.com",
            emails: [VoiceRegressionDesk.murray]
        )
        XCTAssertTrue(
            LiveToolMouth.needsClientTools(
                ask: "Can you read my latest email?",
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            )
        )
        XCTAssertFalse(
            LiveToolMouth.needsClientTools(
                ask: "what's my version",
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            )
        )
        XCTAssertFalse(
            LiveToolMouth.needsClientTools(
                ask: "Can you read my latest email?",
                snapshot: snapshot,
                isConnected: false,
                isOnline: true
            )
        )
        XCTAssertTrue(
            LiveToolMouth.needsClientTools(
                ask: "what's on my calendar",
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            )
        )
    }

    func testHonestGatesStillFailVoiceCutSilenceTwoMouth() {
        XCTAssertTrue(LiveVADPlayerKeep.c1cd758Regression().voiceCutsAfterFirstDelta)
        XCTAssertFalse(LiveVADPlayerKeep.c1cd758Regression().remainingDeltasReachPlayer)
        let up = LiveEveSpeak.plan(text: "1.2.3", socketConnected: true)
        XCTAssertEqual(up.mouth, .eve)
        XCTAssertFalse(up.swallowed)
        XCTAssertFalse(up.wroteClientTTS)
        XCTAssertTrue(A2727B1Walk.versionIsDualMouth())
    }

    func testCardPayloadIsTheCardRowsNotSpokenInboxDump() {
        let cards = EmailItem.listCards([
            VoiceRegressionDesk.murray,
            VoiceRegressionDesk.steve
        ])
        let payload = LiveToolMouth.cardPayload(cards)
        let dump = InboxGlance.spokenInbox(
            ask: "Show me my latest emails.",
            emails: [VoiceRegressionDesk.murray, VoiceRegressionDesk.steve]
        )
        XCTAssertFalse(payload.isEmpty)
        XCTAssertNotEqual(payload, dump)
        XCTAssertFalse(InboxGlance.isFromSubjectGlanceDump(payload), payload)
        XCTAssertTrue(payload.contains(VoiceRegressionDesk.murray.fromName), payload)
        XCTAssertTrue(payload.contains(VoiceRegressionDesk.murray.subject), payload)
        XCTAssertFalse(payload.contains(", and more"), payload)
    }

    func testToolStartAndDoneItemsAreOnTheWire() throws {
        let start = GrokRealtime.functionCallItemObject(
            name: LiveToolMouth.deskGlanceToolName,
            callID: "call-1"
        )
        let startData = try JSONSerialization.data(withJSONObject: start)
        let startRaw = try XCTUnwrap(String(data: startData, encoding: .utf8))
        XCTAssertEqual(GrokRealtime.conversationItemType(inCreate: startRaw), "function_call")

        let cards = EmailItem.listCards([VoiceRegressionDesk.murray])
        let done = GrokRealtime.functionCallOutputItemObject(
            callID: "call-1",
            output: LiveToolMouth.cardPayload(cards)
        )
        let doneData = try JSONSerialization.data(withJSONObject: done)
        let doneRaw = try XCTUnwrap(String(data: doneData, encoding: .utf8))
        XCTAssertEqual(GrokRealtime.conversationItemType(inCreate: doneRaw), "function_call_output")
        let output = try XCTUnwrap(GrokRealtime.functionCallOutput(inCreate: doneRaw))
        XCTAssertFalse(InboxGlance.isFromSubjectGlanceDump(output), output)
        XCTAssertTrue(output.contains(VoiceRegressionDesk.murray.fromName), output)
    }

    /// 65C7B25F / AEEAB5CC 1:41:53 walk: “latest emails” painted 5 cards
    /// and logged empty assistantReply. Live path (handleLiveUser →
    /// needsClientTools → beginToolWaitCreate → applyDeskEvidence) must
    /// command deskGlance. Cards do not land on the user bubble or an
    /// empty mouth. Appointments-tonight still has no table — do not
    /// invent one.
    func testLiveLatestEmailsCommandsGlanceToolAndDoesNotPaintEmptyMouth() throws {
        let inbox = [
            VoiceRegressionDesk.murray,
            VoiceRegressionDesk.steve,
            VoiceRegressionDesk.greenacre,
            VoiceRegressionDesk.laren,
            VoiceRegressionDesk.ericGross
        ]
        XCTAssertEqual(inbox.count, 5)
        let snapshot = DeskSnapshot(emails: inbox)
        let context = DeskContext(isConnected: true, snapshot: snapshot)
        let ask = "latest emails"

        XCTAssertTrue(
            ConversationPresence.wantsInboxOverview(ask),
            "existing glance/list family — not a new synonym table"
        )
        XCTAssertTrue(
            ConversationPresence.ownsConnectedDeskTurn(ask),
            "65C7B25F: desk must own so the existing tool can run"
        )
        XCTAssertTrue(
            LiveToolMouth.needsClientTools(
                ask: ask,
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            ),
            "AEEAB5CC 1:41:53 tape had zero function_call"
        )

        let evidence = ConversationPresence.deskEvidence(for: ask, context: context)
        XCTAssertEqual(evidence?.shouldGlanceInbox, true)
        XCTAssertEqual(evidence?.cards.filter { $0.kind == .email }.count, 5)
        let onScreen = InboxGlance.onScreenText(for: evidence!)
        XCTAssertTrue(
            onScreen.isEmpty,
            "cd4a8b1 logged this empty onScreenText as assistantReply"
        )
        XCTAssertFalse(
            LiveToolMouth.shouldAttachCardsOntoTurn(
                role: .assistant,
                text: onScreen,
                hasToolResult: true
            ),
            "65C7B25F empty mouth + 5 cards"
        )
        XCTAssertFalse(
            LiveToolMouth.shouldAttachCardsOntoTurn(
                role: .user,
                text: ask,
                hasToolResult: true
            ),
            "finishLiveTool painted the user bubble before Eve’s mouth"
        )
        XCTAssertFalse(
            LiveToolMouth.shouldAttachCardsOntoTurn(
                role: .assistant,
                text: "Murray on the walk-through, and more.",
                hasToolResult: false
            ),
            "cards without function_call_output"
        )
        XCTAssertTrue(
            LiveToolMouth.shouldAttachCardsOntoTurn(
                role: .assistant,
                text: "Murray on the walk-through, and more.",
                hasToolResult: true
            ),
            "cards and Eve’s mouth together after function_call_output"
        )
        XCTAssertFalse(
            LiveToolMouth.shouldParkLiveDeskCards(hasToolResult: false),
            "59 parked cards at handleLiveUser start, before any tool report"
        )

        let start = GrokRealtime.functionCallItemObject(
            name: LiveToolMouth.deskGlanceToolName,
            callID: "call-latest"
        )
        let startData = try JSONSerialization.data(withJSONObject: start)
        let startRaw = try XCTUnwrap(String(data: startData, encoding: .utf8))
        XCTAssertEqual(GrokRealtime.conversationItemType(inCreate: startRaw), "function_call")

        let tonight = "Do I have any appointments tonight?"
        XCTAssertFalse(
            ConversationPresence.wantsCalendarAsk(tonight),
            "no appointments∩tonight table — leftover-exhausted on that half"
        )
        XCTAssertFalse(
            LiveToolMouth.needsClientTools(
                ask: tonight,
                snapshot: DeskSnapshot(
                    emails: inbox,
                    events: [
                        CalendarItem(title: "Massimo showing", whenLabel: "Tonight 5:30 PM")
                    ]
                ),
                isConnected: true,
                isOnline: true
            )
        )
    }

    /// 9cf53c4 9B23C3AA leftover inbound `response.created`, then newest
    /// emails. finishLiveTool wrote empty onScreenText + 5 cards.
    /// Leftover inbound is not alreadyCreated. Not a planted empty turn.
    func testLiveNewestEmailsDoesNotAttachCardsOntoEmptyVADMouth() {
        let inbox = [
            VoiceRegressionDesk.murray,
            VoiceRegressionDesk.steve,
            VoiceRegressionDesk.greenacre,
            VoiceRegressionDesk.laren,
            VoiceRegressionDesk.ericGross
        ]
        XCTAssertEqual(inbox.count, 5)
        XCTAssertTrue(
            InboxGlance.onScreenText(compactCardCount: 5).isEmpty,
            "9cf53c4 wrote this empty string + 5 cards as the leftover mouth"
        )
        XCTAssertTrue(
            ConversationPresence.ownsConnectedDeskTurn("What are my newest emails?"),
            "newest emails is a desk ask — tools must run"
        )
        XCTAssertTrue(
            LiveToolMouth.needsClientTools(
                ask: "What are my newest emails?",
                snapshot: DeskSnapshot(emails: inbox),
                isConnected: true,
                isOnline: true
            )
        )
        XCTAssertTrue(
            LiveToolMouth.shouldSendResponseCreate(
                toolWait: false,
                alreadyCreated: false,
                hasToolResult: true
            ),
            "leftover VAD inbound create is not the done mouth"
        )
        XCTAssertFalse(
            LiveToolMouth.shouldSendResponseCreate(
                toolWait: false,
                alreadyCreated: false,
                hasToolResult: false
            ),
            "fd4a772 create-without-words"
        )
    }

    /// 9cf53c4 9B23C3AA 9:01:56 leftover VAD spoke Costco — no tool.
    /// Sender is already on the from-phrase. Not a Costco synonym table.
    func testLiveCostcoDoesNotSpeakFromPresenceWithoutToolReport() {
        let costco = EmailItem(
            providerID: "fixture-costco",
            fromName: "Costco",
            fromEmail: "receipts@costco.example",
            sentAtLabel: "Yesterday 6:12 PM",
            subject: "Your Costco.com order",
            preview: "Thanks for your order",
            filterTag: "Inbox"
        )
        let snapshot = DeskSnapshot(emails: [VoiceRegressionDesk.murray, costco])
        let ask = "Read me the one from Costco."
        XCTAssertTrue(
            GmailSearchQuery.hasSenderPattern(ask),
            "existing from-phrase, not a leftover synonym"
        )
        XCTAssertTrue(
            ConversationPresence.ownsConnectedDeskTurn(ask),
            "9cf53c4 required an email word — leftover VAD spoke Costco"
        )
        XCTAssertTrue(
            LiveToolMouth.needsClientTools(
                ask: ask,
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            )
        )
        XCTAssertFalse(
            ConversationPresence.ownsConnectedDeskTurn("What year did John Wick get released")
        )
        XCTAssertFalse(
            LiveToolMouth.needsClientTools(
                ask: "Yes, please.",
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            ),
            "yes without leftover person is not a tool turn"
        )
        XCTAssertTrue(
            ConversationPresence.ownsConnectedDeskTurn("Yes, please.", hasFocusedEmail: true)
        )
        XCTAssertTrue(
            LiveToolMouth.needsClientTools(
                ask: "Yes, please.",
                snapshot: snapshot,
                isConnected: true,
                isOnline: true,
                hasFocusedEmail: true
            ),
            "c42cadc leftover: yes after Murray hit had no function_call"
        )
        let text = GrokRealtime.presenceInstructions(
            for: DeskContext(isConnected: true, snapshot: snapshot)
        )
        XCTAssertFalse(text.contains("you speak the answer"), text)
        XCTAssertFalse(text.contains("answer from the facts"), text)
        XCTAssertFalse(
            LiveToolMouth.shouldSendResponseCreate(
                toolWait: true,
                alreadyCreated: false,
                hasToolResult: false
            ),
            "no create without a tool report"
        )
    }

    /// 9cf53c4 leftover VAD spoke Massimo — no tool. Walk phrase does
    /// not enter tool-wait. Presence used to list “Massimo showing —
    /// Tonight 5:30 PM”. Delete that injection. No appointments∩tonight
    /// table. No whenLabel. Named Massimo still owns.
    func testLiveAppointmentsTonightDoesNotSpeakFromPresenceWithoutToolReport() {
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
        let walkAsk = "Do I have any appointments tonight?"
        XCTAssertFalse(
            ConversationPresence.wantsCalendarAsk(walkAsk),
            "not an appointments∩tonight table"
        )
        XCTAssertNil(
            ConversationPresence.matchingCalendar(for: walkAsk, in: snapshot.events),
            "title/people have no appointments; whenLabel leftover does not earn keep"
        )
        XCTAssertFalse(
            ConversationPresence.ownsConnectedDeskTurn(walkAsk, events: snapshot.events),
            "do not invent a command — walk phrase is not matchingCalendar"
        )
        XCTAssertFalse(
            LiveToolMouth.needsClientTools(
                ask: walkAsk,
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            )
        )
        let named = "Do I have the Massimo showing?"
        XCTAssertFalse(
            ConversationPresence.wantsCalendarAsk(named),
            "no calendar word — named event is matchingCalendar"
        )
        XCTAssertTrue(
            ConversationPresence.ownsConnectedDeskTurn(named, events: snapshot.events)
        )
        XCTAssertFalse(
            ConversationPresence.wantsCalendarAsk("What's for dinner tonight?"),
            "tonight alone is not calendar"
        )
        XCTAssertNil(
            ConversationPresence.matchingCalendar(
                for: "What's for dinner tonight?",
                in: snapshot.events
            )
        )
        XCTAssertFalse(
            ConversationPresence.ownsConnectedDeskTurn(
                "What's for dinner tonight?",
                events: snapshot.events
            )
        )
        XCTAssertFalse(
            ConversationPresence.ownsConnectedDeskTurn(
                "What year did John Wick get released",
                events: snapshot.events
            )
        )
        let text = GrokRealtime.presenceInstructions(
            for: DeskContext(isConnected: true, snapshot: snapshot)
        )
        XCTAssertFalse(
            text.contains("Massimo showing"),
            "9cf53c4 stuffed the calendar line onto the session: \(text)"
        )
        XCTAssertFalse(text.contains("Tonight 5:30 PM"), text)
        XCTAssertFalse(text.contains("you speak the answer"), text)
        XCTAssertFalse(text.contains("answer from the facts"), text)
        XCTAssertFalse(
            LiveToolMouth.shouldSendResponseCreate(
                toolWait: true,
                alreadyCreated: false,
                hasToolResult: false
            ),
            "no create without a tool report"
        )
    }

    func testPresenceStillTeachesWaitNotPlaceholder() {
        let text = GrokRealtime.presenceInstructions(
            for: DeskContext(isConnected: true, snapshot: DeskSnapshot(
                accountEmail: "agent@example.com",
                emails: [VoiceRegressionDesk.murray]
            )),
            identity: .fixture
        )
        XCTAssertFalse(
            text.contains("wait in this same turn"),
            "AEEAB5CC: wait-and-speak was the park/retry mouth: \(text)"
        )
        XCTAssertFalse(text.contains("you are checking"), text)
        XCTAssertFalse(text.contains("I'm checking"), text)
        XCTAssertFalse(GrokRealtime.teachesLeftoverDeskRouting(text), text)
        XCTAssertFalse(GrokRealtime.teachesNoTools(text), text)
    }

    /// AEEAB5CC c819892 1:40:52: “latest email from Murray” with the
    /// Murray card already on screen and snippet not the full note.
    /// Mouth was park/retry; zero function_call. Same wait-for-full-note
    /// family as c42cadc yes — earlier, card already present.
    /// Live path: needsClientTools + shouldFetchBody. Do not speak
    /// couldn’t-load / I’ll-retry from cache/card/presence.
    func testAEEAB5CCLatestEmailFromMurraySnippetCommandsFetchNotParkRetry() {
        var murray = VoiceRegressionDesk.murray
        murray.body = nil
        murray.subject = "Update"
        murray.preview = "Snippet only"
        let snapshot = DeskSnapshot(emails: [VoiceRegressionDesk.larenJansen, murray])
        let context = DeskContext(isConnected: true, snapshot: snapshot)
        let ask = "latest email from Murray"

        XCTAssertTrue(
            ConversationPresence.ownsConnectedDeskTurn(ask, hasFocusedEmail: true),
            "AEEAB5CC leftover: desk must own so the existing tool can run"
        )
        XCTAssertTrue(
            LiveToolMouth.needsClientTools(
                ask: ask,
                snapshot: snapshot,
                isConnected: true,
                isOnline: true,
                hasFocusedEmail: true
            ),
            "AEEAB5CC leftover: card present, zero function_call"
        )

        let evidence = ConversationPresence.deskEvidence(
            for: ask,
            context: context,
            focusedEmail: murray
        )
        XCTAssertEqual(evidence?.shouldFetchBody, true, "must command the existing fetch/summarize")
        XCTAssertEqual(evidence?.focusedEmail?.fromName, "Murray Mitchell")
        XCTAssertEqual(evidence?.cards.filter { $0.kind == .email }.count, 1)
        if case .email(let item) = evidence?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
            XCTAssertEqual(item.subject, "Update")
        } else {
            XCTFail("Murray card must stay")
        }

        let text = evidence?.text ?? ""
        XCTAssertFalse(
            text.localizedCaseInsensitiveContains("couldn’t load")
                || text.localizedCaseInsensitiveContains("couldn't load"),
            "c819892 park mouth from snippet card: \(text)"
        )
        XCTAssertFalse(
            text.localizedCaseInsensitiveContains("i’ll retry")
                || text.localizedCaseInsensitiveContains("i'll retry"),
            "c819892 park mouth from snippet card: \(text)"
        )
        XCTAssertFalse(
            text.localizedCaseInsensitiveContains("full note"),
            "c42cadc wait-for-full-note family: \(text)"
        )
        XCTAssertFalse(
            text.localizedCaseInsensitiveContains("comes through"),
            text
        )

        let presence = GrokRealtime.presenceInstructions(for: context)
        XCTAssertFalse(
            presence.contains("wait in this same turn"),
            "c819892 taught Eve to park/speak before fetch"
        )
    }
}
