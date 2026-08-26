import XCTest
@testable import VoiceDeskLogic

/// Eve decides command vs ambient. No leftover-echo word list.
final class ListenInterruptTests: XCTestCase {
    func testDeskAsksAreCommands() {
        let desk = VoiceRegressionDesk.greenacreFirst
        XCTAssertTrue(ListenInterrupt.isCommand("show me my emails"))
        XCTAssertTrue(ListenInterrupt.isCommand("what version are we on"))
        XCTAssertTrue(ListenInterrupt.isCommand("show calendar"))
        XCTAssertTrue(ListenInterrupt.isCommand("what's on my calendar"))
        XCTAssertTrue(ListenInterrupt.isCommand("show me Murray's latest email", context: desk))
        XCTAssertTrue(ListenInterrupt.isCommand("today's emails"))
    }

    func testAmbientAndRadioAreNotCommands() {
        XCTAssertFalse(ListenInterrupt.isCommand(""))
        XCTAssertFalse(ListenInterrupt.isCommand("   "))
        XCTAssertFalse(ListenInterrupt.isCommand("hmm"))
        XCTAssertFalse(ListenInterrupt.isCommand("Can you hear me?"))
        XCTAssertFalse(ListenInterrupt.isCommand("and now the weather"))
        XCTAssertFalse(ListenInterrupt.isCommand("What's for dinner?"))
        XCTAssertFalse(ListenInterrupt.isCommand("Murray"), "bare name is not desk intent")
        XCTAssertFalse(ListenInterrupt.isCommand(ConversationPresence.justTalk))
    }
}
