import XCTest
@testable import VoiceDeskLogic

final class EchoTranscriptGateTests: XCTestCase {
    private var spokenVersion: String { BuildIdentity.fixture.spokenLine }

    func testDropsAllUserTranscriptsWhileSpeaking() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spokenVersion)
        XCTAssertTrue(gate.isSpeaking)

        for leftover in ["zero", "point one", "what's on my calendar", "latest email from Lauren"] {
            let decision = gate.decide(leftover, context: VoiceRegressionDesk.connected)
            XCTAssertEqual(decision.intent, "dropped", leftover)
            XCTAssertNil(decision.plan, leftover)
            XCTAssertNil(gate.acceptUserTranscript(leftover), leftover)
        }
    }

    func testVoiceStateSpeakingDropsEvenIfFlagCleared() {
        let gate = EchoTranscriptGate()
        XCTAssertFalse(gate.isSpeaking)
        let decision = gate.decide("zero", voiceState: .speaking)
        XCTAssertEqual(decision.intent, "dropped")
        XCTAssertNil(decision.plan)
        XCTAssertNil(gate.acceptUserTranscript("reservation", voiceState: .speaking))
    }

    func testAfterVersionLineEchoFragmentsHaveDroppedIntentAndNoDeskPlan() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spokenVersion)
        gate.finishSpeaking()
        XCTAssertFalse(gate.isSpeaking)

        let echoes = [
            "zero",
            "Zero",
            "oh",
            "point one",
            "point 1",
            "dot one",
            "build 6",
            "build five",
            "build 1",
            "build one",
            "voice desk",
            "VoiceDesk",
            "voicedesk",
            "voice",
        ]
        for echo in echoes {
            let decision = gate.decide(echo, context: VoiceRegressionDesk.connected)
            XCTAssertEqual(decision.intent, "dropped", echo)
            XCTAssertNil(decision.plan, echo)
            XCTAssertTrue(decision.isDropped, echo)
        }
    }

    func testAfterVersionLineRealAsksStayLive() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spokenVersion)
        gate.finishSpeaking()

        let calendar = gate.decide("what's on my calendar", context: VoiceRegressionDesk.connected)
        XCTAssertEqual(calendar.intent, "calendar")
        XCTAssertEqual(calendar.plan?.topic, .calendar)
        XCTAssertNotEqual(calendar.intent, "dropped")
        XCTAssertNotEqual(calendar.intent, "version")

        let lauren = gate.decide(
            "latest email from Lauren",
            context: VoiceRegressionDesk.greenacreFirst
        )
        XCTAssertTrue(["desk-person", "desk-thread"].contains(lauren.intent), lauren.intent)
        XCTAssertNotEqual(lauren.intent, "dropped")
        XCTAssertNotEqual(lauren.plan?.topic, .version)
        XCTAssertTrue(
            ConversationPresence.ownsConnectedDeskTurn("latest email from Lauren"),
            "Lauren ask must stay desk-owned"
        )

        let zeroEmails = gate.decide("zero emails today", context: VoiceRegressionDesk.connected)
        XCTAssertNotEqual(zeroEmails.intent, "dropped")
        XCTAssertNotNil(zeroEmails.acceptedText)

        let murray = gate.decide(
            "build me a summary of Murray",
            context: VoiceRegressionDesk.connected
        )
        XCTAssertNotEqual(murray.intent, "dropped")
        XCTAssertNotNil(murray.acceptedText)
        XCTAssertNotNil(murray.plan)
    }

    func testVersionLineSpeakThenLeftoverThenCalendarAndLaurenFixture() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spokenVersion)
        XCTAssertEqual(gate.decide("zero").intent, "dropped")
        gate.finishSpeaking()

        XCTAssertEqual(gate.decide("zero").intent, "dropped")
        XCTAssertEqual(gate.decide("point one").intent, "dropped")
        XCTAssertEqual(gate.decide("build 6").intent, "dropped")
        XCTAssertNil(gate.decide("zero").plan)

        let calendar = gate.decide("what's on my calendar", context: VoiceRegressionDesk.connected)
        XCTAssertEqual(calendar.intent, "calendar")

        let lauren = gate.decide(
            "latest email from Lauren",
            context: VoiceRegressionDesk.greenacreFirst
        )
        XCTAssertTrue(["desk-person", "desk-thread"].contains(lauren.intent), lauren.intent)
    }

    func testSharedWordAloneIsEchoButLongerAskIsLive() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spokenVersion)
        gate.finishSpeaking()

        XCTAssertTrue(EchoTranscriptGate.isLeftoverEcho("zero", of: spokenVersion))
        XCTAssertTrue(EchoTranscriptGate.isLeftoverEcho("build 6", of: spokenVersion))
        XCTAssertTrue(EchoTranscriptGate.isLeftoverEcho("build 1", of: spokenVersion))
        XCTAssertFalse(EchoTranscriptGate.isLeftoverEcho("zero emails today", of: spokenVersion))
        XCTAssertFalse(EchoTranscriptGate.isLeftoverEcho("build me a summary of Murray", of: spokenVersion))
    }

    func testCancelStopsWhileSpeakingDropButKeepsLeftoverEcho() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spokenVersion)
        gate.cancelSpeaking()
        XCTAssertFalse(gate.shouldIgnoreUserTranscript())
        XCTAssertEqual(gate.decide("what's on my calendar").intent, "calendar")
        XCTAssertEqual(gate.decide("zero").intent, "dropped")
    }

    func testSpokenVersionLineAvoidsForcingZeroIntoTTS() {
        XCTAssertEqual(spokenVersion, "VoiceDesk point 1, build 6.")
        XCTAssertFalse(spokenVersion.contains("0.1"))
        XCTAssertFalse(spokenVersion.lowercased().split { !$0.isLetter && !$0.isNumber }.contains("zero"))
        XCTAssertEqual(BuildIdentity.fixture.spokenSHALine, "VoiceDesk 1fa0a0e.")
    }

    func testSpeechStartedDuringVersionLineDoesNotCancel() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spokenVersion)
        XCTAssertTrue(gate.isProtectedIdentityLine)
        XCTAssertFalse(gate.shouldCancelSpeakOnSpeechStarted())
        XCTAssertFalse(gate.shouldCancelSpeakOnSpeechStarted(voiceState: .speaking))
        XCTAssertFalse(
            EchoBargeIn.shouldCancelSpeak(event: .speechStarted, gate: gate, voiceState: .speaking)
        )
    }

    func testMidSpeakEchoFragmentsDoNotCancelVersionLine() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spokenVersion)
        for fragment in ["voice", "Voice", "point", "build", "zero", "VoiceDesk", "built"] {
            XCTAssertNil(gate.acceptUserTranscript(fragment, voiceState: .speaking), fragment)
            XCTAssertFalse(gate.shouldCancelSpeak(for: fragment, voiceState: .speaking), fragment)
            XCTAssertFalse(
                EchoBargeIn.shouldCancelSpeak(
                    event: .userTranscript(text: fragment, itemID: nil),
                    gate: gate,
                    voiceState: .speaking
                ),
                fragment
            )
        }
        XCTAssertTrue(gate.isSpeaking)
    }

    func testAfterFinishSpeechStartedCanBargeInButLeftoverEchoStillDrops() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spokenVersion)
        gate.finishSpeaking()
        XCTAssertTrue(gate.shouldCancelSpeakOnSpeechStarted())
        XCTAssertFalse(gate.shouldCancelSpeak(for: "voice"))
        XCTAssertNil(gate.acceptUserTranscript("voice"))
        XCTAssertNil(gate.acceptUserTranscript("point"))
        XCTAssertNotNil(gate.acceptUserTranscript("what's on my calendar"))
        XCTAssertFalse(gate.shouldCancelSpeak(for: "what's on my calendar"))
    }

    func testWhileSpeakingDigestRealAskCanBargeInEchoCannot() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking("Murray wrote: Walk the lot Saturday.")
        XCTAssertFalse(gate.isProtectedIdentityLine)
        XCTAssertFalse(gate.shouldCancelSpeakOnSpeechStarted(voiceState: .speaking))
        XCTAssertNil(gate.acceptUserTranscript("murray", voiceState: .speaking))
        XCTAssertFalse(gate.shouldCancelSpeak(for: "murray", voiceState: .speaking))
        XCTAssertEqual(
            gate.acceptUserTranscript("what's on my calendar", voiceState: .speaking),
            "what's on my calendar"
        )
        XCTAssertTrue(gate.shouldCancelSpeak(for: "what's on my calendar", voiceState: .speaking))
        XCTAssertEqual(
            gate.acceptUserTranscript("latest email from Lauren", voiceState: .speaking),
            "latest email from Lauren"
        )
    }

    func testIdentityLineShapesAreProtected() {
        XCTAssertTrue(EchoTranscriptGate.isProtectedIdentityLine(spokenVersion))
        XCTAssertTrue(EchoTranscriptGate.isProtectedIdentityLine(BuildIdentity.fixture.spokenSHALine))
        XCTAssertTrue(EchoTranscriptGate.isProtectedIdentityLine(BuildIdentity.unknown.spokenLine))
        XCTAssertFalse(EchoTranscriptGate.isProtectedIdentityLine("Murray wrote: Walk the lot Saturday."))
        XCTAssertFalse(EchoTranscriptGate.isProtectedIdentityLine(""))
    }
}
