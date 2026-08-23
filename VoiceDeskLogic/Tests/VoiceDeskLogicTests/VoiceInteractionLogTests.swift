import XCTest
@testable import VoiceDeskLogic

final class VoiceInteractionLogTests: XCTestCase {
    override func setUp() {
        VoiceInteractionLog.resetForTests()
    }

    func testReleasePathNeverPersistsTranscripts() {
        #if DEBUG
        XCTAssertTrue(VoiceInteractionLog.isEnabled)
        let entry = VoiceInteractionEntry(
            source: "text",
            userTranscript: "secret utterance",
            intent: "general",
            routingNotes: [],
            cardsAttached: [],
            assistantReply: "ok",
            voicePath: "AVSpeech"
        )
        VoiceInteractionLog.record(entry)
        XCTAssertEqual(VoiceInteractionLog.snapshot().last?.userTranscript, "secret utterance")
        XCTAssertTrue(VoiceInteractionLog.exportJSON().contains("secret utterance"))
        #else
        XCTAssertFalse(VoiceInteractionLog.isEnabled)
        VoiceInteractionLog.record(
            VoiceInteractionEntry(
                source: "text",
                userTranscript: "secret utterance",
                intent: "general",
                routingNotes: [],
                cardsAttached: [],
                assistantReply: "ok",
                voicePath: "AVSpeech"
            )
        )
        XCTAssertTrue(VoiceInteractionLog.snapshot().isEmpty)
        XCTAssertEqual(VoiceInteractionLog.exportJSON(), "[]")
        #endif
    }

    func testClassifyInboxOverviewClearsStickyVsMurrayPerson() {
        let murray = EmailItem(
            providerID: "log-murray",
            fromName: "Murray Mitchell",
            fromEmail: "murray@example.com",
            sentAtLabel: "Today 9:00 AM",
            subject: "Closing / notarization",
            preview: "Need you to notarize",
            body: "Need you to notarize today.",
            filterTag: "Inbox"
        )
        let steve = EmailItem(
            providerID: "log-steve",
            fromName: "Steve Brown",
            fromEmail: "steve@example.com",
            sentAtLabel: "Today 8:00 AM",
            subject: "Inspection note",
            preview: "Punch list",
            filterTag: "Inbox"
        )
        let context = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [murray, steve])
        )
        let overview = ConversationPresence.deskEvidence(
            for: "summary of my latest emails",
            context: context,
            focusedEmail: murray
        )
        let classified = VoiceInteractionLog.classify(
            utterance: "summary of my latest emails",
            evidence: overview,
            hadFocusedEmail: true
        )
        XCTAssertEqual(classified.intent, "inbox-overview")
        XCTAssertTrue(classified.notes.contains("sticky cleared"))
        XCTAssertNil(overview?.focusedEmail)

        let person = ConversationPresence.deskEvidence(
            for: "summarize the Murray email",
            context: context,
            focusedEmail: steve
        )
        let personClass = VoiceInteractionLog.classify(
            utterance: "summarize the Murray email",
            evidence: person,
            hadFocusedEmail: true
        )
        XCTAssertTrue(["desk-person", "desk-thread"].contains(personClass.intent), personClass.intent)
        XCTAssertNotEqual(personClass.intent, "inbox-overview")
        XCTAssertFalse(personClass.notes.contains("sticky cleared"))
        if case .email(let item) = person?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected Murray person path")
        }
    }
}
