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
}
