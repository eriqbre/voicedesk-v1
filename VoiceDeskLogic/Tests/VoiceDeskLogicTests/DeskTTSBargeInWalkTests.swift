import XCTest
@testable import VoiceDeskLogic

/// Eriq 2026-08-26 morning walk: cannot talk over on-device TTS.
/// Socket hears him; leftover desk speak must stop on an accepted ask.
/// Synonym families, never one golden phrase.
final class DeskTTSBargeInWalkTests: XCTestCase {
    static let followUpFamily = [
        "Murray",
        "murray",
        "the last one",
        "The last one.",
        "show calendar",
        "show my calendar"
    ]

    static let leftoverFamily = [
        "here",
        "latest",
        "five",
        "5"
    ]

    private var glanceLine: String {
        InboxGlance.spokenOverviewBeat(count: InboxGlance.overviewLimit)
    }

    func testFollowUpWhileGlanceBeatSpeakingIsAcceptedAndCancelsTTS() {
        let desk = VoiceRegressionDesk.greenacreFirst
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(glanceLine), glanceLine)
        XCTAssertFalse(InboxGlance.isMultiline(glanceLine), glanceLine)
        XCTAssertFalse(glanceLine.contains("—"), glanceLine)
        XCTAssertFalse(glanceLine.localizedCaseInsensitiveContains("Murray"), glanceLine)

        for followUp in Self.followUpFamily {
            let walk = DeskSpeakListenResume.whileClientTTSSpeaking(
                ask: "show me my latest emails",
                spokenLine: glanceLine,
                nextAsk: followUp,
                context: desk
            )
            XCTAssertTrue(walk.nextAccepted, followUp)
            XCTAssertTrue(walk.cancelledSpeak, "accepted ask must stop leftover TTS: \(followUp)")
            XCTAssertNotEqual(walk.nextIntent, "dropped", followUp)
            XCTAssertFalse(walk.ttsFinished, followUp)
        }
    }

    func testLeftoverOfGlanceBeatStillDropsAndDoesNotCancel() {
        for leftover in Self.leftoverFamily {
            var gate = EchoTranscriptGate()
            gate.beginSpeaking(glanceLine)
            XCTAssertNil(
                EchoBargeIn.acceptedUserTranscript(leftover, gate: gate, voiceState: .speaking),
                leftover
            )
            XCTAssertFalse(
                EchoBargeIn.shouldCancelSpeak(
                    event: .userTranscript(text: leftover, itemID: nil),
                    gate: gate,
                    voiceState: .speaking
                ),
                leftover
            )
            XCTAssertTrue(gate.isSpeaking, leftover)
        }
    }

    func testLongNamedEmailSpeakCancelsOnCalendarAndKeepsLeftoverDropped() {
        let spoken = "Murray Mitchell wrote about Closing / notarization. Need you to notarize the closing package today."
        let desk = VoiceRegressionDesk.greenacreFirst
        for followUp in ["show calendar", "the last one", "what's on my calendar"] {
            let walk = DeskSpeakListenResume.whileClientTTSSpeaking(
                ask: "summarize Murray's last email",
                spokenLine: spoken,
                nextAsk: followUp,
                context: desk
            )
            XCTAssertTrue(walk.nextAccepted, followUp)
            XCTAssertTrue(walk.cancelledSpeak, followUp)
        }

        var gate = EchoTranscriptGate()
        gate.beginSpeaking(spoken)
        XCTAssertNil(EchoBargeIn.acceptedUserTranscript("murray", gate: gate, voiceState: .speaking))
        XCTAssertFalse(
            EchoBargeIn.shouldCancelSpeak(
                event: .userTranscript(text: "murray", itemID: nil),
                gate: gate,
                voiceState: .speaking
            )
        )
        XCTAssertEqual(
            EchoBargeIn.acceptedUserTranscript("what's on my calendar", gate: gate, voiceState: .speaking),
            "what's on my calendar"
        )
        XCTAssertTrue(
            EchoBargeIn.shouldCancelSpeak(
                event: .userTranscript(text: "what's on my calendar", itemID: nil),
                gate: gate,
                voiceState: .speaking
            )
        )
        gate.cancelSpeaking()
        XCTAssertFalse(gate.isSpeaking)
        XCTAssertNil(EchoBargeIn.acceptedUserTranscript("murray", gate: gate))
    }

    func testVersionLineRealAskCancelsLeftoverSpeakEchoDoesNot() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(BuildIdentity.fixture.spokenLine)
        XCTAssertTrue(gate.isProtectedIdentityLine)
        XCTAssertFalse(
            EchoBargeIn.shouldCancelSpeak(event: .speechStarted, gate: gate, voiceState: .speaking)
        )
        XCTAssertNil(EchoBargeIn.acceptedUserTranscript("voice", gate: gate, voiceState: .speaking))
        XCTAssertFalse(
            EchoBargeIn.shouldCancelSpeak(
                event: .userTranscript(text: "voice", itemID: nil),
                gate: gate,
                voiceState: .speaking
            )
        )
        XCTAssertEqual(
            EchoBargeIn.acceptedUserTranscript("show calendar", gate: gate, voiceState: .speaking),
            "show calendar"
        )
        XCTAssertTrue(
            EchoBargeIn.shouldCancelSpeak(
                event: .userTranscript(text: "show calendar", itemID: nil),
                gate: gate,
                voiceState: .speaking
            )
        )
    }

    func testGrokVoiceServiceStopsClientTTSAtAcceptedIngress() throws {
        let source = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        XCTAssertTrue(source.contains("EchoBargeIn.acceptedUserTranscript"), source)
        XCTAssertTrue(source.contains("echoGate.cancelSpeaking()"), source)
        XCTAssertTrue(source.contains("ClientVoiceSpeech.shared.stop()"), source)
        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        XCTAssertTrue(app.contains("echoGate.cancelSpeaking()"), app)
        XCTAssertTrue(app.contains("EchoBargeIn.acceptedUserTranscript(event.text, gate: echoGate)"), app)
    }

    private func repoFile(_ relative: String) -> String? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try? String(contentsOf: candidate, encoding: .utf8)
            }
        }
        return nil
    }
}
