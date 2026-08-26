import XCTest
@testable import VoiceDeskLogic

/// Each live walk line is one inject after client TTS. Mic stays live.
/// Not VoiceTape intent matching. Not emit-twice.
final class EriqSpokenTapeTests: XCTestCase {
    func testEachWalkLineLandsOnceAfterClientTTS() {
        let spoken = InboxGlance.spokenListAck()
        XCTAssertEqual(spoken, "Here they are.")
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
            XCTAssertEqual(walk.leftoverDropped, ["here", "they"], line)
            XCTAssertNotEqual(walk.landed.last, "here", line)
        }
        XCTAssertEqual(EriqSpokenTape.walkLines.count, 12)
        XCTAssertEqual(EriqSpokenTape.coverLines.count, 5)
        XCTAssertEqual(EriqSpokenTape.lines.count, 17)
        for line in EriqSpokenTape.lines {
            XCTAssertFalse(
                VoiceTape.catalog.contains {
                    $0.say.compare(line, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                },
                "first-hear tape, not VoiceTape intent catalog: \(line)"
            )
        }
    }
}
