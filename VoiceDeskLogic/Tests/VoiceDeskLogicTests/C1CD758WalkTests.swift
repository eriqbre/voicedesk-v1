import XCTest
@testable import VoiceDeskLogic

/// Device walk 16:45:39–16:48:25Z on c1cd758 (last 6 jsonl records).
/// Version logged `eve speaks identity` with empty assistantReply and
/// no write→player. 83a5c6a spoke “VoiceDesk point 1, build 6.”
/// Also: first-delta voice cut; show-latest cards missing (Eriq).
final class C1CD758WalkTests: XCTestCase {
    func testWalkLastSixVersionIsEmptyEveSpeaksIdentityLie() throws {
        let records = C1CD758Walk.lastSix
        XCTAssertEqual(records.count, 6)
        XCTAssertEqual(records[0].intent, ListenResumeLog.intent)
        XCTAssertTrue(records[0].routingNotes[0].contains("audio.start"), records[0].routingNotes[0])
        XCTAssertTrue(records[0].assistantReply.isEmpty)

        let version = try XCTUnwrap(C1CD758Walk.versionTurn(in: records))
        XCTAssertEqual(version.userTranscript, C1CD758Walk.versionAsk)
        XCTAssertEqual(version.intent, "version")
        XCTAssertTrue(version.routingNotes.contains(C1CD758Walk.versionIdentityNote), "\(version.routingNotes)")
        XCTAssertTrue(version.routingNotes.contains(where: { $0.contains("0.1.0 build 6 sha c1cd758") }))
        XCTAssertTrue(version.assistantReply.isEmpty, "walk assistantReply was empty")
        XCTAssertEqual(version.cardsAttached, [])
        XCTAssertTrue(
            C1CD758Walk.isEmptyEveSpeaksIdentity(version),
            "c1cd758 version: eve speaks identity + empty reply + no PCM"
        )
        XCTAssertTrue(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: version.routingNotes,
                assistantReply: version.assistantReply,
                wrotePlayerPCM: false
            )
        )

        let close = records[5]
        XCTAssertEqual(close.intent, ListenResumeLog.intent)
        XCTAssertTrue(close.routingNotes[0].contains("session close code=1000"), close.routingNotes[0])
        XCTAssertTrue(close.routingNotes[0].contains("stayLive=false"), close.routingNotes[0])
    }

    func testFixWritesIdentityToPlayerNotEmptyEveLie() {
        let identity = ConversationPresence.spokenIdentityLine(
            for: C1CD758Walk.versionAsk,
            identity: .fixture
        )
        XCTAssertEqual(identity, C1CD758Walk.spokenIdentity83a5c6a)
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: identity,
                identityLine: identity
            ),
            "live VAD desk write is a second mouth; Eve speaks identity"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: InboxGlance.spokenListAck(),
                identityLine: identity
            ),
            "do not write the list stub"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: "",
                identityLine: identity
            )
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
                routingNotes: ["local build identity", BuildIdentity.fixture.dogfoodLine],
                assistantReply: identity,
                wrotePlayerPCM: false
            )
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true
            )
        )
        let cards = LiveVADPlayerKeep.oneMouthFullReply(cardCount: 5)
        XCTAssertFalse(cards.isCardlessBlob)
        XCTAssertTrue(cards.remainingDeltasReachPlayer)
        XCTAssertFalse(LiveVADPlayerKeep.c1cd758Regression().remainingDeltasReachPlayer)
    }

    func testShowLatestIsNotACardlessBlob() {
        let snapshot = DeskSnapshot(
            accountEmail: "agent@example.com",
            lastSyncedAt: Date(timeIntervalSince1970: 1_777_000_000).addingTimeInterval(-52),
            emails: [
                VoiceRegressionDesk.greenacre,
                VoiceRegressionDesk.murray,
                VoiceRegressionDesk.steve,
                VoiceRegressionDesk.laren,
                VoiceRegressionDesk.ericGross
            ]
        )
        for ask in ["show my latest emails", "Show me my latest emails.", "okay show me my latest emails"] {
            let evidence = ConversationPresence.deskEvidence(
                for: ask,
                context: DeskContext(isConnected: true, snapshot: snapshot)
            )
            XCTAssertGreaterThan(evidence?.cards.count ?? 0, 0, ask)
            XCTAssertTrue(evidence?.shouldGlanceInbox == true, ask)
            XCTAssertFalse(
                LiveVADPlayerKeep.oneMouthFullReply(cardCount: evidence?.cards.count ?? 0).isCardlessBlob,
                ask
            )
        }
    }

    func testProductionNoLongerLogsEmptyEveSpeaksIdentityOrSkipsWritePlayer() throws {
        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        let version = speakSlice(
            app,
            from: "if evidence.topic == .version",
            to: "if evidence.shouldSearchGmail"
        )
        XCTAssertTrue(version.contains("spokenIdentityLine"), version)
        XCTAssertTrue(version.contains("speakDeskReply(line)"), version)
        XCTAssertTrue(version.contains("appendAssistant(line)"), version)
        XCTAssertTrue(version.contains("local build identity"), version)
        XCTAssertFalse(
            version.contains("claimLocalAssistantReply()"),
            "claimLocal cuts Eve mid-answer — a2727b1 voice-cut"
        )
        XCTAssertFalse(
            version.contains("eve speaks identity"),
            "c1cd758 logged eve speaks identity with empty assistantReply"
        )
        XCTAssertFalse(version.contains("reply: \"\""), version)

        let desk = speakSlice(app, from: "private func speakDeskReply(_ text: String) async", to: "private func rememberUserTurn")
        XCTAssertTrue(desk.contains("if isLiveVADTurn"), desk)
        XCTAssertTrue(desk.contains("await voice.speak"), desk)
        if let liveAt = desk.range(of: "if isLiveVADTurn"),
           let helperAt = desk.range(of: "liveVersionAsk.speakDeskReply") {
            let liveBranch = String(desk[liveAt.lowerBound..<helperAt.lowerBound])
            XCTAssertTrue(
                liveBranch.contains("await voice.speak"),
                "live VAD must call voice.speak before the helper"
            )
            XCTAssertTrue(liveBranch.contains("return"), liveBranch)
        } else {
            XCTFail("live VAD speakDeskReply must call voice.speak; helper is typed only")
        }
        XCTAssertFalse(desk.contains("Here they are"), desk)
        let seam = try XCTUnwrap(repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/LiveVersionAsk.swift"))
        XCTAssertTrue(seam.contains("shouldWriteLiveDeskLineToPlayer"), seam)
        XCTAssertTrue(seam.contains("spokenIdentityLine"), seam)
        XCTAssertTrue(seam.contains("func handleLiveUser"), seam)
        XCTAssertTrue(seam.contains("func speakDeskReply"), seam)

        let service = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        let speakFn = speakSlice(
            service,
            from: "func speak(_ text: String) async {",
            to: "private func returnToListenAfterDeskTTS"
        )
        XCTAssertTrue(speakFn.contains("LiveEveSpeak.plan"), speakFn)
        XCTAssertTrue(speakFn.contains("ClientVoiceSpeech.shared.speak"), speakFn)
        XCTAssertTrue(speakFn.contains("playPCM16"), speakFn)
        XCTAssertTrue(
            LiveVADPlayerKeep.c1cd758Regression().voiceCutsAfterFirstDelta,
            "c1cd758 walk: first delta then silence after interrupt with no mouth"
        )
        let speakTests = try XCTUnwrap(repoFile("VoiceDeskTests/GrokVoiceServiceSpeakTests.swift"))
        XCTAssertTrue(
            speakTests.contains("testInFlightVADSpeakInterruptsBeforeCreateAndDoesNotStarveEve"),
            speakTests
        )

        let handle = speakSlice(app, from: "private func handleLiveUser", to: "private func upsertLiveAssistant")
        XCTAssertTrue(handle.contains("shouldInterruptOnUserTranscript"), handle)
        XCTAssertTrue(handle.contains("parkLiveVADDeskCards") || handle.contains("parkOrAttachLiveDeskCards"), handle)
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
