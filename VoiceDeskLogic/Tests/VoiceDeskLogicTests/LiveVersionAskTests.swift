import XCTest
@testable import VoiceDeskLogic

/// After production handleLiveUser + speakDeskReply, Eve PCM is
/// `LiveVADPlayerKeep.shouldPlayBargeAudio` — the same function
/// GrokVoiceService.shouldPlayBargeAudio wraps. Drain is
/// `LiveVADPlayerKeep.returnToListenAfterDeskTTS` — the flag-clear
/// body `GrokVoiceService.returnToListenAfterDeskTTS` calls.
/// Not flash-ready.
final class LiveVersionAskTests: XCTestCase {
    private let ask = "Good morning. What version are we on?"

    func testShouldPlayBargeAudioDropsEveAfterHandleLiveUserSpeakDeskReply() {
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
        let eve = LiveVADPlayerKeep.shouldPlayBargeAudio(
            dropAssistantOutput: session.dropAssistantOutput,
            clientTTSInFlight: session.clientTTSInFlight,
            bargeConsumed: false,
            deltaResponseID: "eve",
            cancelledResponseID: nil,
            createdAwaitingAudioID: nil,
            lastCreatedResponseID: nil,
            playingResponseID: nil,
            lastScheduledResponseID: nil,
            hasPendingPlayback: true
        )
        XCTAssertFalse(
            eve,
            "a2727b1 leftover barge-only returned true here; shouldPlayEveAudio guard must drop Eve"
        )
        XCTAssertFalse(session.wroteIdentityPCM && eve)
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: session.routingNotes,
                assistantReply: session.assistantReply,
                wrotePlayerPCM: session.wroteIdentityPCM
            )
        )
    }

    /// 8927c2d leftover: returnToListenAfterDeskTTS cleared
    /// clientTTSInFlight only. drop stayed true — following Eve
    /// delta is shouldPlayBargeAudio false. Same function
    /// GrokVoiceService.returnToListenAfterDeskTTS calls.
    func testFollowingEveDeltaPlaysAfterIdentityWriteDrain() throws {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: true)
        XCTAssertTrue(session.handleLiveUser(ask))
        XCTAssertTrue(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertTrue(session.wroteIdentityPCM)
        XCTAssertFalse(
            playerAllowsEve(session),
            "Eve dropped during identity write only"
        )

        session.returnToListenAfterDeskTTS()
        XCTAssertTrue(
            playerAllowsEve(session),
            "8927c2d leftover cleared clientTTS only; drop stayed true and Eve stayed false"
        )

        let desk = speakSlice(
            try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift")),
            from: "private func speakDeskReply(_ text: String) async {",
            to: "private func rememberUserTurn"
        )
        XCTAssertTrue(desk.contains("liveVersionAsk.returnToListenAfterDeskTTS()"), desk)
        XCTAssertTrue(desk.contains("unmuteGrokAssistant()"), desk)
        XCTAssertFalse(
            desk.contains("&liveVersionAsk."),
            "8fdc481: two inouts of Observation liveVersionAsk alias — device compile 65"
        )
    }

    private func playerAllowsEve(_ session: LiveVersionAsk) -> Bool {
        LiveVADPlayerKeep.shouldPlayBargeAudio(
            dropAssistantOutput: session.dropAssistantOutput,
            clientTTSInFlight: session.clientTTSInFlight,
            bargeConsumed: false,
            deltaResponseID: "eve",
            cancelledResponseID: nil,
            createdAwaitingAudioID: nil,
            lastCreatedResponseID: nil,
            playingResponseID: nil,
            lastScheduledResponseID: nil,
            hasPendingPlayback: true
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
