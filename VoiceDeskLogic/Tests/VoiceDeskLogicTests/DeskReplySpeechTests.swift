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
}
