import XCTest
@testable import VoiceDeskLogic

/// 4f4f4da first ask after a new session: desk identity write→player
/// AND Eve A both speak. Later turns are Eve-only and stay that way.
final class FirstAskOneMouthTests: XCTestCase {
    func testFirstAskDeskPlusEveIsTwoMouthsAndFixIsDeskOnly() {
        let hole = LiveTalkMouth.firstAskDeskIdentityPlusEve()
        XCTAssertTrue(hole.liveVADResponse)
        XCTAssertTrue(hole.clientVoiceSpeechWrite)
        XCTAssertTrue(hole.eveVoicePath)
        XCTAssertFalse(hole.sentVerbatimCreate)
        XCTAssertTrue(
            hole.isDualMouth,
            "4f4f4da wrote identity while Eve A still spoke"
        )

        let keep = LiveTalkMouth.firstAskDeskIdentityOnly()
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
