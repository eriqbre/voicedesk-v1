import XCTest
@testable import VoiceDeskLogic

/// a2727b1 walk L400–L402 (17:20:50–17:21:58Z): desk identity write
/// + Eve realtime voicePath on the same version turn. Unmute /
/// claimLocal / eveAlsoSpoke paper is not the path. Later turns stay.
final class FirstAskOneMouthTests: XCTestCase {
    func testA2727b1WalkVersionIsDeskIdentityPlusEveRealtime() throws {
        let records = A2727B1Walk.window
        let start = try XCTUnwrap(A2727B1Walk.audioStart(in: records))
        XCTAssertEqual(start.intent, ListenResumeLog.intent)
        XCTAssertTrue(start.routingNotes[0].contains("audio.start"), start.routingNotes[0])
        XCTAssertEqual(start.voicePath, A2727B1Walk.eveRealtime)

        let drain = try XCTUnwrap(A2727B1Walk.drain(in: records))
        XCTAssertTrue(drain.routingNotes[0].contains("after desk tts drain"), drain.routingNotes[0])
        XCTAssertTrue(drain.routingNotes[0].contains("listenArmed=true"), drain.routingNotes[0])
        XCTAssertTrue(drain.routingNotes[0].contains("stayLive=true"), drain.routingNotes[0])
        XCTAssertEqual(drain.voicePath, A2727B1Walk.eveRealtime)

        let version = try XCTUnwrap(A2727B1Walk.versionTurn(in: records))
        XCTAssertEqual(version.userTranscript, A2727B1Walk.versionAsk)
        XCTAssertEqual(version.intent, "version")
        XCTAssertTrue(version.routingNotes.contains(A2727B1Walk.versionIdentityNote), "\(version.routingNotes)")
        XCTAssertTrue(version.routingNotes.contains(A2727B1Walk.versionDogfoodNote), "\(version.routingNotes)")
        XCTAssertEqual(version.assistantReply, A2727B1Walk.spokenIdentity)
        XCTAssertEqual(version.cardsAttached, [])
        XCTAssertEqual(version.voicePath, A2727B1Walk.eveRealtime)
        XCTAssertFalse(
            version.routingNotes.contains(where: { $0.contains("eve speaks identity") }),
            "a2727b1 wrote identity — not the c1cd758 empty eve-speaks-identity lie"
        )
        XCTAssertTrue(
            A2727B1Walk.firstAskIsDualMouth(in: records),
            "desk identity write + Eve realtime on the same version turn"
        )
        XCTAssertTrue(A2727B1Walk.firstAskMouth(in: records).isDualMouth)
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
    }

    func testFirstAskDeskPlusEveIsTwoMouthsAndFixIsDeskOnly() {
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

        let keep = LiveTalkMouth.firstAskDeskIdentityOnly()
        XCTAssertTrue(keep.afterDeskTTSDrain)
        XCTAssertTrue(keep.clientVoiceSpeechWrite)
        XCTAssertFalse(keep.eveVoicePath)
        XCTAssertFalse(keep.sentVerbatimCreate)
        XCTAssertFalse(keep.isDualMouth)
        XCTAssertFalse(LiveTalkMouth.liveTalkEveOnly().isDualMouth)
        XCTAssertFalse(GrokRealtime.shouldSendVerbatimCreate(liveVADTurn: true))
    }

    func testVersionAskDropsEveSoDeskIdentityIsTheOnlyMouth() {
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true,
                deskWritesIdentity: true
            ),
            "first-ask identity write must drop Eve or both mouths play"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true,
                deskWritesIdentity: false
            ),
            "later Eve turns keep first-answer PCM"
        )
        XCTAssertTrue(
            ConversationPresence.wantsVersionAsk("Hey, good morning. What version are we on?")
        )
        XCTAssertFalse(ConversationPresence.wantsVersionAsk("Can you hear me?"))
        let identity = ConversationPresence.spokenIdentityLine(
            for: "Hey, good morning. What version are we on?",
            identity: .fixture
        )
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: identity,
                identityLine: identity
            )
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: ["local build identity"],
                assistantReply: identity,
                wrotePlayerPCM: true
            )
        )
    }

    func testHandleLiveUserDoesNotUnmuteEveOnVersionWrite() throws {
        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        let handle = speakSlice(
            app,
            from: "private func handleLiveUser",
            to: "private func upsertLiveAssistant"
        )
        XCTAssertTrue(handle.contains("deskWritesIdentity"), handle)
        XCTAssertTrue(handle.contains("wantsVersionAsk"), handle)
        XCTAssertTrue(handle.contains("deskWritesIdentity: deskWritesIdentity"), handle)
        XCTAssertTrue(handle.contains("claimLocalAssistantReply()"), handle)

        let connected = speakSlice(
            handle,
            from: "if isLiveVADTurn, deskWritesIdentity",
            to: "if yieldGrokInterruptAnswer"
        )
        XCTAssertTrue(connected.contains("claimLocalAssistantReply()"), connected)
        XCTAssertTrue(connected.contains("fulfillConnectedDeskTurn"), connected)
        XCTAssertFalse(
            connected.contains("unmuteGrokAssistant()"),
            "4f4f4da unmuted Eve then wrote identity — two mouths"
        )

        let evidence = speakSlice(
            handle,
            from: "if let evidence = ConversationPresence.deskEvidence",
            to: "unmuteGrokAssistant()\n        pendingDeskTopic"
        )
        XCTAssertTrue(evidence.contains("deskWritesIdentity"), evidence)
        XCTAssertTrue(evidence.contains("claimLocalAssistantReply()"), evidence)
        let versionEvidence = speakSlice(
            evidence,
            from: "if isLiveVADTurn, deskWritesIdentity",
            to: "if yieldGrokInterruptAnswer"
        )
        XCTAssertFalse(
            versionEvidence.contains("unmuteGrokAssistant()"),
            versionEvidence
        )

        XCTAssertFalse(handle.contains("Here they are"), handle)
        XCTAssertFalse(handle.contains("speakLiveReplyViaEve"), handle)
    }

    /// a2727b1 was green on unmute/claimLocal paper and still two
    /// mouths: desk write→player AND Eve live VAD PCM. Suppress
    /// dropped the transcript only. This is the device path.
    func testIdentityWriteAndEveDeltasBothReachPlayerIsTheHole() throws {
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldPlayEveAudio(
                dropAssistantOutput: true,
                clientTTSInFlight: false
            ),
            "claimLocal suppress must drop Eve PCM, not only the transcript"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldPlayEveAudio(
                dropAssistantOutput: false,
                clientTTSInFlight: true
            ),
            "identity write→player must not mix Eve deltas"
        )
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldPlayEveAudio(
                dropAssistantOutput: false,
                clientTTSInFlight: false
            ),
            "later Eve turns still play"
        )
        XCTAssertTrue(
            LiveTalkMouth.firstAskDeskIdentityPlusEve().isDualMouth
        )
        XCTAssertFalse(
            LiveTalkMouth.firstAskDeskIdentityOnly().isDualMouth
        )

        let service = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        let playGate = speakSlice(
            service,
            from: "private func shouldPlayBargeAudio",
            to: "private func noteScheduledResponse"
        )
        XCTAssertTrue(
            playGate.contains("shouldPlayEveAudio"),
            "a2727b1 scheduled Eve deltas during identity write"
        )
        XCTAssertTrue(playGate.contains("dropAssistantTranscript"), playGate)
        XCTAssertTrue(playGate.contains("clientTTSInFlight"), playGate)
        XCTAssertFalse(playGate.contains("dropAssistantAudio"), playGate)

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
