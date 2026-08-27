import XCTest
@testable import VoiceDeskLogic

/// After production handleLiveUser + speakDeskReply, Eve PCM is
/// `LiveVADPlayerKeep.shouldPlayEveAudio` — the function
/// `GrokVoiceService.shouldPlayBargeAudio` calls. No reconstructed
/// ingest helpers. L402: identity write + Eve realtime.
final class LiveVersionAskTests: XCTestCase {
    private let ask = "Good morning. What version are we on?"

    func testA2727b1LeftoverBargeOnlyIsTwoMouthsAfterHandleLiveUserSpeakDeskReply() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: true)
        XCTAssertTrue(session.handleLiveUser(ask))
        XCTAssertTrue(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertEqual(session.assistantReply, "VoiceDesk point 1, build 6.")
        XCTAssertEqual(session.voicePath, "Eve realtime")
        XCTAssertTrue(session.routingNotes.contains("local build identity"))
        XCTAssertTrue(session.routingNotes.contains("0.1.0 build 6 sha a2727b1"))
        XCTAssertTrue(session.wroteIdentityPCM)
        XCTAssertTrue(session.dropAssistantOutput)
        XCTAssertTrue(session.clientTTSInFlight)
        let leftoverBargeOnly = GrokRealtime.shouldScheduleAfterBarge(
            bargeConsumed: false,
            deltaResponseID: "eve",
            cancelledResponseID: nil
        )
        XCTAssertTrue(leftoverBargeOnly, "a2727b1 shouldPlayBargeAudio was leftover barge only")
        XCTAssertTrue(
            session.wroteIdentityPCM && leftoverBargeOnly,
            "a2727b1: desk identity write + Eve realtime on the same version turn"
        )
    }

    func testProductionShouldPlayEveAudioDropsEveAfterHandleLiveUserSpeakDeskReply() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: true)
        XCTAssertTrue(session.handleLiveUser(ask))
        XCTAssertTrue(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertEqual(session.assistantReply, "VoiceDesk point 1, build 6.")
        XCTAssertEqual(session.voicePath, "Eve realtime")
        XCTAssertTrue(session.routingNotes.contains("local build identity"))
        XCTAssertTrue(session.wroteIdentityPCM)
        let eve = LiveVADPlayerKeep.shouldPlayEveAudio(
            dropAssistantOutput: session.dropAssistantOutput,
            clientTTSInFlight: session.clientTTSInFlight
        )
        XCTAssertFalse(eve, "shouldPlayBargeAudio must call shouldPlayEveAudio")
        XCTAssertFalse(session.wroteIdentityPCM && eve)
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: session.routingNotes,
                assistantReply: session.assistantReply,
                wrotePlayerPCM: session.wroteIdentityPCM
            )
        )
    }

    func testShouldPlayBargeAudioCallsShouldPlayEveAudio() throws {
        let service = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        let playGate = speakSlice(
            service,
            from: "private func shouldPlayBargeAudio",
            to: "private func noteScheduledResponse"
        )
        XCTAssertTrue(
            playGate.contains("LiveVADPlayerKeep.shouldPlayEveAudio"),
            "Linux cannot instantiate GrokVoiceService — this is the production call"
        )
        XCTAssertTrue(playGate.contains("dropAssistantTranscript"), playGate)
        XCTAssertTrue(playGate.contains("clientTTSInFlight"), playGate)
        XCTAssertTrue(playGate.contains("shouldScheduleAfterBarge"), playGate)
        XCTAssertFalse(service.contains("ingestEveRealtimeDelta"), service)
        XCTAssertFalse(service.contains("ingestEveRealtimeDeltaA2727B1"), service)

        let seam = try XCTUnwrap(repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/LiveVersionAsk.swift"))
        XCTAssertFalse(seam.contains("ingestEveRealtimeDelta"), seam)
        XCTAssertFalse(seam.contains("ingestEveRealtimeDeltaA2727B1"), seam)

        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        let handle = speakSlice(
            app,
            from: "private func handleLiveUser",
            to: "private func upsertLiveAssistant"
        )
        XCTAssertTrue(handle.contains("if liveVersionAsk.handleLiveUser(text)"), handle)
        XCTAssertTrue(handle.contains("claimLocalAssistantReply()"), handle)
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldPlayEveAudio(
                dropAssistantOutput: false,
                clientTTSInFlight: false
            ),
            "later Eve turns still play"
        )
    }

    private func speakSlice(_ source: String, from: String, to: String) -> String {
        guard let start = source.range(of: from),
              let end = source.range(of: to, range: start.upperBound..<source.endIndex)
        else { return "" }
        return String(source[start.lowerBound..<end.lowerBound])
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
