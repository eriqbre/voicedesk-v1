import XCTest
@testable import VoiceDeskLogic

final class OfflineQueueTests: XCTestCase {
    func testEnqueueAndFlush() {
        var queue = OfflineQueue()
        XCTAssertTrue(queue.isEmpty)

        queue.enqueue(OfflineAction(title: "Send reply", payload: "draft-1"))
        XCTAssertFalse(queue.isEmpty)
        XCTAssertEqual(queue.pending.count, 1)

        let flushed = queue.flushWhenOnline()
        XCTAssertEqual(flushed.count, 1)
        XCTAssertEqual(flushed[0].title, "Send reply")
        XCTAssertTrue(queue.isEmpty)
    }

    func testConfirmedSendQueuesAndNeverMarksDelivered() {
        let client = RecordingSendClient(isOnline: false)
        var draft = SampleData.draftReply()
        draft.status = .confirmed
        XCTAssertEqual(client.send(draft), .queuedNotDelivered)
        XCTAssertEqual(client.queue.pending.count, 1)
        XCTAssertFalse(client.queue.isEmpty)
    }
}
