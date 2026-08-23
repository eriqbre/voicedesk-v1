import XCTest
@testable import VoiceDeskLogic

final class EchoTranscriptGateTests: XCTestCase {
    func testDropsFauxUserTranscriptWhileAssistantSpeaking() {
        var gate = EchoTranscriptGate()
        let t0 = Date(timeIntervalSince1970: 5_000)
        XCTAssertEqual(
            gate.acceptUserTranscript("what's on the calendar this week", at: t0),
            "what's on the calendar this week"
        )

        gate.assistantStarted(at: t0)
        XCTAssertTrue(gate.assistantSpeaking)
        XCTAssertNil(gate.acceptUserTranscript("reservation", at: t0.addingTimeInterval(0.2)))
        XCTAssertNil(gate.acceptUserTranscript("Dinner reservation", voiceState: .listening, at: t0))
        XCTAssertFalse(gate.shouldAcceptSpeechStarted(at: t0))
    }

    func testVoiceStateSpeakingDropsEvenIfFlagCleared() {
        var gate = EchoTranscriptGate()
        let t0 = Date(timeIntervalSince1970: 6_000)
        XCTAssertFalse(gate.assistantSpeaking)
        XCTAssertNil(gate.acceptUserTranscript("reservation", voiceState: .speaking, at: t0))
        XCTAssertFalse(gate.shouldAcceptUserTranscript(voiceState: .speaking, at: t0))
    }

    func testAcceptsAfterFinishPlusCooldown() {
        var gate = EchoTranscriptGate()
        let t0 = Date(timeIntervalSince1970: 7_000)
        gate.assistantStarted(at: t0)
        gate.assistantFinished(at: t0.addingTimeInterval(1), cooldown: 0.3)

        XCTAssertFalse(gate.assistantSpeaking)
        XCTAssertNil(gate.acceptUserTranscript("reservation", at: t0.addingTimeInterval(1.1)))
        XCTAssertFalse(gate.shouldAcceptSpeechStarted(at: t0.addingTimeInterval(1.2)))

        let afterCooldown = t0.addingTimeInterval(1.4)
        XCTAssertEqual(
            gate.acceptUserTranscript("what's the weather", at: afterCooldown),
            "what's the weather"
        )
        XCTAssertTrue(gate.shouldAcceptSpeechStarted(at: afterCooldown))
    }

    func testDefaultCooldownIsBetween200And400ms() {
        XCTAssertGreaterThanOrEqual(EchoTranscriptGate.defaultCooldown, 0.2)
        XCTAssertLessThanOrEqual(EchoTranscriptGate.defaultCooldown, 0.4)
    }

    func testAbortAndResetReArmImmediately() {
        var gate = EchoTranscriptGate()
        gate.assistantStarted()
        gate.assistantAborted()
        XCTAssertTrue(gate.shouldAcceptUserInput())
        XCTAssertEqual(gate.acceptUserTranscript("tampa weather"), "tampa weather")

        gate.assistantStarted()
        gate.assistantFinished(cooldown: 10)
        gate.reset()
        XCTAssertTrue(gate.shouldAcceptUserInput())
    }

    func testReservationEchoWouldRouteAsCalendarIfAccepted() {
        // Documents the dogfood bug: Eve saying “reservation” must be dropped,
        // because that word is a calendar follow-up if treated as the user.
        XCTAssertTrue(ConversationPresence.wantsCalendarDetails("reservation"))
        var gate = EchoTranscriptGate()
        gate.assistantStarted()
        XCTAssertNil(gate.acceptUserTranscript("reservation"))
    }
}
