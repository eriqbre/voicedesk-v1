import XCTest
@testable import VoiceDeskLogic

final class DeskReplySpeechTests: XCTestCase {
    func testSkipsSearchingBeatAndDuplicates() {
        XCTAssertNil(
            DeskReplySpeech.textToSpeak(ConversationPresence.gmailSearchingBeat, lastSpoken: nil)
        )
        XCTAssertNil(DeskReplySpeech.textToSpeak("   ", lastSpoken: nil))

        let summary = "Murray wrote: Need you to notarize today."
        XCTAssertEqual(DeskReplySpeech.textToSpeak(summary, lastSpoken: nil), summary)
        XCTAssertNil(DeskReplySpeech.textToSpeak(summary, lastSpoken: summary))
        XCTAssertEqual(
            DeskReplySpeech.textToSpeak(ConversationPresence.gmailSearchEmptyReply, lastSpoken: summary),
            ConversationPresence.gmailSearchEmptyReply
        )
        XCTAssertEqual(
            DeskReplySpeech.textToSpeak(ConversationPresence.emailNeedMoreReply, lastSpoken: nil),
            ConversationPresence.emailNeedMoreReply
        )
    }

    func testInboxOverviewAndDeskPersonRepliesAreSpoken() {
        let digest = ConversationPresence.inboxOverviewCopy([
            VoiceRegressionDesk.murray,
            VoiceRegressionDesk.steve
        ])
        XCTAssertTrue(digest.isEmpty, digest)
        XCTAssertNotEqual(digest, "Here they are.")
        XCTAssertNil(DeskReplySpeech.textToSpeak(digest, lastSpoken: nil))
        let madison = ConversationPresence.emailBodyReply(
            EmailItem(
                fromName: "John Madison",
                fromEmail: "john@example.com",
                sentAtLabel: "Today",
                subject: "Beach Drive",
                preview: "Can we talk numbers",
                body: "Can we talk numbers on Beach Drive.",
                filterTag: "Inbox"
            )
        )
        XCTAssertEqual(DeskReplySpeech.textToSpeak(madison, lastSpoken: digest), madison)
        XCTAssertNil(DeskReplySpeech.textToSpeak(digest, lastSpoken: nil))
        XCTAssertFalse(ConversationPresence.isGrokDeskMeta(digest))
        XCTAssertFalse(ConversationPresence.isGrokDeskMeta(madison))
    }
}
