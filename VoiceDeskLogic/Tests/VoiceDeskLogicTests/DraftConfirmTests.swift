import XCTest
@testable import VoiceDeskLogic

final class DraftConfirmTests: XCTestCase {
    func testPendingConfirmBecomesConfirmed() {
        XCTAssertEqual(DraftConfirmMachine.apply(.pending, .confirm), .confirmed)
        XCTAssertTrue(DraftConfirmMachine.mayCallSendClient(after: .confirmed))
    }

    func testEditSaveCancelPaths() {
        XCTAssertEqual(DraftConfirmMachine.apply(.pending, .beginEdit), .editing)
        XCTAssertEqual(DraftConfirmMachine.apply(.editing, .saveBody), .pending)
        XCTAssertEqual(DraftConfirmMachine.apply(.editing, .confirm), .confirmed)
        XCTAssertEqual(DraftConfirmMachine.apply(.pending, .cancel), .cancelled)
        XCTAssertEqual(DraftConfirmMachine.apply(.editing, .cancel), .cancelled)
    }

    func testConfirmedAndCancelledAreTerminal() {
        XCTAssertEqual(DraftConfirmMachine.apply(.confirmed, .cancel), .confirmed)
        XCTAssertEqual(DraftConfirmMachine.apply(.cancelled, .confirm), .cancelled)
        XCTAssertFalse(DraftConfirmMachine.mayCallSendClient(after: .pending))
        XCTAssertFalse(DraftConfirmMachine.mayCallSendClient(after: .editing))
        XCTAssertFalse(DraftConfirmMachine.mayCallSendClient(after: .cancelled))
    }
}
