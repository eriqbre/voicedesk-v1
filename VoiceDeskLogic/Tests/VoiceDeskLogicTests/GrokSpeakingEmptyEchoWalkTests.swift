import XCTest
@testable import VoiceDeskLogic

/// 2150783 Qs 15 Pro Max: latest-emails never reached the desk because
/// Grok `.speaking` + empty lastSpokenLine dropped the transcript.
final class GrokSpeakingEmptyEchoWalkTests: XCTestCase {
    func testLatestEmailsFamilyAcceptedWhileGrokSpeakingAndLastSpokenEmpty() {
        for ask in GrokSpeakingEmptyEchoWalk.latestEmailsFamily {
            let walk = GrokSpeakingEmptyEchoWalk.race(ask: ask)
            XCTAssertTrue(walk.accepted, ask)
            XCTAssertFalse(walk.dropped, ask)
            XCTAssertEqual(walk.intent, "inbox-overview", ask)
            XCTAssertNotEqual(walk.intent, "dropped", ask)
            XCTAssertNotEqual(walk.intent, "general", ask)
        }
    }

    func testSecondAskAfterFirstWouldHaveBeenDroppedIsStillAccepted() {
        let asks = GrokSpeakingEmptyEchoWalk.latestEmailsFamily
        let pair = GrokSpeakingEmptyEchoWalk.twoAsks(first: asks[0], second: asks[1])
        XCTAssertTrue(pair.first.accepted, asks[0])
        XCTAssertEqual(pair.first.intent, "inbox-overview", asks[0])
        XCTAssertTrue(pair.second.accepted, asks[1])
        XCTAssertFalse(pair.second.dropped, asks[1])
        XCTAssertEqual(pair.second.intent, "inbox-overview", asks[1])
    }

    func testVersionSHACalendarNamedEmailAcceptedWhileGrokSpeaking() {
        for ask in GrokSpeakingEmptyEchoWalk.versionFamily {
            let walk = GrokSpeakingEmptyEchoWalk.race(ask: ask)
            XCTAssertTrue(walk.accepted, ask)
            XCTAssertEqual(walk.intent, "version", ask)
            XCTAssertNotEqual(walk.intent, "dropped", ask)
        }
        for ask in GrokSpeakingEmptyEchoWalk.shaFamily {
            let walk = GrokSpeakingEmptyEchoWalk.race(ask: ask)
            XCTAssertTrue(walk.accepted, ask)
            XCTAssertEqual(walk.intent, "version", ask)
            XCTAssertTrue(ConversationPresence.wantsSHAAsk(ask), ask)
            XCTAssertNotEqual(walk.intent, "dropped", ask)
        }
        for ask in GrokSpeakingEmptyEchoWalk.calendarFamily {
            let walk = GrokSpeakingEmptyEchoWalk.race(
                ask: ask,
                context: VoiceRegressionDesk.massimoCalendar
            )
            XCTAssertTrue(walk.accepted, ask)
            XCTAssertEqual(walk.intent, "calendar", ask)
            XCTAssertNotEqual(walk.intent, "dropped", ask)
        }
        for ask in GrokSpeakingEmptyEchoWalk.namedEmailFamily {
            let walk = GrokSpeakingEmptyEchoWalk.race(
                ask: ask,
                context: VoiceRegressionDesk.greenacreFirst
            )
            XCTAssertTrue(walk.accepted, ask)
            XCTAssertTrue(["desk-person", "desk-thread"].contains(walk.intent), "\(ask) → \(walk.intent)")
            XCTAssertNotEqual(walk.intent, "dropped", ask)
            XCTAssertNotEqual(walk.intent, "general", ask)
        }
        for ask in GrokSpeakingEmptyEchoWalk.namedKatherineFamily {
            let walk = GrokSpeakingEmptyEchoWalk.race(
                ask: ask,
                context: VoiceRegressionDesk.massimoCalendar
            )
            XCTAssertTrue(walk.accepted, ask)
            XCTAssertTrue(["desk-person", "desk-thread"].contains(walk.intent), "\(ask) → \(walk.intent)")
            XCTAssertNotEqual(walk.intent, "dropped", ask)
        }
    }

    func testLiveIngressAfterVersionSpeakDropsLeftoverAndKeepsLatestEmails() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking(BuildIdentity.fixture.spokenLine)
        gate.finishSpeaking()
        for leftover in ["zero", "point one", "build 6"] {
            XCTAssertNil(
                EchoBargeIn.acceptedUserTranscript(leftover, gate: gate),
                leftover
            )
        }
        XCTAssertEqual(
            EchoBargeIn.acceptedUserTranscript(
                "show my latest emails",
                gate: gate,
                voiceState: .speaking
            ),
            "show my latest emails"
        )
        let empty = EchoTranscriptGate()
        XCTAssertEqual(
            EchoBargeIn.acceptedUserTranscript(
                "show my latest emails",
                gate: empty,
                voiceState: .speaking
            ),
            "show my latest emails"
        )
    }

    func testOnDeviceDeskTTSLeftoverStillDrops() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking("Murray Mitchell — Closing / notarization.")
        XCTAssertTrue(gate.isSpeaking)
        XCTAssertFalse(gate.lastSpokenLine.isEmpty)
        XCTAssertNil(gate.acceptUserTranscript("murray", voiceState: .speaking))
        XCTAssertEqual(gate.decide("murray").intent, "dropped")
        XCTAssertEqual(
            gate.acceptUserTranscript("what's on my calendar", voiceState: .speaking),
            "what's on my calendar"
        )
        XCTAssertEqual(
            gate.decide("what's on my calendar", context: VoiceRegressionDesk.connected).intent,
            "calendar"
        )
    }

    func testEmptyLastSpokenLineNeverDropsAndEmptyBeginSpeakingIsNotDeskTTS() {
        var gate = EchoTranscriptGate()
        gate.beginSpeaking("   ")
        XCTAssertFalse(gate.isSpeaking)
        XCTAssertTrue(gate.lastSpokenLine.isEmpty)
        XCTAssertEqual(
            gate.acceptUserTranscript("show my latest emails", voiceState: .speaking),
            "show my latest emails"
        )
        XCTAssertFalse(EchoTranscriptGate.isLeftoverEcho("show my latest emails", of: ""))
    }

    func testDroppedTranscriptIsEngineListenResumeNote() {
        let entry = ListenResumeLog.droppedTranscript()
        XCTAssertEqual(entry.source, "engine")
        XCTAssertEqual(entry.intent, ListenResumeLog.intent)
        XCTAssertTrue(entry.routingNotes.contains { $0.contains(ListenResumeLog.droppedTranscriptNote) })
        XCTAssertEqual(entry.userTranscript, "")
    }

    func testOneGateAndDroppedTranscriptIsLogged() throws {
        let source = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        XCTAssertFalse(source.contains("EchoBargeIn.acceptedUserTranscript"))
        XCTAssertFalse(source.contains("echoGate"))
        XCTAssertTrue(source.contains("interruptPlayback()"))
        XCTAssertTrue(source.contains("liveSessionArmed = true"))
        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        XCTAssertFalse(app.contains("EchoBargeIn.acceptedUserTranscript"), app)
        XCTAssertFalse(app.contains("echoGate"), app)
        XCTAssertFalse(app.contains("markSpeaking"))
        XCTAssertFalse(app.contains("voiceState: voice.state"), "Grok speaking must not drop")
        XCTAssertFalse(app.contains("lastSpokenLine.isEmpty { return nil }"))
        let gate = try XCTUnwrap(repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/EchoTranscriptGate.swift"))
        XCTAssertFalse(gate.contains("func markSpeaking"))
        XCTAssertFalse(gate.contains("lastSpokenLine.isEmpty { return nil }"))
        XCTAssertFalse(gate.contains("isSpeaking || voiceState"))
    }

    func testSessionStaysLiveAfterAudioStartOrWarmUpUnlessUserStop() {
        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: false,
                audioStarted: true
            ),
            "audio.start / warmUp is live unless they tapped stop"
        )
        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                audioStarted: false
            )
        )
        XCTAssertFalse(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: true,
                liveSessionArmed: true,
                audioStarted: true
            )
        )
        XCTAssertEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: ListenResumePolicy.sessionShouldStayLive(
                    userWantsVoiceOff: false,
                    liveSessionArmed: false,
                    audioStarted: true
                ),
                closeCode: 1000,
                voiceState: .idle
            ),
            .reconnect
        )
        XCTAssertNotEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: true,
                closeCode: 1000,
                voiceState: .idle
            ),
            .stayIdle
        )
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
