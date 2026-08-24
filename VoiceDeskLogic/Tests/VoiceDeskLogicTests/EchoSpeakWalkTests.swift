import XCTest
@testable import VoiceDeskLogic

final class EchoSpeakWalkTests: XCTestCase {
    func testVersionAskCompletesSpokenLineWhenEchoArrivesMidSpeak() {
        let walk = EchoSpeakWalk.versionAskThenMidSpeakEcho()

        XCTAssertEqual(walk.spokenLine, "VoiceDesk point 1, build 4.")
        XCTAssertTrue(walk.completedSpokenLine, "Eve must finish the version sentence")
        XCTAssertFalse(walk.cancelledSpeak, "voice / point / build echo must not barge-in")

        for fragment in ["voice", "point", "build", "zero"] {
            XCTAssertTrue(walk.droppedTranscripts.contains(fragment), fragment)
            XCTAssertFalse(walk.acceptedTurns.contains(fragment), fragment)
        }

        XCTAssertTrue(walk.acceptedTurns.contains("what's on my calendar"))
        XCTAssertTrue(walk.acceptedTurns.contains("latest email from Lauren"))
        XCTAssertFalse(walk.droppedTranscripts.contains("what's on my calendar"))
        XCTAssertFalse(walk.droppedTranscripts.contains("latest email from Lauren"))
    }

    func testSynonymFamiliesDropAsEchoAndNeverReachGrok() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(BuildIdentity.fixture.spokenLine)
        let synonyms = [
            "voice", "desk", "voicedesk", "voice desk",
            "point", "dot",
            "build", "built",
            "zero", "oh", "0",
            "one", "1",
            "two", "2",
        ]
        for synonym in synonyms {
            XCTAssertEqual(
                gate.decide(synonym, voiceState: .speaking, context: VoiceRegressionDesk.connected).intent,
                "dropped",
                synonym
            )
            XCTAssertNil(
                EchoBargeIn.acceptedUserTranscript(synonym, gate: gate, voiceState: .speaking),
                synonym
            )
            XCTAssertFalse(
                EchoBargeIn.shouldCancelSpeak(
                    event: .userTranscript(text: synonym, itemID: nil),
                    gate: gate,
                    voiceState: .speaking
                ),
                synonym
            )
        }
        gate.finishSpeaking()
        XCTAssertEqual(gate.decide("voice").intent, "dropped")
        XCTAssertEqual(gate.decide("point").intent, "dropped")
        XCTAssertEqual(gate.decide("zero").intent, "dropped")
        XCTAssertEqual(
            gate.decide("what's on my calendar", context: VoiceRegressionDesk.connected).intent,
            "calendar"
        )
    }
}
