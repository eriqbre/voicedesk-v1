import XCTest
@testable import VoiceDeskLogic

/// a2727b1 restore-walk L420+L421: desk identity write + Eve stayLive
/// on the same version second. Mute-flag tokens are not in the window.
final class FirstAskOneMouthTests: XCTestCase {
    func testA2727b1RestoreWalkVersionIsDeskIdentityPlusEveRealtime() throws {
        let records = A2727B1Walk.bakedRestoreWalk
        let start = try XCTUnwrap(A2727B1Walk.audioStart(in: records))
        XCTAssertEqual(start.source, ListenResumeLog.source)
        XCTAssertEqual(start.intent, ListenResumeLog.intent)
        XCTAssertTrue(start.routingNotes.contains(where: { $0.contains("audio.start") }))
        XCTAssertEqual(start.assistantReply, "")

        let drain = try XCTUnwrap(A2727B1Walk.drain(in: records))
        XCTAssertEqual(drain.source, ListenResumeLog.source)
        XCTAssertEqual(drain.intent, ListenResumeLog.intent)
        XCTAssertEqual(drain.routingNotes, [A2727B1Walk.drainNote])

        let version = try XCTUnwrap(A2727B1Walk.versionTurn(in: records))
        XCTAssertEqual(version.source, "live voice")
        XCTAssertEqual(version.userTranscript, A2727B1Walk.versionAsk)
        XCTAssertEqual(version.intent, "version")
        XCTAssertTrue(version.routingNotes.contains(A2727B1Walk.versionIdentityNote))
        XCTAssertTrue(version.routingNotes.contains(A2727B1Walk.versionDogfoodNote))
        XCTAssertEqual(version.assistantReply, A2727B1Walk.spokenIdentity)
        XCTAssertEqual(version.cardsAttached, [])
        XCTAssertEqual(version.voicePath, A2727B1Walk.eveRealtime)
        XCTAssertFalse(
            version.routingNotes.contains(where: { $0.contains("eve speaks identity") })
        )
        XCTAssertTrue(
            A2727B1Walk.versionIsDualMouth(in: records),
            "desk identity write + Eve realtime on the same version turn"
        )
        XCTAssertTrue(A2727B1Walk.versionMouth(in: records).isDualMouth)
        XCTAssertTrue(
            LiveTalkMouth.versionTurnIsDualMouth(
                versionNotes: version.routingNotes,
                assistantReply: version.assistantReply,
                voicePath: version.voicePath,
                drainNotes: drain.routingNotes
            )
        )
        XCTAssertFalse(
            LiveTalkMouth.versionTurnIsDualMouth(
                versionNotes: version.routingNotes,
                assistantReply: version.assistantReply,
                voicePath: version.voicePath,
                drainNotes: []
            ),
            "drain is the sibling listen-resume, not a boolean eveAlsoSpoke"
        )
        XCTAssertTrue(ConversationPresence.wantsVersionAsk(A2727B1Walk.versionAsk))
        XCTAssertTrue(A2727B1Walk.versionIsDualMouth())
        XCTAssertTrue(A2727B1Walk.versionHasNoFirstAudioWhileDeskDrained(in: records))
        XCTAssertTrue(A2727B1Walk.diedStayIdleAfterLastReply(in: records))
        XCTAssertFalse(A2727B1Walk.mentionsMuteFlagTokens(in: records))
    }

    func testFirstAskDeskPlusEveIsTwoMouthsAndFixIsEveOnly() {
        let hole = LiveTalkMouth.firstAskDeskIdentityPlusEve()
        XCTAssertTrue(hole.afterDeskTTSDrain)
        XCTAssertTrue(hole.liveVADResponse)
        XCTAssertTrue(hole.clientVoiceSpeechWrite)
        XCTAssertTrue(hole.eveVoicePath)
        XCTAssertFalse(hole.sentVerbatimCreate)
        XCTAssertTrue(
            hole.isDualMouth,
            "desk TTS write + Eve realtime is two mouths"
        )

        let keep = LiveTalkMouth.liveTalkEveOnly()
        XCTAssertFalse(keep.afterDeskTTSDrain)
        XCTAssertFalse(keep.clientVoiceSpeechWrite)
        XCTAssertTrue(keep.eveVoicePath)
        XCTAssertFalse(keep.sentVerbatimCreate)
        XCTAssertFalse(keep.isDualMouth)
        XCTAssertFalse(GrokRealtime.shouldSendVerbatimCreate(liveVADTurn: true))
    }

    func testVersionAskKeepsEveMouthAndDoesNotWriteDesk() {
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true
            ),
            "Eve must finish; version ask is not a barge cut"
        )
        XCTAssertTrue(
            ConversationPresence.wantsVersionAsk("Hey, good morning. What version are we on?")
        )
        XCTAssertFalse(ConversationPresence.wantsVersionAsk("Can you hear me?"))
        let identity = ConversationPresence.spokenIdentityLine(
            for: "Hey, good morning. What version are we on?",
            identity: .fixture
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: identity,
                identityLine: identity
            ),
            "live VAD desk identity write is the second mouth"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: ["local build identity"],
                assistantReply: identity,
                wrotePlayerPCM: false
            )
        )
    }

    /// a2727b1: desk write→player AND Eve live VAD PCM. Mute flags
    /// tried to hide Eve and stuck. Live Talk is Eve only.
    func testIdentityWriteAndEveDeltasBothReachPlayerIsTheHole() throws {
        XCTAssertTrue(
            LiveTalkMouth.firstAskDeskIdentityPlusEve().isDualMouth
        )
        XCTAssertFalse(
            LiveTalkMouth.liveTalkEveOnly().isDualMouth
        )

        let service = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        let speakFn = speakSlice(
            service,
            from: "func speak(_ text: String) async {",
            to: "private func returnToListenAfterDeskTTS"
        )
        XCTAssertTrue(speakFn.contains("ClientVoiceSpeech.shared.speak"), speakFn)
        XCTAssertTrue(speakFn.contains("playPCM16"), speakFn)
        if let realtimeAt = speakFn.range(of: "shouldSpeakViaRealtime"),
           let writeAt = speakFn.range(of: "ClientVoiceSpeech.shared.speak") {
            let between = String(speakFn[realtimeAt.upperBound..<writeAt.lowerBound])
            XCTAssertFalse(
                between.contains("return"),
                "do not restore empty eve-speaks-identity / silent player"
            )
        } else {
            XCTFail("identity must still write→player")
        }
        XCTAssertFalse(service.contains("eve speaks identity"), service)
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
