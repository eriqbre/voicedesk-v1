import XCTest
@testable import VoiceDeskLogic

final class VoiceStopIntentTests: XCTestCase {
    func testBareStopCommandsStopVoice() {
        for utterance in [
            "Stop", "stop.", "Stop it", "Stop that", "stop listening",
            "Stop talking, please", "Eve, stop", "Okay stop", "hey eve stop it",
            "Cancel", "cancel that", "Abort", "Quit", "Nevermind", "never mind",
            "Shut up", "Be quiet", "Forget it", "That's enough", "Mute yourself"
        ] {
            XCTAssertTrue(VoiceStopIntent.matches(utterance), "should stop: \(utterance)")
        }
    }

    /// The regression that made the app go deaf mid-conversation: any sentence
    /// containing "stop" or "cancel" used to tear the session down.
    func testSentencesContainingStopWordsKeepTheSessionAlive() {
        for utterance in [
            "I need to stop by the office at five",
            "Can you cancel the Saturday showing?",
            "Never mind the inbox, what's on my calendar?",
            "The buyer wants a non-stop flight out of Tampa",
            "Draft a note saying we should stop pushing the price down",
            "What's the cancellation policy on that listing?",
            "Tell Jordan the showing was cancelled",
            "Stop by 1842 Beach Drive on your way",
            "Abort mission is a movie quote, not a command to you",
            "Is it quiet enough over there for a call?"
        ] {
            XCTAssertFalse(VoiceStopIntent.matches(utterance), "should not stop: \(utterance)")
        }
    }

    func testEmptyAndFillerOnlyUtterancesDoNotStop() {
        for utterance in ["", "   ", "hey", "okay", "um, uh", "..."] {
            XCTAssertFalse(VoiceStopIntent.matches(utterance))
        }
    }

    func testCommandTokensStripFramingFillerButKeepTheVerb() {
        XCTAssertEqual(VoiceStopIntent.commandTokens("Hey Eve, stop please"), ["stop"])
        XCTAssertEqual(VoiceStopIntent.commandTokens("That's enough"), ["thats", "enough"])
        XCTAssertEqual(VoiceStopIntent.commandTokens("stop"), ["stop"])
    }

    func testLongUtterancesAreNeverBareCommands() {
        XCTAssertFalse(
            VoiceStopIntent.matches("stop it it it it it"),
            "beyond the command-length budget the user is talking, not commanding"
        )
    }
}
