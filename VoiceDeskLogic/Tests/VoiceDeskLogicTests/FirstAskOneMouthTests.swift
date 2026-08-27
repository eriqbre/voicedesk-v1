import XCTest
@testable import VoiceDeskLogic

/// 4f4f4da / a2727b1 first ask: desk identity write→player AND Eve
/// live VAD PCM both reach the player. Unmute/claimLocal paper is
/// not the path. Later turns are Eve-only and stay that way.
final class FirstAskOneMouthTests: XCTestCase {
    func testFirstAskDeskPlusEveIsTwoMouthsAndFixIsDeskOnly() {
        let hole = LiveTalkMouth.firstAskDeskIdentityPlusEve()
        XCTAssertTrue(hole.afterDeskTTSDrain, "4f4f4da version logged after desk tts drain")
        XCTAssertTrue(hole.liveVADResponse)
        XCTAssertTrue(hole.clientVoiceSpeechWrite)
        XCTAssertTrue(hole.eveVoicePath)
        XCTAssertFalse(hole.sentVerbatimCreate)
        XCTAssertTrue(
            hole.isDualMouth,
            "5bcfbd7 / 4f4f4da: desk TTS drain + Eve"
        )
        let walkNotes = [
            "local build identity",
            "0.1.0 build 6 sha 4f4f4da",
            "after desk tts drain listenArmed=true stayLive=true"
        ]
        XCTAssertTrue(
            LiveTalkMouth.versionNotesAreDualMouth(
                routingNotes: walkNotes,
                eveAlsoSpoke: true
            ),
            "jsonl has no second firstAudio; both mouths were heard"
        )

        let keep = LiveTalkMouth.firstAskDeskIdentityOnly()
        XCTAssertTrue(keep.afterDeskTTSDrain)
        XCTAssertTrue(keep.clientVoiceSpeechWrite)
        XCTAssertFalse(keep.eveVoicePath)
        XCTAssertFalse(keep.sentVerbatimCreate)
        XCTAssertFalse(keep.isDualMouth)
        XCTAssertFalse(
            LiveTalkMouth.versionNotesAreDualMouth(
                routingNotes: walkNotes,
                eveAlsoSpoke: false
            )
        )
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
