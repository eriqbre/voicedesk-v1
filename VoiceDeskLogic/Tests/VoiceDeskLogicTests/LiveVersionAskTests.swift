import XCTest
@testable import VoiceDeskLogic

/// Spoken loop against the a2727b1 restore-walk (L417–L424).
/// Production seams: handleLiveUser / speakDeskReply / shouldPlayBargeAudio /
/// DidClose → sessionShouldStayLive + afterSocketClose.
///
/// Walk holes this family is red on:
/// - L420+L421 same-second desk identity write + Eve stayLive (two-mouth)
/// - Eve cut / no firstAudio on the version turn while desk drained
/// - L424 DidClose 1000 stayIdle after the last reply, no audio.start after
///
/// jsonl has no dropAssistantOutput / clientTTSInFlight / unmute / firstAudio.
/// Do not invent those tokens. Phone stays a2727b1.
final class LiveVersionAskTests: XCTestCase {
    func testRestoreWalkIsTwoMouthEveCutAndStayIdle() throws {
        let records = A2727B1Walk.window
        let start = try XCTUnwrap(A2727B1Walk.audioStart(in: records))
        XCTAssertTrue(start.routingNotes.contains(where: { $0.contains("audio.start") }))

        let drain = try XCTUnwrap(A2727B1Walk.drain(in: records))
        XCTAssertEqual(drain.routingNotes, [A2727B1Walk.drainNote])
        XCTAssertTrue(drain.routingNotes[0].contains("stayLive=true"))

        let version = try XCTUnwrap(A2727B1Walk.versionTurn(in: records))
        XCTAssertEqual(version.userTranscript, A2727B1Walk.versionAsk)
        XCTAssertEqual(version.assistantReply, A2727B1Walk.spokenIdentity)
        XCTAssertEqual(version.voicePath, A2727B1Walk.eveRealtime)
        XCTAssertTrue(version.routingNotes.contains(A2727B1Walk.versionIdentityNote))
        XCTAssertTrue(version.routingNotes.contains(A2727B1Walk.versionDogfoodNote))
        XCTAssertEqual(version.timestamp, drain.timestamp, "L420+L421 same second")

        XCTAssertTrue(A2727B1Walk.versionIsDualMouth(in: records))
        XCTAssertTrue(A2727B1Walk.versionMouth(in: records).isDualMouth)
        XCTAssertTrue(
            A2727B1Walk.versionHasNoFirstAudioWhileDeskDrained(in: records),
            "Eve cut: desk drained, no firstAudio on the version turn"
        )

        let last = try XCTUnwrap(A2727B1Walk.lastUserTurn(in: records))
        XCTAssertEqual(last.userTranscript, A2727B1Walk.lastUserAsk)
        XCTAssertEqual(last.cardsAttached, [])
        XCTAssertEqual(last.voicePath, A2727B1Walk.eveRealtime)
        XCTAssertTrue(A2727B1Walk.diedStayIdleAfterLastReply(in: records))
        XCTAssertFalse(A2727B1Walk.hasAudioStart(after: last, in: records))

        let close = try XCTUnwrap(A2727B1Walk.sessionClose(in: records))
        XCTAssertTrue(close.routingNotes.contains(where: { $0.contains(A2727B1Walk.closeNote) }))

        XCTAssertFalse(A2727B1Walk.mentionsEveSpeaksIdentity(in: records))
        XCTAssertFalse(
            A2727B1Walk.mentionsMuteFlagTokens(in: records),
            "window has no dropAssistantOutput / clientTTSInFlight / unmute"
        )
    }

    func testProductionSpokenLoopFailsRestoreWalkLeftovers() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: true)
        XCTAssertTrue(session.handleLiveUser(A2727B1Walk.versionAsk))
        XCTAssertEqual(session.assistantReply, A2727B1Walk.spokenIdentity)
        XCTAssertEqual(session.voicePath, A2727B1Walk.eveRealtime)
        XCTAssertTrue(session.routingNotes.contains(A2727B1Walk.versionIdentityNote))
        XCTAssertTrue(session.routingNotes.contains(A2727B1Walk.versionDogfoodNote))
        XCTAssertFalse(session.routingNotes.contains(where: { $0.contains("eve speaks identity") }))
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: session.routingNotes,
                assistantReply: session.assistantReply,
                wrotePlayerPCM: false
            )
        )

        // TWO-MOUTH: walk wrote desk identity while Eve stayLive.
        XCTAssertFalse(
            session.speakDeskReply(session.spokenIdentityLine),
            "L420+L421 desk write on live VAD is the second mouth"
        )
        XCTAssertFalse(session.wroteIdentityPCM)
        XCTAssertTrue(playerAllowsEve(), "Eve is the live-Talk mouth")
        XCTAssertFalse(session.wroteIdentityPCM && playerAllowsEve())

        // EVE CUT: no firstAudio while desk drained. Do not interrupt her
        // pending mouth. jsonl has no mute-flag token to flip.
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true
            ),
            "Eve must finish; version drain is not a barge cut"
        )

        // POST-EMAIL DEAF: L424 DidClose 1000 stayIdle after a real reply.
        // Production DidClose uses sessionShouldStayLive, not listen-armed-only.
        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                audioStarted: true
            )
        )
        XCTAssertEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: true,
                closeCode: 1000,
                voiceState: .idle,
                liveSessionArmed: true
            ),
            .reconnect,
            "L424 leftover: state=idle stayLive=false stayIdle after the last reply"
        )
        XCTAssertEqual(
            ListenResumePolicy.afterSocketClose(
                userWantsVoiceOff: false,
                sessionShouldStayLive: ListenResumePolicy.sha415c955StayLiveAfterClose1000(
                    userWantsVoiceOff: false,
                    listenArmed: false
                ),
                closeCode: 1000,
                voiceState: .idle,
                liveSessionArmed: false
            ),
            .stayIdle,
            "walk DidClose: idle + listen-armed stayLive=false + unarmed → stayIdle"
        )
        var listen = VoiceSession()
        listen.apply(.tapTalk)
        let after = ListenResumePolicy.afterClientTTSFinished(
            session: &listen,
            userWantsVoiceOff: false,
            liveSessionArmed: true,
            captureRunning: true
        )
        XCTAssertTrue(after.stayLive)
        XCTAssertNotEqual(after.close1000, .stayIdle)
        XCTAssertFalse(after.startAgain, "no audio.start after a real reply")
    }

    func testOfflineVersionStillWritesIdentityNotEmptyEveLie() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: false)
        XCTAssertTrue(session.handleLiveUser(A2727B1Walk.versionAsk))
        XCTAssertTrue(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertTrue(session.wroteIdentityPCM)
        XCTAssertEqual(session.identityPCM, A2727B1Walk.spokenIdentity)
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
            )
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
