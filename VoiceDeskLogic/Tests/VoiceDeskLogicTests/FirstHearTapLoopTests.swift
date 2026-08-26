import XCTest
@testable import VoiceDeskLogic

/// Tap-rate-during-playback is not first-hear. The third command PCM
/// after desk TTS drain must be a listen-path turn, or the walk is deaf.
final class FirstHearTapLoopTests: XCTestCase {
    func testProductThirdPCMAfterDrainIsATurnWithoutSecondStart() {
        let first = FirstHearTapLoop.commandPCM(1)
        let second = FirstHearTapLoop.commandPCM(2)
        let third = FirstHearTapLoop.commandPCM(3)
        let walk = FirstHearTapLoop.twoTurnsDeskTTSDrainThenThird(
            first: first,
            second: second,
            third: third
        )
        XCTAssertEqual(walk.turns, [first, second, third])
        XCTAssertTrue(walk.tapLive)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.stayLive)
        XCTAssertNotEqual(walk.close1000, .stayIdle)
        XCTAssertEqual(walk.startCount, 1)
    }

    func testSpeakStartedDuringTTSThenDeafDropsTheThird() {
        let walk = FirstHearTapLoop.speakStartedDuringTTSDropsThird()
        XCTAssertEqual(walk.turns.count, 2, "first two land; after TTS the path is deaf")
        XCTAssertFalse(walk.listenArmed)
        XCTAssertEqual(walk.startCount, 1)
        XCTAssertNil(
            FirstHearTapLoop.accept(
                pcm: FirstHearTapLoop.commandPCM(3),
                tapLive: true,
                session: VoiceSession(state: .speaking),
                stayLive: true,
                startCount: 1
            ),
            "tap may still fire while session is speaking — that is not a turn"
        )
    }

    func testIdleClosedAfterTTSDropsTheThird() {
        let walk = FirstHearTapLoop.idleClosedAfterTTSDropsThird()
        XCTAssertEqual(walk.turns.count, 2, "keep-listen log is not hear proof")
        XCTAssertFalse(walk.stayLive)
        XCTAssertEqual(walk.close1000, .stayIdle)
        XCTAssertFalse(walk.listenArmed)
        XCTAssertEqual(walk.startCount, 1)
    }

    func testRearmAfterTTSWithoutSecondStartDropsTheThird() {
        let walk = FirstHearTapLoop.rearmAfterTTSDropsThird()
        XCTAssertEqual(walk.turns.count, 2)
        XCTAssertFalse(walk.tapLive)
        XCTAssertEqual(walk.startCount, 1, "second start was not taken; third must not land")
    }

    func testSilentTapWhileEngineRunningIsTheLie() {
        XCTAssertTrue(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: false, engineRunning: true)
        )
        XCTAssertFalse(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: true, engineRunning: true)
        )
        XCTAssertFalse(
            FirstHearTapLoop.silentTapWhileEngineRunning(tapEmitting: false, engineRunning: false)
        )
    }

    func testAcceptRequiresListenArmedStayLiveAndOneStart() {
        var session = VoiceSession()
        session.apply(.tapTalk)
        let pcm = FirstHearTapLoop.commandPCM(9)
        XCTAssertEqual(
            FirstHearTapLoop.accept(
                pcm: pcm,
                tapLive: true,
                session: session,
                stayLive: true,
                startCount: 1
            ),
            pcm
        )
        XCTAssertNil(
            FirstHearTapLoop.accept(
                pcm: pcm,
                tapLive: true,
                session: session,
                stayLive: true,
                startCount: 2
            )
        )
        XCTAssertNil(
            FirstHearTapLoop.accept(
                pcm: pcm,
                tapLive: false,
                session: session,
                stayLive: true,
                startCount: 1
            )
        )
        XCTAssertNil(
            FirstHearTapLoop.accept(
                pcm: pcm,
                tapLive: true,
                session: session,
                stayLive: false,
                startCount: 1
            )
        )
    }
}
