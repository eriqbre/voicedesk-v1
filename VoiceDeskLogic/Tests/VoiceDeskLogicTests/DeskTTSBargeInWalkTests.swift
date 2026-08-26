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
        "they",
        "here they are"
    ]

    /// First live ask after a list ack — synonym family, never one golden phrase.
    static let firstAskAfterAckFamily = [
        "show calendar",
        "Murray",
        "what's on my calendar"
    ]

    private var glanceLine: String {
        InboxGlance.spokenListAck()
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

    func testFirstAskAfterGlanceAckIsAcceptedAndListenArmed() {
        let desk = VoiceRegressionDesk.greenacreFirst
        XCTAssertEqual(glanceLine, "Here they are.")
        for ask in Self.firstAskAfterAckFamily {
            let walk = DeskSpeakListenResume.afterCompletedDeskSpeak(
                ask: "show me my emails",
                spokenLine: glanceLine,
                nextAsk: ask,
                context: desk
            )
            XCTAssertTrue(walk.ttsFinished, ask)
            XCTAssertTrue(walk.listenArmed, "first ask after desk speak must hear: \(ask)")
            XCTAssertTrue(walk.nextAccepted, ask)
            XCTAssertNotEqual(walk.nextIntent, "dropped", ask)
        }

        var gate = EchoTranscriptGate()
        gate.beginSpeaking(glanceLine)
        gate.finishSpeaking()
        XCTAssertFalse(gate.isSpeaking)
        XCTAssertEqual(gate.lastSpokenLine, glanceLine)
        for leftover in Self.leftoverFamily {
            XCTAssertNil(EchoBargeIn.acceptedUserTranscript(leftover, gate: gate), leftover)
        }
        for ask in Self.firstAskAfterAckFamily {
            XCTAssertEqual(EchoBargeIn.acceptedUserTranscript(ask, gate: gate), ask, ask)
            XCTAssertEqual(EarlyFinalHold().accept(ask, context: desk), ask, ask)
        }
    }

    func testFirstAskAfterSummaryDigestIsAcceptedAndListenArmed() {
        let spoken = InboxGlance.spokenInboxSummary([
            VoiceRegressionDesk.greenacre,
            VoiceRegressionDesk.murray
        ])
        XCTAssertTrue(InboxGlance.isShortSpokenSummary(spoken), spoken)
        let desk = VoiceRegressionDesk.greenacreFirst
        for ask in ["show calendar", "what's on my calendar"] {
            let walk = DeskSpeakListenResume.afterCompletedDeskSpeak(
                ask: "catch me up on email",
                spokenLine: spoken,
                nextAsk: ask,
                context: desk
            )
            XCTAssertTrue(walk.listenArmed, ask)
            XCTAssertTrue(walk.nextAccepted, ask)
            XCTAssertNotEqual(walk.nextIntent, "dropped", ask)
        }
    }

    func testSessionStartFirstAskIsAcceptedWithoutPriorSpeak() {
        var session = VoiceSession()
        session.apply(.tapTalk)
        XCTAssertTrue(ListenResumePolicy.isListenArmed(state: session.state))
        let gate = EchoTranscriptGate()
        XCTAssertTrue(gate.lastSpokenLine.isEmpty)
        XCTAssertFalse(gate.isSpeaking)
        let desk = VoiceRegressionDesk.greenacreFirst
        for ask in Self.firstAskAfterAckFamily {
            XCTAssertEqual(EchoBargeIn.acceptedUserTranscript(ask, gate: gate), ask, ask)
            let decision = gate.decide(ask, voiceState: session.state, context: desk)
            XCTAssertFalse(decision.isDropped, ask)
            XCTAssertNotEqual(decision.intent, "dropped", ask)
            XCTAssertEqual(EarlyFinalHold().accept(ask, context: desk), ask, ask)
            var dedupe = TranscriptDedupe()
            XCTAssertEqual(dedupe.accept(text: ask), ask, ask)
        }
    }

    func testListenRearmsAfterClientTTSEvenIfLastSpokenLineChanged() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(glanceLine)
        gate.beginSpeaking("Murray on closing, and more.")
        XCTAssertNotEqual(gate.lastSpokenLine, glanceLine)
        gate.finishSpeaking()
        var session = VoiceSession()
        session.apply(.tapTalk)
        session.apply(.listenFinished)
        session.apply(.speakStarted)
        ListenResumePolicy.applySessionAfterDeskSpeak(&session)
        XCTAssertTrue(ListenResumePolicy.shouldArmListenAfterClientTTS(ttsFinished: true))
        XCTAssertTrue(ListenResumePolicy.isListenArmed(state: session.state))
        XCTAssertFalse(gate.isSpeaking)
        XCTAssertEqual(gate.lastSpokenLine, "Murray on closing, and more.")
        XCTAssertNil(EchoBargeIn.acceptedUserTranscript("murray", gate: gate))
        XCTAssertEqual(
            EchoBargeIn.acceptedUserTranscript("show calendar", gate: gate),
            "show calendar"
        )
    }

    func testFirstAcceptedLiveTranscriptBecomesATurn() {
        let desk = VoiceRegressionDesk.greenacreFirst
        for ask in Self.firstAskAfterAckFamily {
            var gate = EchoTranscriptGate()
            gate.beginSpeaking(glanceLine)
            gate.finishSpeaking()
            guard let accepted = EchoBargeIn.acceptedUserTranscript(ask, gate: gate) else {
                XCTFail("Grok ingress must accept first ask: \(ask)")
                continue
            }
            var hold = EarlyFinalHold()
            guard let held = hold.accept(accepted, context: desk) else {
                XCTFail("AppModel early-final must not hold first ask: \(ask)")
                continue
            }
            var dedupe = TranscriptDedupe()
            XCTAssertEqual(dedupe.accept(text: held), held, ask)
        }
    }

    func testGrokVoiceServiceStopsClientTTSAtAcceptedIngress() throws {
        let source = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        XCTAssertTrue(source.contains("EchoBargeIn.acceptedUserTranscript"), source)
        XCTAssertTrue(source.contains("echoGate.cancelSpeaking()"), source)
        XCTAssertTrue(source.contains("ClientVoiceSpeech.shared.stop()"), source)
        XCTAssertTrue(source.contains("eventHandler?(.userTranscript(trimmed, isFinal: true, itemID: itemID))"), source)
        XCTAssertFalse(source.contains("if echoGate.lastSpokenLine == trimmed"), source)
        XCTAssertTrue(source.contains("armListenIfSessionLive(reason: \"client tts\")"), source)
        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        XCTAssertTrue(app.contains("echoGate.cancelSpeaking()"), app)
        XCTAssertTrue(app.contains("EchoBargeIn.acceptedUserTranscript(event.text, gate: echoGate)"), app)
        XCTAssertTrue(app.contains("handleLiveUser(accepted, itemID: event.itemID)"), app)
        XCTAssertFalse(app.contains("if echoGate.lastSpokenLine == spoken"), app)
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
