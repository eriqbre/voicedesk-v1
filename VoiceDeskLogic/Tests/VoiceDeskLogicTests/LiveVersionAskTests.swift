import XCTest
@testable import VoiceDeskLogic

/// REQ-LOOP-1 / REQ-LOOP-2 / REQ-LOOP-3. Production seams:
/// handleLiveUser / speakDeskReply / SpokenLoopLog / afterSocketClose.
/// Named after the behavior. Observables: mouth, first_audio, stayLive.
/// Not source-scrape. Not mute-flag gossip.
final class LiveVersionAskTests: XCTestCase {

    /// REQ-LOOP-1 | one mouth on version
    func testOneMouthOnVersionDoesNotPlayDeskIdentityAndEveOnTheSameTurn() {
        let sessionID = SpokenLoopLog.beginSession()
        let walk = a2727b1VersionWalkEvents(sessionID: sessionID)
        XCTAssertTrue(
            SpokenLoopLog.isTwoMouth(walk),
            "a2727b1 L420 drain + L421 local build identity same second with Eve stayLive"
        )
        XCTAssertEqual(Set(SpokenLoopLog.mouths(in: walk)), [.desk, .eve])

        var session = LiveVersionAsk(
            identity: .a2727b1Walk,
            liveVADTurn: true,
            sessionID: sessionID
        )
        XCTAssertTrue(session.handleLiveUser(A2727B1Walk.versionAsk))
        XCTAssertFalse(
            session.speakDeskReply(session.spokenIdentityLine),
            "desk identity write on live VAD is the second mouth"
        )
        XCTAssertFalse(session.wroteIdentityPCM)
        let events = session.spokenLoopTurnEvents(intent: "version")
        XCTAssertFalse(SpokenLoopLog.isTwoMouth(events))
        XCTAssertEqual(SpokenLoopLog.mouths(in: events), [.eve])
        XCTAssertFalse(SpokenLoopLog.containsTranscriptOrBody(events[0]))
        XCTAssertEqual(SpokenLoopLog.parse(events[0])["event"], SpokenLoopLog.turnStartEvent)
        XCTAssertEqual(SpokenLoopLog.parse(events[0])["intent"], "version")
        XCTAssertEqual(SpokenLoopLog.parse(events[0])["session"], sessionID)
    }

    /// REQ-LOOP-2 | Eve finishes the turn
    func testEveFinishesTheTurnWithoutVoiceCutOrEmptyFirstAudio() {
        let sessionID = SpokenLoopLog.beginSession()
        let walk = a2727b1VersionWalkEvents(sessionID: sessionID)
        XCTAssertTrue(
            SpokenLoopLog.isVoiceCut(walk),
            "version drain + Eve stayLive + first_audio absent"
        )
        XCTAssertEqual(SpokenLoopLog.firstAudioStatus(in: walk), .absent)

        var session = LiveVersionAsk(
            identity: .a2727b1Walk,
            liveVADTurn: true,
            sessionID: sessionID
        )
        XCTAssertTrue(session.handleLiveUser(A2727B1Walk.versionAsk))
        XCTAssertFalse(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true
            )
        )
        let events = session.spokenLoopTurnEvents(intent: "version")
        XCTAssertEqual(SpokenLoopLog.firstAudioStatus(in: events), .present)
        XCTAssertFalse(SpokenLoopLog.isVoiceCut(events))
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: session.routingNotes,
                assistantReply: session.assistantReply,
                wrotePlayerPCM: false
            )
        )
    }

    /// REQ-LOOP-3 | session stays listening after a real email reply
    func testSessionStaysListeningAfterEmailReplyNotDidCloseStayIdle() throws {
        let records = A2727B1Walk.window
        let last = try XCTUnwrap(A2727B1Walk.lastUserTurn(in: records))
        let close = try XCTUnwrap(A2727B1Walk.sessionClose(in: records))
        XCTAssertEqual(last.userTranscript, A2727B1Walk.lastUserAsk)
        XCTAssertEqual(close.timestamp.timeIntervalSince(last.timestamp), 8, accuracy: 0.5)
        XCTAssertTrue(
            A2727B1Walk.diedStayIdleAfterLastReply(in: records),
            "L423 then L424 stayIdle 8s later with no audio.start after"
        )

        let sessionID = SpokenLoopLog.beginSession()
        let walkClose = SpokenLoopLog.sessionClose(
            sessionID: sessionID,
            code: 1000,
            stayLive: false,
            stayIdle: true
        )
        XCTAssertTrue(SpokenLoopLog.closeIsStayIdle([walkClose]))

        XCTAssertTrue(
            ListenResumePolicy.sessionShouldStayLive(
                userWantsVoiceOff: false,
                liveSessionArmed: true,
                audioStarted: true
            )
        )
        let decision = ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: false,
            sessionShouldStayLive: true,
            closeCode: 1000,
            voiceState: .idle,
            liveSessionArmed: true
        )
        XCTAssertEqual(decision, .reconnect)
        let healthy = SpokenLoopLog.sessionClose(
            sessionID: sessionID,
            code: 1000,
            stayLive: true,
            stayIdle: decision == .stayIdle
        )
        XCTAssertFalse(SpokenLoopLog.closeIsStayIdle([healthy]))
        XCTAssertEqual(SpokenLoopLog.parse(healthy)["stayLive"], "true")
        XCTAssertEqual(SpokenLoopLog.parse(healthy)["stayIdle"], "false")
        XCTAssertFalse(SpokenLoopLog.containsTranscriptOrBody(healthy))
        XCTAssertFalse(A2727B1Walk.hasAudioStart(after: last, in: records))
    }

    func testSpokenLoopLogIsStructuredKeyValueWithoutTranscripts() {
        let sessionID = SpokenLoopLog.beginSession()
        let start = SpokenLoopLog.turnStart(sessionID: sessionID, intent: "mail")
        let mouth = SpokenLoopLog.mouth(sessionID: sessionID, mouth: .eve)
        let audio = SpokenLoopLog.firstAudio(sessionID: sessionID, status: .present)
        let drain = SpokenLoopLog.deskTTSDrain(
            sessionID: sessionID,
            listenArmed: true,
            stayLive: true,
            state: "listening"
        )
        let close = SpokenLoopLog.sessionClose(
            sessionID: sessionID,
            code: 1000,
            stayLive: true,
            stayIdle: false
        )
        for entry in [start, mouth, audio, drain, close] {
            XCTAssertFalse(SpokenLoopLog.containsTranscriptOrBody(entry), entry.routingNotes.joined())
            XCTAssertEqual(SpokenLoopLog.parse(entry)["session"], sessionID)
            XCTAssertTrue(entry.routingNotes[0].contains("event=spoken_loop."))
        }
        XCTAssertEqual(SpokenLoopLog.parse(start)["intent"], "mail")
        XCTAssertEqual(SpokenLoopLog.parse(mouth)["mouth"], "eve")
        XCTAssertEqual(SpokenLoopLog.parse(audio)["first_audio"], "present")
        XCTAssertEqual(SpokenLoopLog.parse(drain)["listenArmed"], "true")
        XCTAssertEqual(SpokenLoopLog.parse(close)["code"], "1000")
    }

    func testOfflineVersionStillWritesIdentityNotEmptyEveLie() {
        var session = LiveVersionAsk(identity: .a2727b1Walk, liveVADTurn: false)
        XCTAssertTrue(session.handleLiveUser(A2727B1Walk.versionAsk))
        XCTAssertTrue(session.speakDeskReply(session.spokenIdentityLine))
        XCTAssertTrue(session.wroteIdentityPCM)
        XCTAssertEqual(session.spokenLoopMouth, .desk)
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: session.routingNotes,
                assistantReply: session.assistantReply,
                wrotePlayerPCM: session.wroteIdentityPCM
            )
        )
    }

    private func a2727b1VersionWalkEvents(sessionID: String) -> [VoiceInteractionEntry] {
        [
            SpokenLoopLog.deskTTSDrain(
                sessionID: sessionID,
                listenArmed: true,
                stayLive: true,
                state: "listening"
            ),
            SpokenLoopLog.mouth(sessionID: sessionID, mouth: .desk),
            SpokenLoopLog.mouth(sessionID: sessionID, mouth: .eve),
            SpokenLoopLog.firstAudio(sessionID: sessionID, status: .absent)
        ]
    }
}
