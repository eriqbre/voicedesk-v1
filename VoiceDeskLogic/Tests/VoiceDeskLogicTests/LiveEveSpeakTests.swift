import XCTest
@testable import VoiceDeskLogic

/// Leftover-phrase gate (Linux). A spoken leftover reply must fail.
/// Presence must not teach stay silent / let the app handle.
/// `speak("1.2.3")` wire proof is iOS `GrokVoiceServiceSpeakTests`
/// on the loopback `URLSessionWebSocketTask`. This package never
/// runs VoiceDeskTests.
final class LiveEveSpeakTests: XCTestCase {
    func testLeftoverDeskRoutingReplyFailsAndPresenceDoesNotTeachIt() {
        XCTAssertTrue(GrokRealtime.isLeftoverDeskRoutingReply(" The app will take care of it."))
        XCTAssertTrue(GrokRealtime.isLeftoverDeskRoutingReply(" app will take this."))
        XCTAssertTrue(GrokRealtime.isLeftoverDeskRoutingReply("I’ll let the app handle that."))
        XCTAssertFalse(GrokRealtime.isLeftoverDeskRoutingReply("VoiceDesk point 1, build 6."))
        XCTAssertFalse(GrokRealtime.isLeftoverDeskRoutingReply("Murray wrote about the showing."))
        let text = GrokRealtime.presenceInstructions(
            for: DeskContext(isConnected: true, snapshot: .empty)
        )
        XCTAssertFalse(GrokRealtime.teachesLeftoverDeskRouting(text), text)
        XCTAssertFalse(text.contains("stay silent"), text)
        XCTAssertFalse(text.contains("let the app handle"), text)
        XCTAssertFalse(
            GrokRealtime.teachesLeftoverDeskRouting(
                GrokRealtime.verbatimSpeakInstructions(text: "1.2.3")
            )
        )
    }
}
