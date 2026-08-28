import XCTest
@testable import VoiceDeskLogic

/// 12:14 leftover: first VAD mouth I-don’t-know / empty before tools,
/// then the real answer. Runtime walk — not a source scrape.
final class LiveToolMouthTests: XCTestCase {
    func testLeftover1214IsEarlyIDontKnowThenRealAnswer() {
        let leftover = LiveToolMouth.leftover1214()
        XCTAssertTrue(
            leftover.isEarlyIDontKnowThenRealAnswer,
            "83a5c6a / 7ef2f6d noon walk: I-don't-know then the real answer"
        )
        XCTAssertTrue(LiveToolMouth.leftover1214EmptyFirst().isEarlyIDontKnowThenRealAnswer)
        XCTAssertTrue(LiveToolMouth.isIDontKnowOrEmpty("I don't know"))
        XCTAssertTrue(LiveToolMouth.isIDontKnowOrEmpty("I don’t know"))
        XCTAssertTrue(LiveToolMouth.isIDontKnowOrEmpty("   "))
        XCTAssertFalse(LiveToolMouth.isIDontKnowOrEmpty("Murray wrote about the closing package."))
    }

    func testProductWaitThenOneMouthIsNotEarlyIDontKnow() {
        let product = LiveToolMouth.productWaitThenOneMouth(
            answer: "Murray wrote about the closing package."
        )
        XCTAssertFalse(product.isEarlyIDontKnowThenRealAnswer)
        XCTAssertFalse(product.firstMouthBeforeTools)
        XCTAssertTrue(product.laterMouth.isEmpty)
        XCTAssertEqual(product.createdCount, 1)
    }

    func testFirstAudioWaitsForToolsOnLiveMailAsk() {
        XCTAssertFalse(
            LiveToolMouth.shouldPlayFirstAudio(awaitingIntent: true, needsTools: false, toolsLanded: false)
        )
        XCTAssertFalse(
            LiveToolMouth.shouldPlayFirstAudio(needsTools: true, toolsLanded: false)
        )
        XCTAssertTrue(
            LiveToolMouth.shouldPlayFirstAudio(needsTools: true, toolsLanded: true)
        )
        XCTAssertTrue(
            LiveToolMouth.shouldPlayFirstAudio(needsTools: false, toolsLanded: false)
        )
        XCTAssertTrue(
            LiveToolMouth.shouldCreateAfterTools(
                needsTools: true,
                toolsLanded: true,
                playedFirstAudio: false
            )
        )
        XCTAssertFalse(
            LiveToolMouth.shouldCreateAfterTools(
                needsTools: true,
                toolsLanded: true,
                playedFirstAudio: true
            ),
            "already-heard mouth must not get a second create"
        )
    }

    func testHoldFirstAudioUntilToolsOnLiveMailNotVersion() {
        let snapshot = DeskSnapshot(
            accountEmail: "agent@example.com",
            emails: [VoiceRegressionDesk.murray]
        )
        XCTAssertTrue(
            LiveToolMouth.shouldHoldFirstAudioUntilTools(
                ask: "Can you read my latest email?",
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            )
        )
        XCTAssertTrue(
            LiveToolMouth.shouldHoldFirstAudioUntilTools(
                ask: "show me my emails",
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            )
        )
        XCTAssertFalse(
            LiveToolMouth.shouldHoldFirstAudioUntilTools(
                ask: "what's my version",
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            )
        )
        XCTAssertFalse(
            LiveToolMouth.shouldHoldFirstAudioUntilTools(
                ask: "Can you read my latest email?",
                snapshot: snapshot,
                isConnected: false,
                isOnline: true
            )
        )
    }

    func testHonestGatesStillFailVoiceCutSilenceTwoMouth() {
        XCTAssertTrue(LiveVADPlayerKeep.c1cd758Regression().voiceCutsAfterFirstDelta)
        XCTAssertFalse(LiveVADPlayerKeep.c1cd758Regression().remainingDeltasReachPlayer)
        let up = LiveEveSpeak.plan(text: "1.2.3", socketConnected: true)
        XCTAssertEqual(up.mouth, .eve)
        XCTAssertFalse(up.swallowed)
        XCTAssertFalse(up.wroteClientTTS)
        let swallow = LiveEveSpeak.plan(text: "1.2.3", socketConnected: true)
        XCTAssertFalse(
            swallow.swallowed,
            "8927c2d silence: Eve chosen then swallow / no ClientTTS"
        )
        XCTAssertTrue(A2727B1Walk.versionIsDualMouth())
    }

    func testPresenceDoesNotTeachCheckingPlaceholder() {
        let text = GrokRealtime.presenceInstructions(
            for: DeskContext(isConnected: true, snapshot: DeskSnapshot(
                accountEmail: "agent@example.com",
                emails: [VoiceRegressionDesk.murray]
            )),
            identity: .fixture
        )
        XCTAssertFalse(text.contains("you are checking"), text)
        XCTAssertFalse(text.contains("I'm checking"), text)
        XCTAssertFalse(text.contains("I don’t know"), text)
        XCTAssertFalse(text.contains("I don't know"), text)
        XCTAssertTrue(text.contains("wait in this same turn"), text)
        XCTAssertFalse(GrokRealtime.teachesLeftoverDeskRouting(text), text)
        XCTAssertFalse(GrokRealtime.teachesNoTools(text), text)
    }
}
