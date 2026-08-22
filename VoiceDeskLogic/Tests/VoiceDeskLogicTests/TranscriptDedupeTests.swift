import XCTest
@testable import VoiceDeskLogic

final class TranscriptDedupeTests: XCTestCase {
    func testSameItemIDIsRejected() {
        var dedupe = TranscriptDedupe()
        let first = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(dedupe.accept(text: "Hello there", itemID: "item_1", at: first), "Hello there")
        XCTAssertNil(dedupe.accept(text: "Hello there", itemID: "item_1", at: first.addingTimeInterval(0.05)))
    }

    func testIdenticalFinalWithinWindowIsRejected() {
        var dedupe = TranscriptDedupe()
        let first = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(dedupe.accept(text: "What’s in my inbox?", itemID: "a", at: first), "What’s in my inbox?")
        XCTAssertNil(
            dedupe.accept(
                text: "What’s in my inbox?",
                itemID: "b",
                at: first.addingTimeInterval(0.4)
            )
        )
    }

    func testCompletedThenItemCreatedSameTurnIsOneAccept() {
        var dedupe = TranscriptDedupe()
        let now = Date(timeIntervalSince1970: 3_000)
        XCTAssertNotNil(
            dedupe.accept(text: "Beach Drive showing", itemID: "item_9", at: now)
        )
        XCTAssertNil(
            dedupe.accept(text: "Beach Drive showing", itemID: "item_9", at: now.addingTimeInterval(0.01))
        )
    }

    func testLaterDifferentUtteranceIsAccepted() {
        var dedupe = TranscriptDedupe()
        let first = Date(timeIntervalSince1970: 4_000)
        XCTAssertNotNil(dedupe.accept(text: "Hello", itemID: "1", at: first))
        XCTAssertEqual(
            dedupe.accept(text: "What’s next?", itemID: "2", at: first.addingTimeInterval(0.3)),
            "What’s next?"
        )
    }

    func testAssistantGatePrefersAudioOverOutputText() {
        var gate = AssistantTranscriptGate()
        XCTAssertTrue(gate.shouldAccept(.audio))
        XCTAssertFalse(gate.shouldAccept(.outputText))
        XCTAssertTrue(gate.shouldAccept(.audio))
        gate.reset()
        XCTAssertTrue(gate.shouldAccept(.outputText))
    }
}
