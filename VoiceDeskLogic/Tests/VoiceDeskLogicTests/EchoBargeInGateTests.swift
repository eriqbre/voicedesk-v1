import XCTest
@testable import VoiceDeskLogic

final class EchoBargeInGateTests: XCTestCase {
    func testDropsUserInputWhileAssistantSpeakingAndDuringCooldown() {
        var gate = EchoBargeInGate()
        let t0 = Date(timeIntervalSince1970: 5_000)
        XCTAssertTrue(gate.shouldAcceptUserInput(at: t0))

        gate.assistantStarted(at: t0)
        XCTAssertFalse(gate.shouldAcceptUserInput(at: t0))
        XCTAssertFalse(gate.shouldSendMicAudio(at: t0.addingTimeInterval(0.05)))

        gate.assistantFinished(at: t0.addingTimeInterval(1), cooldown: 0.3)
        XCTAssertFalse(gate.shouldAcceptUserInput(at: t0.addingTimeInterval(1.1)))
        XCTAssertTrue(gate.shouldAcceptUserInput(at: t0.addingTimeInterval(1.4)))
    }

    func testResetReArmsImmediately() {
        var gate = EchoBargeInGate()
        gate.assistantStarted()
        gate.reset()
        XCTAssertTrue(gate.shouldAcceptUserInput())
    }

    func testAbortDoesNotCooldownNextWeatherAsk() {
        var gate = EchoBargeInGate()
        let t0 = Date(timeIntervalSince1970: 8_000)
        gate.assistantStarted(at: t0)
        gate.assistantAborted()
        XCTAssertTrue(gate.shouldAcceptUserInput(at: t0))
        XCTAssertFalse(gate.assistantSpeaking)
        XCTAssertNil(gate.cooldownUntil)
    }
}
