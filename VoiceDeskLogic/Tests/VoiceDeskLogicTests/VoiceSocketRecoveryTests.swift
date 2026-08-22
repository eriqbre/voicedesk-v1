import XCTest
@testable import VoiceDeskLogic

final class VoiceSocketRecoveryTests: XCTestCase {
    func testSocketNotConnectedIsADrop() {
        XCTAssertTrue(VoiceSocketRecovery.isSocketDrop("The operation couldn't be completed. Socket is not connected"))
        XCTAssertTrue(VoiceSocketRecovery.isSocketDrop("Grok disconnected"))
        XCTAssertTrue(VoiceSocketRecovery.isSocketDrop("WebSocket timeout"))
        XCTAssertFalse(VoiceSocketRecovery.isSocketDrop("Microphone permission denied"))
    }

    func testReconnectsOnceThenStops() {
        XCTAssertTrue(
            VoiceSocketRecovery.shouldReconnect(
                error: "Socket is not connected",
                alreadyTried: false
            )
        )
        XCTAssertFalse(
            VoiceSocketRecovery.shouldReconnect(
                error: "Socket is not connected",
                alreadyTried: true
            )
        )
        XCTAssertEqual(VoiceSocketRecovery.maxAutomaticReconnects, 1)
    }
}
