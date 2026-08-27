import XCTest
@testable import VoiceDeskLogic

/// Fake-socket suite around `speak("1.2.3")`. Production `LiveEveSpeak.plan`
/// is what GrokVoiceService.speak calls. Would fail 83a5c6a hard-true
/// ClientTTS lie, guard-return silence, and unbound restore.
final class LiveEveSpeakTests: XCTestCase {

    func testSpeak123SocketUpIsThreeJSONAndNoClientTTS() {
        let plan = LiveEveSpeak.plan(
            text: "1.2.3",
            socketConnected: true
        )
        XCTAssertEqual(plan.mouth, .eve)
        XCTAssertEqual(plan.wireTypes, LiveEveSpeak.eveWireTypes)
        XCTAssertEqual(plan.wireTypes, [
            "session.update",
            "conversation.item.create",
            "response.create"
        ])
        XCTAssertFalse(plan.wroteClientTTS)
        XCTAssertFalse(plan.swallowed)
        XCTAssertTrue(
            ListenResumePolicy.deskSpeakUsesGrokVerbatim(socketConnected: true)
        )
        XCTAssertFalse(
            ListenResumePolicy.deskSpeakUsesClientTTS(socketConnected: true)
        )
    }

    func testSpeak123SocketDownWritesClientTTS() {
        let plan = LiveEveSpeak.plan(
            text: "1.2.3",
            socketConnected: false
        )
        XCTAssertEqual(plan.mouth, .clientTTS)
        XCTAssertTrue(plan.wroteClientTTS)
        XCTAssertTrue(plan.wireTypes.isEmpty)
        XCTAssertFalse(plan.swallowed)
        XCTAssertTrue(
            ListenResumePolicy.deskSpeakUsesClientTTS(socketConnected: false)
        )
        XCTAssertFalse(
            ListenResumePolicy.deskSpeakUsesGrokVerbatim(socketConnected: false)
        )
        XCTAssertTrue(
            LiveEveSpeak.swallowedGuardReturn().swallowed,
            "83a5c6a guard-return swallowed the 6m silence class"
        )
        XCTAssertNotEqual(
            LiveEveSpeak.plan(text: "1.2.3", socketConnected: false),
            LiveEveSpeak.swallowedGuardReturn()
        )
    }

    func testForeignResponseDoneDoesNotClearVerbatimMode() {
        XCTAssertEqual(
            LiveEveSpeak.bindVerbatimResponseID(existing: nil, createdID: "verbatim-1"),
            "verbatim-1"
        )
        XCTAssertFalse(
            LiveEveSpeak.shouldRestorePresence(
                doneResponseID: "foreign",
                verbatimResponseID: "verbatim-1"
            ),
            "unbound bool restore on any done is stayIdle-after-version"
        )
        XCTAssertFalse(
            LiveEveSpeak.shouldRestorePresence(
                doneResponseID: "verbatim-1",
                verbatimResponseID: nil
            )
        )
        XCTAssertTrue(
            LiveEveSpeak.shouldRestorePresence(
                doneResponseID: "verbatim-1",
                verbatimResponseID: "verbatim-1"
            )
        )
    }

    func testLeftoverDeskRoutingReplyFailsAndPresenceDoesNotTeachIt() {
        XCTAssertTrue(GrokRealtime.isLeftoverDeskRoutingReply(" The app will take care of it."))
        XCTAssertTrue(GrokRealtime.isLeftoverDeskRoutingReply(" app will take this."))
        XCTAssertTrue(GrokRealtime.isLeftoverDeskRoutingReply("I’ll let the app handle that."))
        XCTAssertFalse(GrokRealtime.isLeftoverDeskRoutingReply("VoiceDesk point 1, build 6."))
        XCTAssertFalse(GrokRealtime.isLeftoverDeskRoutingReply("Murray wrote about the showing."))
        let text = GrokRealtime.presenceInstructions(
            for: DeskContext(isConnected: true, snapshot: .empty)
        )
        XCTAssertFalse(GrokRealtime.teachesLeftoverDeskRouting(text), text)
        XCTAssertFalse(text.contains("stay silent"), text)
        XCTAssertFalse(text.contains("let the app handle"), text)
        XCTAssertFalse(
            GrokRealtime.teachesLeftoverDeskRouting(
                GrokRealtime.verbatimSpeakInstructions(text: "1.2.3")
            )
        )
    }

    func testClassRegressionsStillFail() {
        XCTAssertTrue(LiveVADPlayerKeep.c1cd758Regression().voiceCutsAfterFirstDelta)
        XCTAssertFalse(
            LiveVADPlayerKeep.oneMouthFullReply(cardCount: 5).voiceCutsAfterFirstDelta
        )
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldPlayBargeAudio(
                bargeConsumed: false,
                deltaResponseID: "eve",
                cancelledResponseID: nil,
                createdAwaitingAudioID: nil,
                lastCreatedResponseID: nil,
                playingResponseID: nil,
                lastScheduledResponseID: nil,
                hasPendingPlayback: false
            )
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: "VoiceDesk point 1, build 6.",
                identityLine: "VoiceDesk point 1, build 6."
            )
        )
    }
}
