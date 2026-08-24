import XCTest
@testable import VoiceDeskLogic

final class StatusEllipsisTests: XCTestCase {
    func testDotsCycleOneTwoThree() {
        XCTAssertEqual(StatusEllipsis.dots(tick: 0), ".")
        XCTAssertEqual(StatusEllipsis.dots(tick: 1), "..")
        XCTAssertEqual(StatusEllipsis.dots(tick: 2), "...")
        XCTAssertEqual(StatusEllipsis.dots(tick: 3), ".")
        XCTAssertEqual(StatusEllipsis.dots(tick: 4), "..")
        XCTAssertEqual(StatusEllipsis.interval, 0.45, accuracy: 0.001)
    }

    func testSearchingGmailDisplayKeepsStem() {
        XCTAssertEqual(
            StatusEllipsis.display(stem: ConversationPresence.gmailSearchingStem, tick: 0),
            "Searching Gmail."
        )
        XCTAssertEqual(
            StatusEllipsis.display(stem: ConversationPresence.gmailSearchingStem, tick: 2),
            "Searching Gmail..."
        )
        XCTAssertEqual(
            StatusEllipsis.display(stem: ConversationPresence.thinkingStatusStem, tick: 1),
            "Thinking.."
        )
        XCTAssertTrue(ConversationPresence.isGmailSearchingBeat(ConversationPresence.gmailSearchingBeat))
        XCTAssertEqual(ConversationPresence.gmailSearchingBeat, "Searching Gmail…")
        XCTAssertTrue(ConversationPresence.isThinkingBeat(ConversationPresence.thinkingStatusBeat))
        XCTAssertTrue(ConversationPresence.isStatusBeat(ConversationPresence.thinkingStatusBeat))
        XCTAssertNil(DeskReplySpeech.textToSpeak(ConversationPresence.thinkingStatusBeat, lastSpoken: nil))
        XCTAssertEqual(
            StatusEllipsis.display(stem: LaunchSyncStatus.syncingStem, tick: 2),
            "Syncing inbox..."
        )
    }
}
