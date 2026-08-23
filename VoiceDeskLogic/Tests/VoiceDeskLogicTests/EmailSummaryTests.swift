import XCTest
@testable import VoiceDeskLogic

final class EmailSummaryTests: XCTestCase {
    func testTwoQuestionsAreNamedAndCardChromeIsForbidden() {
        let body = """
        Hey Bridget — two quick questions:

        1. Can you notarize the closing package Thursday?
        2. Is the buyer still set for 3pm on Beach Drive?

        Thanks,
        Murray
        """
        let request = EmailSummaryRequest(
            fromName: "Murray Mitchell",
            subject: "Closing / notarization",
            body: body
        )
        let summary = EmailSummary.heuristic(request)
        XCTAssertTrue(summary.contains("notarize"), summary)
        XCTAssertTrue(summary.localizedCaseInsensitiveContains("Thursday")
                      || summary.contains("notarize the closing package"), summary)
        XCTAssertTrue(summary.localizedCaseInsensitiveContains("Beach Drive")
                      || summary.localizedCaseInsensitiveContains("3pm")
                      || summary.localizedCaseInsensitiveContains("buyer"), summary)
        XCTAssertFalse(EmailSummary.containsUIChrome(summary), summary)
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("on the card"), summary)
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("see the card"), summary)
        XCTAssertEqual(DeskReplySpeech.textToSpeak(summary, lastSpoken: nil), summary)
    }

    func testScrubRemovesCardChrome() {
        let dirty = "Latest from Murray is on the card. Need you to notarize. You can see it below."
        let clean = EmailSummary.scrubUIChrome(dirty)
        XCTAssertFalse(EmailSummary.containsUIChrome(clean), clean)
        XCTAssertTrue(clean.contains("Need you to notarize"), clean)
        let spoken = DeskReplySpeech.textToSpeak(dirty, lastSpoken: nil)
        XCTAssertFalse(EmailSummary.containsUIChrome(spoken ?? ""), spoken ?? "")
    }

    func testConnectInstructionIsNotScrubbedForSpeak() {
        XCTAssertEqual(
            DeskReplySpeech.textToSpeak(ConversationPresence.connectHowToReply, lastSpoken: nil),
            ConversationPresence.connectHowToReply
        )
    }

    func testChatCompletionParserScrubsChrome() {
        let json: [String: Any] = [
            "choices": [
                ["message": ["content": "Murray asked two things. I’ve put it on a card."]]
            ]
        ]
        let content = EmailSummary.chatCompletionContent(from: json)
        XCTAssertEqual(content, "Murray asked two things.")
    }

    func testMissingBodyDoesNotInvent() {
        let summary = EmailSummary.heuristic(
            EmailSummaryRequest(fromName: "Murray Mitchell", subject: "", body: "", preview: "")
        )
        XCTAssertTrue(summary.localizedCaseInsensitiveContains("don’t have")
                      || summary.localizedCaseInsensitiveContains("not inventing")
                      || summary.localizedCaseInsensitiveContains("don’t have enough"), summary)
        XCTAssertFalse(summary.localizedCaseInsensitiveContains("notarize"), summary)
    }
}

final class ConversationScrollPolicyTests: XCTestCase {
    func testUserThenAssistantPinsEveTextNotLastCard() {
        let user = UUID()
        let eve = UUID()
        let afterUser = ConversationScrollPolicy.afterUser(turnID: user)
        XCTAssertEqual(afterUser.targetID, user)
        XCTAssertEqual(afterUser.reason, .userUtterance)
        XCTAssertEqual(afterUser.anchor, .top)

        let reply = ConversationScrollPolicy.afterAssistant(turnID: eve, hasCards: false)
        XCTAssertEqual(reply.targetID, eve)
        XCTAssertEqual(reply.reason, .assistantReply)
        XCTAssertEqual(reply.anchor, .top)

        let peek = ConversationScrollPolicy.afterAssistant(turnID: eve, hasCards: true)
        XCTAssertEqual(peek.targetID, eve)
        XCTAssertEqual(peek.reason, .cardsPeek)
        XCTAssertEqual(peek.anchor, .top)
        XCTAssertNil(ConversationScrollPolicy.afterExpand())
    }
}
