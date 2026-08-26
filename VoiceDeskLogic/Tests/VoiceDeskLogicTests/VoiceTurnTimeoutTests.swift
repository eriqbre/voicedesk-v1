import XCTest
@testable import VoiceDeskLogic

final class VoiceTurnTimeoutTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000)

    func testIdleSessionNeverStalls() {
        var timeout = VoiceTurnTimeout()
        timeout.stateChanged(to: .listening, at: start)
        XCTAssertFalse(timeout.hasStalled(now: start.addingTimeInterval(600)))
    }

    func testThinkingWithinBudgetIsFine() {
        var timeout = VoiceTurnTimeout()
        timeout.stateChanged(to: .thinking, at: start)
        XCTAssertFalse(timeout.hasStalled(now: start.addingTimeInterval(3.9)))
    }

    /// Grok is told to stay silent on desk turns, so no response ever arrives
    /// and the session used to park in `.thinking` for good.
    func testSilentTurnStallsAfterTheBudget() {
        var timeout = VoiceTurnTimeout()
        timeout.stateChanged(to: .thinking, at: start)
        XCTAssertTrue(timeout.hasStalled(now: start.addingTimeInterval(4.1)))
    }

    func testSpeakingClearsTheDeadline() {
        var timeout = VoiceTurnTimeout()
        timeout.stateChanged(to: .thinking, at: start)
        timeout.stateChanged(to: .speaking, at: start.addingTimeInterval(1))
        XCTAssertNil(timeout.thinkingSince)
        XCTAssertFalse(timeout.hasStalled(now: start.addingTimeInterval(60)))
    }

    func testRepeatedThinkingUpdatesDoNotPushTheDeadlineOut() {
        var timeout = VoiceTurnTimeout()
        timeout.stateChanged(to: .thinking, at: start)
        timeout.stateChanged(to: .thinking, at: start.addingTimeInterval(3))
        timeout.stateChanged(to: .thinking, at: start.addingTimeInterval(3.5))
        XCTAssertEqual(timeout.thinkingSince, start)
        XCTAssertTrue(timeout.hasStalled(now: start.addingTimeInterval(4.1)))
    }

    func testReturningToListeningResetsAndCanStallAgain() {
        var timeout = VoiceTurnTimeout()
        timeout.stateChanged(to: .thinking, at: start)
        timeout.stateChanged(to: .listening, at: start.addingTimeInterval(5))
        XCTAssertFalse(timeout.hasStalled(now: start.addingTimeInterval(20)))
        timeout.stateChanged(to: .thinking, at: start.addingTimeInterval(30))
        XCTAssertFalse(timeout.hasStalled(now: start.addingTimeInterval(33)))
        XCTAssertTrue(timeout.hasStalled(now: start.addingTimeInterval(35)))
    }
}
