import XCTest
@testable import VoiceDeskLogic

final class VoiceTurnTimingTests: XCTestCase {
    func testLatencyMsIsFirstAudioMinusUserFinal() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var timing = VoiceTurnTiming()
        timing.markUserFinal(at: start)
        timing.markReplyReady(at: start.addingTimeInterval(0.8))
        timing.markFirstAudio(at: start.addingTimeInterval(30.4))
        timing.markReplyDone(at: start.addingTimeInterval(33))
        timing.addStage("awaitingNonMetaTranscript")
        timing.addStage("awaitingNonMetaTranscript")
        XCTAssertEqual(timing.latencyMs, 30_400)
        XCTAssertEqual(timing.replyReadyMs, 800)
        XCTAssertEqual(timing.stages, ["awaitingNonMetaTranscript"])
    }

    func testMillisecondsNilUntilBothEndsExist() {
        XCTAssertNil(VoiceTurnTiming.milliseconds(from: nil, to: Date()))
        XCTAssertNil(VoiceTurnTiming.milliseconds(from: Date(), to: nil))
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(VoiceTurnTiming.milliseconds(from: start, to: start.addingTimeInterval(-1)), -1000)
    }
}
