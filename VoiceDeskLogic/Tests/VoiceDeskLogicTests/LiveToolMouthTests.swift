import XCTest
@testable import VoiceDeskLogic

/// 12:14 leftover: listen-resume `create_response: true` lets VAD create
/// before tools, then another create after tools. Runtime walk of
/// production session.update / VAD-create / response.create — not a
/// baked leftover1214() phrase factory.
final class LiveToolMouthTests: XCTestCase {
    func testSha83a5c6aNoonCreateBeforeAndAfterToolsFails() {
        let leftover = LiveToolMouth.sha83a5c6aNoonCreateTrace()
        XCTAssertEqual(leftover.createResponseOnListen, true)
        XCTAssertTrue(
            GrokRealtime.vadCreatesOnSpeechStopped(createResponse: leftover.createResponseOnListen)
        )
        XCTAssertGreaterThanOrEqual(leftover.createsBeforeTools, 1)
        XCTAssertGreaterThanOrEqual(leftover.createsAfterTools, 1)
        XCTAssertTrue(
            leftover.isNoon1214Leftover,
            "83a5c6a / 7ef2f6d noon: VAD mouth before tools, then another after"
        )
        XCTAssertFalse(leftover.isOneMouthAfterTools)
    }

    func testProductToolWaitIsOneCreateAfterTools() {
        let product = LiveToolMouth.productToolWaitCreateTrace()
        XCTAssertEqual(product.createResponseOnListen, GrokRealtime.createResponseWhileToolsRun)
        XCTAssertEqual(product.createResponseOnListen, false)
        XCTAssertFalse(
            GrokRealtime.vadCreatesOnSpeechStopped(createResponse: product.createResponseOnListen)
        )
        XCTAssertEqual(product.createsBeforeTools, 0)
        XCTAssertEqual(product.createsAfterTools, 1)
        XCTAssertFalse(product.isNoon1214Leftover)
        XCTAssertTrue(product.isOneMouthAfterTools)
        XCTAssertTrue(
            LiveToolMouth.shouldSendResponseCreate(toolWait: false, alreadyCreated: false)
        )
        XCTAssertFalse(
            LiveToolMouth.shouldSendResponseCreate(toolWait: true, alreadyCreated: false)
        )
        XCTAssertFalse(
            LiveToolMouth.shouldSendResponseCreate(toolWait: false, alreadyCreated: true)
        )
    }

    func testListenResumeStaysCreateResponseTrue() throws {
        let resume = GrokRealtime.listenResumeSessionUpdateObject()
        let data = try JSONSerialization.data(withJSONObject: resume)
        let raw = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(GrokRealtime.createResponse(inSessionUpdate: raw), true)
        let wait = GrokRealtime.toolWaitSessionUpdateObject()
        let waitData = try JSONSerialization.data(withJSONObject: wait)
        let waitRaw = try XCTUnwrap(String(data: waitData, encoding: .utf8))
        XCTAssertEqual(GrokRealtime.createResponse(inSessionUpdate: waitRaw), false)
    }

    func testNeedsClientToolsOnLiveMailNotVersion() {
        let snapshot = DeskSnapshot(
            accountEmail: "agent@example.com",
            emails: [VoiceRegressionDesk.murray]
        )
        XCTAssertTrue(
            LiveToolMouth.needsClientTools(
                ask: "Can you read my latest email?",
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            )
        )
        XCTAssertFalse(
            LiveToolMouth.needsClientTools(
                ask: "what's my version",
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
            )
        )
        XCTAssertFalse(
            LiveToolMouth.needsClientTools(
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
        XCTAssertTrue(A2727B1Walk.versionIsDualMouth())
    }

    func testPresenceStillTeachesWaitNotPlaceholder() {
        let text = GrokRealtime.presenceInstructions(
            for: DeskContext(isConnected: true, snapshot: DeskSnapshot(
                accountEmail: "agent@example.com",
                emails: [VoiceRegressionDesk.murray]
            )),
            identity: .fixture
        )
        XCTAssertTrue(text.contains("wait in this same turn"), text)
        XCTAssertTrue(text.contains("in your own words"), text)
        XCTAssertFalse(text.contains("you are checking"), text)
        XCTAssertFalse(text.contains("I'm checking"), text)
        XCTAssertFalse(GrokRealtime.teachesLeftoverDeskRouting(text), text)
        XCTAssertFalse(GrokRealtime.teachesNoTools(text), text)
    }
}
