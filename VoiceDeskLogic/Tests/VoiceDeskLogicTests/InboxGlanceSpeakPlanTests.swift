import XCTest
@testable import VoiceDeskLogic

/// Live tape 2026-08-25, SHA be0b4c8 (VoiceDesk 0.1 build 6):
/// “Show me my emails for the day” / “Show me my most recent email”
/// → inbox-overview, 5 cards, cacheAgeSec=9, felt slow.
///
/// Mail was already cached. First audio must start from the local snapshot
/// immediately — no Gmail list wait, no xAI 5-line rewrite.
///
/// Synonym families, not one golden phrase. Assert intent / timing / source
/// of first speak — never Eve’s exact wording.
final class InboxGlanceSpeakPlanTests: XCTestCase {
    static let glanceFamily = [
        "Show me my emails for the day",
        "show me my emails for the day",
        "Tell me my emails for the day.",
        "tell me my emails",
        "Tell me my emails.",
        "show me my most recent emails",
        "Show me my most recent email",
        "show me my most recent email",
        "emails for the day",
        "um show me my emails for the day",
        "uh tell me my emails",
        "how about my emails",
        "okay, show me my most recent emails"
    ]

    private var now: Date {
        Date(timeIntervalSince1970: 1_777_000_000)
    }

    private var hotSnapshot: DeskSnapshot {
        DeskSnapshot(
            accountEmail: "agent@example.com",
            lastSyncedAt: now.addingTimeInterval(-9),
            emails: [
                VoiceRegressionDesk.greenacre,
                VoiceRegressionDesk.murray,
                VoiceRegressionDesk.steve,
                VoiceRegressionDesk.laren,
                VoiceRegressionDesk.ericGross
            ]
        )
    }

    func testCacheHotGlanceFamilySpeaksLocalHeuristicWithoutListOrModelWait() {
        let snapshot = hotSnapshot
        XCTAssertEqual(snapshot.glanceEmails.count, InboxGlance.overviewLimit)
        XCTAssertEqual(
            GoogleSyncPolicy.cacheAgeSeconds(lastSyncedAt: snapshot.lastSyncedAt, now: now),
            9
        )
        XCTAssertTrue(InboxGlanceSpeakPlan.hasHotLatestFive(snapshot))

        let hanging = HangingInboxGlancer()
        for ask in Self.glanceFamily {
            XCTAssertTrue(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertFalse(
                InboxGlanceSpeakPlan.shouldRefreshGmailListBeforeFirstSpeak(
                    ask: ask,
                    snapshot: snapshot,
                    isConnected: true,
                    isOnline: true
                ),
                ask
            )

            let plan = InboxGlanceSpeakPlan.cacheHot(ask: ask, snapshot: snapshot, now: now)
            XCTAssertEqual(hanging.glanceCalls, 0, "\(ask) must not touch a glancer")
            XCTAssertEqual(plan.intent, "inbox-overview", ask)
            XCTAssertEqual(plan.spokenSource, InboxGlanceSpeakPlan.localHeuristicSource, ask)
            XCTAssertFalse(plan.waitsOnGmailList, ask)
            XCTAssertFalse(plan.waitsOnModel, ask)
            XCTAssertFalse(
                InboxGlanceSpeakPlan.firstAudioWaitsOnGmailList(plan.stagesBeforeFirstAudio),
                ask
            )
            XCTAssertFalse(
                InboxGlanceSpeakPlan.firstAudioWaitsOnModel(plan.stagesBeforeFirstAudio),
                ask
            )
            XCTAssertEqual(
                plan.stagesBeforeFirstAudio,
                [InboxGlanceSpeakPlan.localCacheStage, InboxGlanceSpeakPlan.heuristicStage],
                ask
            )
            XCTAssertFalse(plan.stagesBeforeFirstAudio.contains(InboxGlanceSpeakPlan.gmailListStage), ask)
            XCTAssertFalse(plan.stagesBeforeFirstAudio.contains(InboxGlanceSpeakPlan.xaiGlanceStage), ask)
            XCTAssertEqual(plan.cardCount, InboxGlance.overviewLimit, ask)
            XCTAssertNotEqual(plan.spokenText, "Here they are.", ask)
            XCTAssertFalse(plan.spokenText.localizedCaseInsensitiveContains("here they are"), ask)
            XCTAssertTrue(
                plan.spokenText.isEmpty
                    || InboxGlance.isShortSpokenSummary(plan.spokenText),
                "\(ask) → \(plan.spokenText)"
            )
            XCTAssertFalse(InboxGlance.isMultiline(plan.spokenText), ask)
            XCTAssertFalse(plan.spokenText.contains("—"), ask)
            if plan.spokenText.isEmpty {
                XCTAssertNil(DeskReplySpeech.textToSpeak(plan.spokenText, lastSpoken: nil), ask)
            } else {
                XCTAssertNotNil(DeskReplySpeech.textToSpeak(plan.spokenText, lastSpoken: nil), ask)
            }
            XCTAssertTrue(plan.voiceLogNotes.contains("firstAudio skipped xaiGlance"), ask)
            XCTAssertTrue(plan.voiceLogNotes.contains("firstAudio skipped gmailList"), ask)
            XCTAssertTrue(plan.voiceLogNotes.contains("cacheAgeSec=9"), ask)
        }
        XCTAssertEqual(hanging.glanceCalls, 0)
    }

    func testCacheHotPlanDoesNotAwaitHangingGlancer() async {
        let snapshot = hotSnapshot
        let hanging = HangingInboxGlancer()
        let plan = InboxGlanceSpeakPlan.cacheHot(
            ask: "Show me my emails for the day",
            snapshot: snapshot,
            now: now
        )
        XCTAssertEqual(hanging.glanceCalls, 0)
        XCTAssertFalse(plan.waitsOnModel)
        XCTAssertEqual(plan.spokenSource, InboxGlanceSpeakPlan.localHeuristicSource)

        let polish = Task { await hanging.glance(snapshot.glanceEmails) }
        await waitUntil { hanging.glanceCalls == 1 }
        XCTAssertFalse(plan.spokenText.contains("cloud polish"))
        hanging.fail()
        _ = await polish.value
        XCTAssertEqual(plan.spokenSource, InboxGlanceSpeakPlan.localHeuristicSource)
    }

    func testEmptySnapshotStillAllowsGmailListBeforeFirstSpeak() {
        let empty = DeskSnapshot(
            accountEmail: "agent@example.com",
            lastSyncedAt: now.addingTimeInterval(-9),
            emails: []
        )
        XCTAssertFalse(InboxGlanceSpeakPlan.hasHotLatestFive(empty))
        XCTAssertTrue(
            InboxGlanceSpeakPlan.shouldRefreshGmailListBeforeFirstSpeak(
                ask: "show me my emails",
                snapshot: empty,
                isConnected: true,
                isOnline: true
            )
        )
        XCTAssertFalse(
            InboxGlanceSpeakPlan.shouldRefreshGmailListBeforeFirstSpeak(
                ask: "show me my emails",
                snapshot: empty,
                isConnected: true,
                isOnline: false
            )
        )
        XCTAssertFalse(
            InboxGlanceSpeakPlan.shouldRefreshGmailListBeforeFirstSpeak(
                ask: "what's on my calendar",
                snapshot: empty,
                isConnected: true,
                isOnline: true
            )
        )
    }

    func testNamedSenderAndLastCardStayOutOfGlanceFirstSpeak() {
        let snapshot = hotSnapshot
        for ask in [
            "show me the email from Murray",
            "summarize Murray's last email",
            "The last one."
        ] {
            XCTAssertFalse(ConversationPresence.wantsInboxOverview(ask), ask)
            XCTAssertFalse(
                InboxGlanceSpeakPlan.shouldRefreshGmailListBeforeFirstSpeak(
                    ask: ask,
                    snapshot: snapshot,
                    isConnected: true,
                    isOnline: true
                ),
                ask
            )
            let plan = InboxGlanceSpeakPlan.cacheHot(ask: ask, snapshot: snapshot, now: now)
            XCTAssertNotEqual(plan.intent, "inbox-overview", ask)
        }
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<40 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out")
    }
}

/// Never resumes unless `fail()` is called — proves firstAudio is not gated on it.
final class HangingInboxGlancer: InboxGlancing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var glanceCalls = 0

    func glance(_ emails: [EmailItem]) async -> String {
        _ = emails
        return await withCheckedContinuation { continuation in
            lock.lock()
            glanceCalls += 1
            self.continuation = continuation
            lock.unlock()
        }
    }

    func fail() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: "")
    }
}
