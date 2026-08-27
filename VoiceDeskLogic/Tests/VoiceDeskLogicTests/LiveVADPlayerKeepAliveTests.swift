import XCTest
@testable import VoiceDeskLogic

/// c1cd758 hole vs 83a5c6a: after the first output_audio.delta, same-turn
/// interruptResponse cancelled A. No second create. Voice quit. Glance
/// cards never landed on the streaming turn (blob). Prefetch
/// session.update mid-A stalled printed transcripts.
///
/// One mouth: keep A's PCM on the player. Cards on first delta.
/// Stream text as it arrives. No client “Here they are.” first audio.
final class LiveVADPlayerKeepAliveTests: XCTestCase {
    static let showLatestFamily = [
        "show-latest-emails",
        "show my latest emails",
        "Show me my latest emails.",
        "okay show me my latest emails"
    ]

    private var now: Date {
        Date(timeIntervalSince1970: 1_777_000_000)
    }

    private var hotSnapshot: DeskSnapshot {
        DeskSnapshot(
            accountEmail: "agent@example.com",
            lastSyncedAt: now.addingTimeInterval(-52),
            emails: [
                VoiceRegressionDesk.greenacre,
                VoiceRegressionDesk.murray,
                VoiceRegressionDesk.steve,
                VoiceRegressionDesk.laren,
                VoiceRegressionDesk.ericGross
            ]
        )
    }

    func testC1cd758CutsVoiceAfterFirstDeltaAndFixKeepsPlayer() {
        let hole = LiveVADPlayerKeep.c1cd758Regression()
        XCTAssertTrue(hole.firstDeltaOnPlayer)
        XCTAssertTrue(hole.sameTurnInterruptCancelledFirstAnswer)
        XCTAssertFalse(hole.sentSecondCreate)
        XCTAssertTrue(
            hole.voiceCutsAfterFirstDelta,
            "c1cd758 latched A cancelled after the first delta; no B"
        )
        XCTAssertFalse(hole.remainingDeltasReachPlayer)
        XCTAssertTrue(hole.isCardlessBlob)
        XCTAssertTrue(hole.dumpsTranscriptLate)
        XCTAssertFalse(hole.isOneMouthFullReply)

        let keep = LiveVADPlayerKeep.oneMouthFullReply(cardCount: 5)
        XCTAssertFalse(keep.sameTurnInterruptCancelledFirstAnswer)
        XCTAssertFalse(keep.sentSecondCreate)
        XCTAssertFalse(keep.voiceCutsAfterFirstDelta)
        XCTAssertTrue(keep.remainingDeltasReachPlayer)
        XCTAssertFalse(keep.isCardlessBlob)
        XCTAssertFalse(keep.dumpsTranscriptLate)
        XCTAssertTrue(keep.isOneMouthFullReply)
    }

    func testSameTurnFirstAnswerMustNotBeInterrupted() {
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: true
            ),
            "first-answer PCM on the player is the one mouth"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: true,
                hasPendingPlayback: true
            ),
            "speech_started already dropped leftover"
        )
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldInterruptOnUserTranscript(
                alreadyBarged: false,
                hasPendingPlayback: false
            )
        )
    }

    func testPresenceUpdateWaitsUntilIdleAndTranscriptsAreNotBuffered() {
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldSendPresenceSessionUpdate(responseInFlight: true),
            "session.update mid-A cut voice and stalled print"
        )
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldSendPresenceSessionUpdate(responseInFlight: false)
        )
        XCTAssertFalse(LiveVADPlayerKeep.shouldBufferTranscriptUntilToolsFinish())
        XCTAssertTrue(
            LiveVADPlayerKeep.shouldAttachCardsOnFirstTranscriptDelta(liveVADTurn: true)
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldAttachCardsOnFirstTranscriptDelta(liveVADTurn: false)
        )
    }

    func testShowLatestFamilyGetsCardsNotABlob() {
        let snapshot = hotSnapshot
        for ask in Self.showLatestFamily {
            XCTAssertTrue(
                ConversationPresence.wantsInboxOverview(ask)
                    || ask == "show-latest-emails",
                ask
            )
            let evidence = ConversationPresence.deskEvidence(
                for: ask == "show-latest-emails" ? "show my latest emails" : ask,
                context: DeskContext(isConnected: true, snapshot: snapshot)
            )
            XCTAssertNotNil(evidence, ask)
            XCTAssertTrue(evidence?.shouldGlanceInbox == true, ask)
            XCTAssertGreaterThan(evidence?.cards.count ?? 0, 0, "\(ask) must have cards")
            let surface = LiveVADPlayerKeep.oneMouthFullReply(
                cardCount: evidence?.cards.count ?? 0
            )
            XCTAssertFalse(surface.isCardlessBlob, ask)
            let plan = InboxGlanceSpeakPlan.liveVAD(ask: ask, snapshot: snapshot, now: now)
            XCTAssertTrue(plan.spokenText.isEmpty, ask)
            XCTAssertNotEqual(plan.spokenText, InboxGlance.spokenListAck(), ask)
            XCTAssertGreaterThan(plan.cardCount, 0, ask)
        }
    }

    func testLiveUserTranscriptDoesNotCancelFirstAnswerOrSessionUpdateMidReply() throws {
        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        let handleUser = speakSlice(
            app,
            from: "private func handleLiveUser",
            to: "private func upsertLiveAssistant"
        )
        XCTAssertTrue(
            handleUser.contains("LiveVADPlayerKeep.shouldInterruptOnUserTranscript"),
            "c1cd758 called interruptResponse after the first delta and killed A"
        )
        XCTAssertTrue(handleUser.contains("hasPendingPlayback"), handleUser)
        XCTAssertTrue(handleUser.contains("userDedupe.accept"), handleUser)
        if let acceptAt = handleUser.range(of: "userDedupe.accept"),
           let interruptAt = handleUser.range(of: "voice.interruptResponse()") {
            XCTAssertLessThan(acceptAt.lowerBound, interruptAt.lowerBound)
        } else {
            XCTFail("accept before gated interruptResponse")
        }
        XCTAssertTrue(
            handleUser.contains("parkLiveVADDeskCards")
                || handleUser.contains("parkOrAttachLiveDeskCards"),
            "cards must park before tools or show-latest is a blob"
        )
        XCTAssertTrue(handleUser.contains("appendUser(text)"), handleUser)
        if let userAt = handleUser.range(of: "appendUser(text)"),
           let fulfillAt = handleUser.range(of: "fulfillConnectedDeskTurn") {
            XCTAssertLessThan(
                userAt.lowerBound,
                fulfillAt.lowerBound,
                "user text must print before tools"
            )
        } else {
            XCTFail("appendUser before fulfill")
        }
        XCTAssertFalse(
            handleUser.contains("deskWritesIdentity"),
            "version claimLocal cut Eve; inbox and version both leave her the mouth"
        )
        XCTAssertFalse(handleUser.contains("Here they are"), handleUser)

        let upsert = speakSlice(
            app,
            from: "private func upsertLiveAssistant",
            to: "private func parkLiveVADDeskCards"
        )
        XCTAssertTrue(
            upsert.contains("attachLiveDeskCardsIfNeeded"),
            "cards on first delta, not only isFinal"
        )
        if let attachAt = upsert.range(of: "attachLiveDeskCardsIfNeeded"),
           let finalAt = upsert.range(of: "if isFinal") {
            XCTAssertLessThan(
                attachAt.lowerBound,
                finalAt.lowerBound,
                "c1cd758 waited for isFinal — blob until tools finished"
            )
        }

        let glance = speakSlice(
            app,
            from: "private func applyInboxGlance",
            to: "private func appendThinkingBeat"
        )
        XCTAssertTrue(glance.contains("parkOrAttachLiveDeskCards"), glance)
        XCTAssertTrue(glance.contains("isLiveVADTurn"), glance)
        if let liveAt = glance.range(of: "if isLiveVADTurn") {
            let liveSlice = String(glance[liveAt.lowerBound...])
            XCTAssertTrue(
                liveSlice.contains("parkOrAttachLiveDeskCards"),
                "live glance must attach to the stream, not a second blob"
            )
        }
        XCTAssertFalse(glance.contains("Here they are"), glance)

        let service = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        let presence = speakSlice(
            service,
            from: "func updatePresenceInstructions",
            to: "func interruptResponse"
        )
        XCTAssertTrue(
            presence.contains("LiveVADPlayerKeep.shouldSendPresenceSessionUpdate"),
            "c1cd758 sent session.update mid-A from prefetch refreshPresence"
        )
        XCTAssertTrue(presence.contains("isLiveResponseInFlight"), presence)
        XCTAssertTrue(presence.contains("pendingPresenceSessionUpdate"), presence)
        let speakFn = speakSlice(
            service,
            from: "func speak(_ text: String) async {",
            to: "private func returnToListenAfterDeskTTS"
        )
        XCTAssertTrue(service.contains("verbatimSpeakResponseID"), service)
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
