import XCTest
@testable import VoiceDeskLogic

/// 83a5c6a hole: live VAD already created A; client stacked a verbatim
/// `response.create` (B) and spoke the list stub. Read-latest skipped
/// glance/gmail and first-audio was “Here they are.”
///
/// One ask → one Eve turn. Client owns cards, mic, tools. No synonym table.
/// Synonym families assert outcome, not wording.
final class LiveVADOneMouthTests: XCTestCase {
    static let readLatestFamily = [
        "read my latest email",
        "Read my latest email.",
        "read the latest one",
        "can you read my latest email",
        "Can you read my latest email?"
    ]

    static let liveDeskAsks = [
        "what's my version",
        "show me my emails",
        "Can you read my latest email?",
        "show me Murray's latest email"
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

    func testLiveVADPlusVerbatimStubIsTwoMouthsAndTheFixIsOne() {
        let walk = LiveTalkMouth.liveVADPlusVerbatimStub()
        XCTAssertTrue(walk.liveVADResponse)
        XCTAssertTrue(walk.sentVerbatimCreate)
        XCTAssertTrue(walk.skippedGlanceStubFirstAudio)
        XCTAssertTrue(
            walk.stacksSecondCreate,
            "83a5c6a stacked A (uncancelled VAD) + B (verbatim create)"
        )
        XCTAssertTrue(walk.isDualMouth)
        XCTAssertFalse(GrokRealtime.shouldSendVerbatimCreate(liveVADTurn: true))
        XCTAssertTrue(GrokRealtime.shouldSendVerbatimCreate(liveVADTurn: false))
        let eve = LiveTalkMouth.liveTalkEveOnly()
        XCTAssertTrue(eve.liveVADResponse)
        XCTAssertFalse(eve.sentVerbatimCreate)
        XCTAssertFalse(eve.stacksSecondCreate)
        XCTAssertFalse(eve.isDualMouth)
        XCTAssertFalse(eve.skippedGlanceStubFirstAudio)
    }

    func testLiveSpeakDoesNotSendSecondCreateOrClientStub() throws {
        let source = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        let speakFn = speakSlice(
            source,
            from: "func speak(_ text: String) async {",
            to: "private func returnToListenAfterDeskTTS"
        )
        XCTAssertTrue(speakFn.contains("shouldSpeakViaRealtime"), speakFn)
        XCTAssertFalse(
            speakFn.contains("speakLiveReplyViaEve"),
            "live VAD must not call speakLiveReplyViaEve"
        )
        XCTAssertFalse(
            speakFn.contains("responseCreateObject"),
            "live VAD must not send a second response.create"
        )
        XCTAssertFalse(speakFn.contains("verbatimSpeakSessionUpdateObject"), speakFn)
        XCTAssertFalse(speakFn.contains("textItemObject"), speakFn)
        XCTAssertTrue(speakFn.contains("ClientVoiceSpeech.shared.speak"), speakFn)
        XCTAssertFalse(source.contains("private func speakLiveReplyViaEve"), source)
        XCTAssertFalse(source.contains("restorePresenceAfterEveSpeak"), source)

        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        let desk = speakSlice(app, from: "private func speakDeskReply", to: "private func rememberUserTurn")
        XCTAssertTrue(desk.contains("isLiveVADTurn"), desk)
        XCTAssertTrue(desk.contains("return"), desk)
        XCTAssertFalse(desk.contains("Here they are"), desk)

        let glance = speakSlice(app, from: "private func applyInboxGlance", to: "private func appendThinkingBeat")
        XCTAssertTrue(glance.contains("InboxGlanceSpeakPlan.liveVAD"), glance)
        XCTAssertTrue(glance.contains("glanceInbox"), glance)

        let live = speakSlice(
            app,
            from: "if ConversationPresence.ownsConnectedDeskTurn",
            to: "unmuteGrokAssistant()\n        pendingDeskTopic"
        )
        XCTAssertTrue(live.contains("unmuteGrokAssistant()"), live)
        XCTAssertFalse(
            live.contains("deskWritesIdentity"),
            "version claimLocal was the Eve cut + second mouth"
        )
        let inbox = speakSlice(
            live,
            from: "if yieldGrokInterruptAnswer",
            to: "if let evidence = ConversationPresence.deskEvidence"
        )
        XCTAssertTrue(inbox.contains("unmuteGrokAssistant()"), inbox)
        XCTAssertFalse(
            inbox.contains("claimLocalAssistantReply()"),
            "claimLocal drops in-flight Eve audio on a live VAD inbox turn"
        )
    }

    func testReadLatestFamilyDoesNotSkipToolsOrSpeakListStub() {
        let snapshot = hotSnapshot
        XCTAssertEqual(
            GoogleSyncPolicy.cacheAgeSeconds(lastSyncedAt: snapshot.lastSyncedAt, now: now),
            52
        )
        let walkAsk = "Can you read my latest email?"
        let cacheWalk = InboxGlanceSpeakPlan.cacheHot(ask: walkAsk, snapshot: snapshot, now: now)
        XCTAssertTrue(
            InboxGlanceSpeakPlan.isSkippedGlanceListStub(cacheWalk),
            "83a5c6a cache-hot first-audio on the walk ask: \(cacheWalk.spokenText) \(cacheWalk.voiceLogNotes)"
        )
        for ask in Self.readLatestFamily {
            if ask.localizedCaseInsensitiveContains("email") {
                XCTAssertTrue(
                    InboxGlanceSpeakPlan.shouldRefreshGmailListBeforeFirstSpeak(
                        ask: ask,
                        snapshot: snapshot,
                        isConnected: true,
                        isOnline: true,
                        liveVADTurn: true
                    ),
                    "\(ask) live VAD must not skip gmailList"
                )
            }

            let plan = InboxGlanceSpeakPlan.liveVAD(ask: ask, snapshot: snapshot, now: now)
            XCTAssertFalse(
                InboxGlanceSpeakPlan.isSkippedGlanceListStub(plan),
                "\(ask) live first-audio must not be the list stub"
            )
            XCTAssertFalse(plan.voiceLogNotes.contains("firstAudio skipped xaiGlance"), ask)
            XCTAssertFalse(plan.voiceLogNotes.contains("firstAudio skipped gmailList"), ask)
            XCTAssertTrue(plan.waitsOnGmailList, ask)
            XCTAssertTrue(plan.waitsOnModel, ask)
            XCTAssertTrue(plan.stagesBeforeFirstAudio.contains(InboxGlanceSpeakPlan.gmailListStage), ask)
            XCTAssertTrue(plan.stagesBeforeFirstAudio.contains(InboxGlanceSpeakPlan.xaiGlanceStage), ask)
            XCTAssertEqual(plan.spokenSource, InboxGlanceSpeakPlan.eveSpokenSource, ask)
            XCTAssertTrue(plan.spokenText.isEmpty, "\(ask) Eve speaks — no client first-audio")
            XCTAssertFalse(InboxGlance.isShortSpokenAck(plan.spokenText), ask)
            XCTAssertNotEqual(plan.spokenText, InboxGlance.spokenListAck(), ask)
            XCTAssertGreaterThan(plan.cardCount, 0, ask)
            XCTAssertTrue(plan.voiceLogNotes.contains("cacheAgeSec=52"), ask)
        }
    }

    func testLiveDeskAsksDoNotGetAClientStubAsFirstAudio() {
        let snapshot = hotSnapshot
        for ask in Self.liveDeskAsks {
            XCTAssertFalse(
                GrokRealtime.shouldSendVerbatimCreate(liveVADTurn: true),
                ask
            )
            if ConversationPresence.looksLikeMailAsk(ask)
                || ConversationPresence.wantsInboxOverview(ask) {
                let plan = InboxGlanceSpeakPlan.liveVAD(ask: ask, snapshot: snapshot, now: now)
                XCTAssertNotEqual(plan.spokenText, InboxGlance.spokenListAck(), ask)
                XCTAssertFalse(InboxGlanceSpeakPlan.isSkippedGlanceListStub(plan), ask)
            }
        }
    }

    func testPresenceLetsEveAnswerDeskTurns() {
        let text = GrokRealtime.presenceInstructions(
            for: DeskContext(isConnected: true, snapshot: hotSnapshot),
            identity: .fixture
        )
        XCTAssertTrue(text.contains("you speak the answer"), text)
        XCTAssertTrue(text.contains("in your own words"), text)
        XCTAssertTrue(text.contains("Build identity"), text)
        XCTAssertFalse(text.contains("stay silent"), text)
        XCTAssertFalse(text.contains("Stay silent"), text)
        XCTAssertFalse(text.contains("NEVER say you are searching"), text)
        XCTAssertFalse(text.contains("Here they are."), text)
        XCTAssertFalse(text.contains("I'm checking"), text)
        XCTAssertFalse(text.contains("I don’t know"), text)
        XCTAssertTrue(text.contains("let the app handle"), text)
        let facts = GrokRealtime.connectedDeskFacts(hotSnapshot)
        XCTAssertFalse(facts.contains("stay silent"), facts)
        XCTAssertTrue(facts.contains("You speak the answer"), facts)
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
