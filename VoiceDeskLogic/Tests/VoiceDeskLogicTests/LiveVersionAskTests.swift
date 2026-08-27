import XCTest
@testable import VoiceDeskLogic

/// Spoken loop on the production seams AppModel.handleLiveUser,
/// AppModel.speakDeskReply, GrokVoiceService.returnToListenAfterDeskTTS,
/// and GrokVoiceService.shouldPlayBargeAudio call.
///
/// a2727b1 two-mouth: desk identity PCM AND Eve on the same live turn.
/// Eve voice-cut: interrupt while she still has pending playback.
/// Post-email deaf: mute stuck / listen dies after she speaks.
/// This family is red on those leftovers. Not flash-ready.
final class LiveVersionAskTests: XCTestCase {
    private let ask = "Good morning. What version are we on?"

    func testLiveVersionAskIsOneEveMouthSheFinishesThenListenStays() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: true)
        XCTAssertTrue(session.handleLiveUser(ask))
        XCTAssertEqual(session.assistantReply, "VoiceDesk point 1, build 6.")
        XCTAssertEqual(session.voicePath, "Eve realtime")
        XCTAssertTrue(session.routingNotes.contains("local build identity"))
        XCTAssertTrue(session.routingNotes.contains("0.1.0 build 6 sha a2727b1"))
        XCTAssertFalse(
            session.routingNotes.contains(where: { $0.contains("eve speaks identity") }),
            "c1cd758 empty eve-speaks-identity silent return must not come back"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: session.routingNotes,
                assistantReply: session.assistantReply,
                wrotePlayerPCM: false
            )
        )

        // TWO-MOUTH: a2727b1 wrote desk identity on live VAD while Eve also played.
        XCTAssertFalse(
            session.speakDeskReply(session.spokenIdentityLine),
            "desk write on live VAD is the second mouth"
        )
        XCTAssertFalse(session.wroteIdentityPCM)
        let eve = playerAllowsEve()
        XCTAssertTrue(eve, "Eve is the live-Talk mouth")
        XCTAssertFalse(
            session.wroteIdentityPCM && eve,
            "a2727b1: identity write + Eve PCM on the same turn"
        )
        XCTAssertTrue(
            LiveTalkMouth.liveTalkEveOnly().eveVoicePath
                && !LiveTalkMouth.liveTalkEveOnly().clientVoiceSpeechWrite
        )
        XCTAssertTrue(LiveTalkMouth.firstAskDeskIdentityPlusEve().isDualMouth)

        // VOICE-CUT: a2727b1 deskWritesIdentity interrupted while Eve had pending.
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true
            ),
            "Eve must finish; interrupt is the next turn on a real command"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: true,
                hasPendingPlayback: true
            )
        )
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: false
            ),
            "after she finishes, a real next-turn command may interrupt leftover"
        )

        // POST-EMAIL DEAF: after version, next Eve delta still plays; listen stays.
        XCTAssertTrue(
            playerAllowsEve(),
            "8927c2d mute stuck: following Eve (emails) was silent / mic felt deaf"
        )
        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                audioStarted: true,
                clientTTSInFlight: false
            )
        )
        var listen = VoiceSession()
        listen.apply(.tapTalk)
        let after = ListenResumePolicy.afterClientTTSFinished(
            session: &listen,
            userWantsVoiceOff: false,
            liveSessionArmed: true,
            captureRunning: true
        )
        XCTAssertTrue(after.stayLive, "GrokVoiceService.returnToListenAfterDeskTTS stayLive")
        XCTAssertTrue(after.listenArmed)
        XCTAssertNotEqual(after.close1000, .stayIdle, "close 1000 after she speaks is not mic-deaf")
        XCTAssertFalse(after.startAgain)
    }

    func testOfflineVersionStillWritesIdentityNotEmptyEveLie() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: false)
        XCTAssertTrue(session.handleLiveUser(ask))
        XCTAssertTrue(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertTrue(session.wroteIdentityPCM)
        XCTAssertEqual(session.identityPCM, "VoiceDesk point 1, build 6.")
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: session.routingNotes,
                assistantReply: session.assistantReply,
                wrotePlayerPCM: session.wroteIdentityPCM
            )
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: session.spokenIdentityLine,
                identityLine: session.spokenIdentityLine
            ),
            "live VAD must not add a desk mouth"
        )
    }

    private func playerAllowsEve() -> Bool {
        LiveVADPlayerKeep.shouldPlayBargeAudio(
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
