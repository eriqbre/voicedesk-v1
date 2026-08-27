import XCTest
@testable import VoiceDeskLogic

/// fe1ffc8 walk: version + today’s emails landed on resumeCapture; the
/// next first-ask lived in a 43s hole (no leftover-echo, no hold). One
/// inject during/after client TTS must land without a second shot.
final class FirstHearListenLoopTests: XCTestCase {
    static let firstFamily = [
        "what version are we on",
        "what build is this"
    ]

    static let secondFamily = [
        "show me my emails",
        "today's emails",
        "see my latest emails"
    ]

    static let duringFamily = [
        "Murray",
        "show calendar",
        "what's on my calendar"
    ]

    func testTwoTurnsThenOneInjectDuringClientTTSLands() {
        let spoken = InboxGlance.spokenListAck()
        XCTAssertEqual(spoken, "Here they are.")
        for first in Self.firstFamily {
            for second in Self.secondFamily {
                for during in Self.duringFamily {
                    let walk = FirstHearListenLoop.twoTurnsThenOneDuringClientTTS(
                        first: first,
                        second: second,
                        spokenAfterSecond: spoken,
                        duringTTS: during
                    )
                    XCTAssertEqual(walk.landed, [first, second, during], "\(first) / \(second) / \(during)")
                    XCTAssertTrue(walk.tapLive, during)
                    XCTAssertTrue(walk.listenArmed, during)
                    XCTAssertTrue(walk.stayLive, "session must stay live after client TTS: \(during)")
                    XCTAssertNotEqual(walk.close1000, .stayIdle, during)
                    XCTAssertEqual(walk.startCount, 1, "no second audio.start: \(during)")
                }
            }
        }
    }

    func testFe1ffc8RearmPathIsGoneFromClientTTS() {
        XCTAssertEqual(
            ListenResumePolicy.afterDeskSpeak(
                userWantsVoiceOff: false,
                socketConnected: true
            ),
            .keepListening
        )
    }

    func testFa72e1cSpeakStartedWithoutKeepListenDropsTheNextAsk() {
        let dead = FirstHearListenLoop.fa72e1cSpeakStartedWithoutKeepListen()
        XCTAssertFalse(dead.listenArmed, "fa72e1c left VoiceSession speaking")
        XCTAssertTrue(dead.landed.isEmpty, "next ask must not land until keep-listen")
        XCTAssertEqual(dead.startCount, 1)

        let live = FirstHearListenLoop.twoTurnsThenOneDuringClientTTS(
            first: "what version are we on",
            second: "show me my emails",
            spokenAfterSecond: InboxGlance.spokenListAck(),
            duringTTS: "Tell me Murray's latest email."
        )
        XCTAssertEqual(live.landed.last, "Tell me Murray's latest email.")
        XCTAssertTrue(live.listenArmed)
        XCTAssertTrue(live.stayLive)
        XCTAssertNotEqual(live.close1000, .stayIdle)
        XCTAssertEqual(live.startCount, 1)
    }
}
