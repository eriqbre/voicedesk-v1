import XCTest
@testable import VoiceDeskLogic

final class SendClientSecurityTests: XCTestCase {
    func testUnconfirmedDraftDoesNotFireSend() {
        let client = RecordingSendClient()
        let draft = SampleData.draftReply()
        XCTAssertEqual(draft.status, .pending)

        let attempt = client.send(draft)
        XCTAssertEqual(attempt, .blockedUnconfirmed)
        XCTAssertTrue(client.sentDrafts.isEmpty)
        XCTAssertNotEqual(attempt, .delivered)
    }

    func testConfirmRequiredBeforeQueue() {
        let client = RecordingSendClient()
        var draft = SampleData.draftReply()
        draft.status = DraftConfirmMachine.apply(draft.status, .confirm)
        XCTAssertTrue(DraftConfirmMachine.mayCallSendClient(after: draft.status))

        let attempt = client.send(draft)
        XCTAssertEqual(attempt, .queuedNotDelivered)
        XCTAssertEqual(client.sentDrafts.count, 1)
        XCTAssertNotEqual(attempt, .delivered)
    }

    func testDraftOnlyNeverReportsDelivered() {
        let client = RecordingSendClient()
        var draft = SampleData.draftReply()
        _ = client.send(draft)
        draft.status = .confirmed
        let queued = client.send(draft)
        XCTAssertEqual(queued, .queuedNotDelivered)
    }
}
