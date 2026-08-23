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

    func testUserStopDoesNotReconnectSocketDropWhileArmedDoesOnce() {
        XCTAssertFalse(
            VoiceSocketRecovery.shouldReconnect(
                error: "Grok disconnected",
                alreadyTried: false,
                userWantsVoiceOff: true
            ),
            "user tap-stop / cancel must not auto-reconnect"
        )
        XCTAssertTrue(
            VoiceSocketRecovery.shouldReconnect(
                error: "Socket is not connected",
                alreadyTried: false,
                userWantsVoiceOff: false
            ),
            "unexpected drop while voice is still armed reconnects once"
        )
        XCTAssertFalse(
            VoiceSocketRecovery.shouldReconnect(
                error: "Socket is not connected",
                alreadyTried: true,
                userWantsVoiceOff: false
            )
        )
    }
}
