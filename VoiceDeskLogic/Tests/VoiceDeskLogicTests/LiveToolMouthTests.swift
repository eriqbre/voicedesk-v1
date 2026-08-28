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
            )
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

    func testPresenceStillTeachesWaitNotPlaceholder() {
        let text = GrokRealtime.presenceInstructions(
            for: DeskContext(isConnected: true, snapshot: DeskSnapshot(
                accountEmail: "agent@example.com",
                emails: [VoiceRegressionDesk.murray]
            )),
            identity: .fixture
        )
        XCTAssertTrue(text.contains("wait in this same turn"), text)
        XCTAssertTrue(text.contains("in your own words"), text)
        XCTAssertFalse(text.contains("you are checking"), text)
        XCTAssertFalse(text.contains("I'm checking"), text)
        XCTAssertFalse(GrokRealtime.teachesLeftoverDeskRouting(text), text)
        XCTAssertFalse(GrokRealtime.teachesNoTools(text), text)
    }
}
