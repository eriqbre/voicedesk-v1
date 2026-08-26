import XCTest
@testable import VoiceDeskLogic

/// Each compact-tape line is one inject after client TTS. Mic stays live.
/// Not VoiceTape catalog, not VoiceTapeGate 168-accept, not emit-twice.
final class EriqSpokenTapeTests: XCTestCase {
    func testEachWalkLineLandsOnceAfterClientTTS() {
        let spoken = InboxGlance.spokenListAck()
        XCTAssertEqual(spoken, "Here they are.")
        XCTAssertEqual(VoiceTape.catalog.count, 8, "do not expand VoiceTape.catalog")
        XCTAssertEqual(EriqSpokenTape.spoken.count, 16)
        XCTAssertEqual(EriqSpokenTape.intended.count, 8)
        XCTAssertEqual(EriqSpokenTape.lines.count, 24)
        for line in EriqSpokenTape.lines {
            let walk = FirstHearListenLoop.twoTurnsThenOneDuringClientTTS(
                first: "what version are we on",
                second: "show me my emails",
                spokenAfterSecond: spoken,
                duringTTS: line
            )
            XCTAssertEqual(walk.landed.last, line, line)
            XCTAssertEqual(walk.landed.filter { $0 == line }.count, 1, line)
            XCTAssertTrue(walk.tapLive, line)
            XCTAssertTrue(walk.listenArmed, line)
            XCTAssertTrue(walk.stayLive, line)
            XCTAssertNotEqual(walk.close1000, .stayIdle, line)
            XCTAssertEqual(walk.startCount, 1, line)
            XCTAssertFalse(
                VoiceTape.catalog.contains {
                    $0.say.compare(line, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                },
                "first-hear tape, not VoiceTape intent catalog: \(line)"
            )
        }
    }
}
