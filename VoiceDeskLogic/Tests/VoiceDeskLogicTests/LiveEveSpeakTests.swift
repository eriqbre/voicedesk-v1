import XCTest
@testable import VoiceDeskLogic

/// Production `speak()` uses `LiveEveSpeak.plan` + `hasProductionSendTask`.
/// 83a5c6a `ListenResumePolicy.deskSpeakUsesClientTTS()` was hard-true
/// while UP speak used Eve — two contracts. Those wrappers are gone.
final class LiveEveSpeakTests: XCTestCase {
    func testSpeakPlanSocketUpIsEveNot83a5c6aHardTrueClientTTS() {
        let up = LiveEveSpeak.plan(
            text: "1.2.3",
            socketConnected: true,
            liveSessionArmed: true
        )
        XCTAssertEqual(up.mouth, .eve, "83a5c6a deskSpeakUsesClientTTS() was hard-true")
        XCTAssertFalse(up.wroteClientTTS, "83a5c6a leftover wrapper always chose ClientTTS")
        XCTAssertEqual(up.wireTypes, LiveEveSpeak.eveWireTypes)
        XCTAssertFalse(up.swallowed)

        let down = LiveEveSpeak.plan(text: "1.2.3", socketConnected: false)
        XCTAssertEqual(down.mouth, .clientTTS)
        XCTAssertTrue(down.wroteClientTTS)
        XCTAssertTrue(down.wireTypes.isEmpty)

        XCTAssertTrue(LiveVADPlayerKeep.c1cd758Regression().voiceCutsAfterFirstDelta)
        XCTAssertTrue(A2727B1Walk.versionIsDualMouth())
    }
}
