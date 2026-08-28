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
        XCTAssertTrue(LiveVADPlayerKeep.c1cd758Regression().voiceCutsAfterFirstDelta)
        XCTAssertFalse(
            LiveVADPlayerKeep.oneMouthFullReply(cardCount: 3).voiceCutsAfterFirstDelta
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: "Here they are.",
                identityLine: "VoiceDesk point 1, build 6."
            )
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
        XCTAssertFalse(
            InboxGlanceSpeakPlan.isSkippedGlanceListStub(cacheWalk),
            "83a5c6a cache-hot first-audio was Here they are.: \(cacheWalk.spokenText) \(cacheWalk.voiceLogNotes)"
        )
        XCTAssertNotEqual(cacheWalk.spokenText, "Here they are.")
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
            XCTAssertFalse(
                InboxGlance.isFromSubjectGlanceDump(plan.spokenText),
                "677abb9 \(ask) glance-then-cards mouth: \(plan.spokenText)"
            )
            XCTAssertNotEqual(
                plan.spokenText,
                InboxGlance.spokenInbox(ask: ask, emails: snapshot.emails),
                ask
            )
            XCTAssertFalse(InboxGlance.isShortSpokenAck(plan.spokenText), ask)
            XCTAssertNotEqual(plan.spokenText, "Here they are.", ask)
            XCTAssertGreaterThan(plan.cardCount, 0, ask)
            XCTAssertTrue(plan.voiceLogNotes.contains("cacheAgeSec=52"), ask)
        }
    }

    func testLiveDeskAsksDoNotGetAClientStubAsFirstAudio() {
        let snapshot = hotSnapshot
        for ask in Self.liveDeskAsks {
            let speak = LiveEveSpeak.plan(text: ask, socketConnected: true)
            XCTAssertEqual(speak.mouth, .eve, ask)
            XCTAssertEqual(speak.wireTypes, LiveEveSpeak.eveWireTypes, ask)
            XCTAssertFalse(speak.wroteClientTTS, ask)
            XCTAssertFalse(speak.swallowed, ask)
            if ConversationPresence.looksLikeMailAsk(ask)
                || ConversationPresence.wantsInboxOverview(ask) {
                let plan = InboxGlanceSpeakPlan.liveVAD(ask: ask, snapshot: snapshot, now: now)
                XCTAssertNotEqual(plan.spokenText, "Here they are.", ask)
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
        XCTAssertFalse(text.contains("you are checking"), text)
        XCTAssertFalse(text.contains("I don’t know"), text)
        XCTAssertFalse(text.contains("I don't know"), text)
        XCTAssertTrue(text.contains("wait in this same turn"), text)
        XCTAssertFalse(text.contains("let the app handle"), text)
        XCTAssertFalse(GrokRealtime.teachesLeftoverDeskRouting(text), text)
        XCTAssertFalse(GrokRealtime.teachesNoTools(text), text)
        XCTAssertFalse(text.contains("You have no tools"), text)
        XCTAssertFalse(text.contains("do not pretend to call functions"), text)
        let facts = GrokRealtime.connectedDeskFacts(hotSnapshot)
        XCTAssertFalse(facts.contains("stay silent"), facts)
        XCTAssertTrue(facts.contains("You speak the answer"), facts)
    }
}
