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
    func testFollowingEveDeltaPlaysAfterIdentityWriteDrain() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: true)
        XCTAssertTrue(session.handleLiveUser(ask))
        XCTAssertTrue(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertTrue(session.wroteIdentityPCM)
        XCTAssertFalse(
            playerAllowsEve(session),
            "Eve dropped during identity write only"
        )

        LiveVADPlayerKeep.returnToListenAfterDeskTTS(
            dropAssistantOutput: &session.dropAssistantOutput,
            clientTTSInFlight: &session.clientTTSInFlight
        )
        XCTAssertTrue(
            playerAllowsEve(session),
            "8927c2d leftover cleared clientTTS only; drop stayed true and Eve stayed false"
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
}
