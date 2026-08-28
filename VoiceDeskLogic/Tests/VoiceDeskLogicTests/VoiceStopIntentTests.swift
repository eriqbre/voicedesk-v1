import XCTest
@testable import VoiceDeskLogic

final class VoiceStopIntentTests: XCTestCase {
    func testBareStopIsACommand() {
        for utterance in ["Stop", "stop.", "Cancel", "cancel that", "Abort", "never mind", "Nevermind"] {
            XCTAssertTrue(VoiceStopIntent.matches(utterance), utterance)
        }
    }

    func testStopInsideASentenceIsNotACommand() {
        for utterance in [
            "I need to stop by the office at five",
            "Can you cancel the Saturday showing?",
            "Never mind the inbox, what's on my calendar?"
        ] {
            XCTAssertFalse(VoiceStopIntent.matches(utterance), utterance)
        }
    }
}
