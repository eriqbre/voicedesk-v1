import XCTest
@testable import VoiceDeskLogic

/// Large pending-clarify matrix. After “I found a few matches. Which one?” every
/// follow-up below must stay desk-owned and never yield to live Grok.
final class ClarifyPickTests: XCTestCase {
    private var older: EmailItem { murray(id: "old", subject: "Old walk-through", label: "Yesterday 4:00 PM") }
    private var middle: EmailItem { murray(id: "mid", subject: "Closing / notarization", label: "Today 9:00 AM") }
    private var newest: EmailItem { murray(id: "new", subject: "Walk-through today", label: "Today 2:00 PM") }
    private var matches: [EmailItem] { [older, middle, newest] }

    /// Phrase → expected providerID. Newest = `new`. Ordinals use offered-card order.
    static let deskPickMatrix: [(phrase: String, providerID: String, reason: String)] = [
        ("The last one.", "new", "newest"),
        ("the last one", "new", "newest"),
        ("last one", "new", "newest"),
        ("the last", "new", "newest"),
        ("last", "new", "newest"),
        ("the latest", "new", "newest"),
        ("latest", "new", "newest"),
        ("The most recent one.", "new", "newest"),
        ("most recent", "new", "newest"),
        ("the most recent one", "new", "newest"),
        ("the newest", "new", "newest"),
        ("newest one", "new", "newest"),
        ("that one", "new", "newest"),
        ("that", "new", "newest"),
        ("yeah that", "new", "newest"),
        ("this one", "new", "newest"),
        ("the top one", "new", "newest"),
        ("number one", "old", "ordinal 0"),
        ("the first one", "old", "ordinal 0"),
        ("the first", "old", "ordinal 0"),
        ("the second one", "mid", "ordinal 1"),
        ("the second", "mid", "ordinal 1"),
        ("the third one", "new", "ordinal 2"),
        ("uh the last one", "new", "filler + last"),
        ("yeah the latest", "new", "filler + latest"),
        ("ok that", "new", "filler + that"),
        ("mm hmm", "new", "short leftover default"),
        ("okay", "new", "filler-only default")
    ]

    func testClarifyFamilyPicksExpectedCardNotGrok() {
        for row in Self.deskPickMatrix {
            XCTAssertTrue(ConversationPresence.isClarifyPick(row.phrase), "\(row.phrase) (\(row.reason))")
            XCTAssertFalse(ConversationPresence.wantsInboxOverview(row.phrase), row.phrase)
            XCTAssertFalse(ConversationPresence.ownsConnectedDeskTurn(row.phrase), row.phrase)
            XCTAssertTrue(
                ConversationPresence.ownsConnectedDeskTurn(
                    row.phrase,
                    pendingSearchClarify: true,
                    hasClarifyMatches: true
                ),
                row.phrase
            )
            XCTAssertEqual(
                ConversationPresence.pickClarifiedEmail(ask: row.phrase, candidates: matches)?.providerID,
                row.providerID,
                "\(row.phrase) → \(row.reason)"
            )

            let evidence = ConversationPresence.deskEvidence(
                for: row.phrase,
                context: DeskContext(isConnected: true, snapshot: .empty),
                pendingSearchClarify: true,
                clarifyMatches: matches
            )
            XCTAssertEqual(evidence?.focusedEmail?.providerID, row.providerID, row.phrase)
            XCTAssertNotEqual(evidence?.shouldSearchGmail, true, row.phrase)
            XCTAssertFalse(ConversationPresence.isGrokDeskMeta(evidence?.text ?? ""), row.phrase)
            XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("client will jump"), row.phrase)
            XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("ios app"), row.phrase)

            let replay = VoiceTurnReplay.play(
                utterance: row.phrase,
                context: VoiceRegressionDesk.greenacreOnly,
                pendingSearchClarify: true,
                clarifyMatches: matches
            )
            XCTAssertTrue(replay.ownsDeskTurn, row.phrase)
            XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), "\(row.phrase) → \(replay.intent)")
            XCTAssertNotEqual(replay.intent, "general", "\(row.phrase) must not yield to live Grok")
            XCTAssertEqual(replay.evidence?.focusedEmail?.providerID, row.providerID, row.phrase)
            XCTAssertFalse(replay.notes.contains("live Grok"), "\(row.phrase) → \(replay.notes)")
        }
    }

    func testNamedSenderAndRealQuestionsAreNotClarifyPicks() {
        XCTAssertFalse(ConversationPresence.isClarifyPick("Show me the most recent email by showing time."))
        XCTAssertFalse(ConversationPresence.isClarifyPick("Give me a summary of Murray's last email."))
        XCTAssertFalse(ConversationPresence.isClarifyPick("What's for dinner?"))
        XCTAssertFalse(ConversationPresence.isClarifyPick("What's the latest on my calendar?"))
        XCTAssertFalse(
            ConversationPresence.ownsConnectedDeskTurn(
                "What's for dinner?",
                pendingSearchClarify: true,
                hasClarifyMatches: true
            )
        )
        XCTAssertNil(
            ConversationPresence.pickClarifiedEmail(ask: "What's for dinner?", candidates: matches)
        )
        let dinner = VoiceTurnReplay.play(
            utterance: "What's for dinner?",
            context: VoiceRegressionDesk.greenacreOnly,
            pendingSearchClarify: true,
            clarifyMatches: matches
        )
        XCTAssertEqual(dinner.intent, "general")
        XCTAssertFalse(dinner.ownsDeskTurn)
    }

    func testMurraySeveralSnapshotLastOneIsNewestNotLiveGrok() {
        let replay = VoiceTurnReplay.play(
            utterance: "The last one.",
            context: DeskContext(isConnected: true, snapshot: VoiceRegressionDesk.murraySeveralSnapshot),
            pendingSearchClarify: true,
            clarifyMatches: VoiceRegressionDesk.murraySeveralMatches
        )
        XCTAssertEqual(replay.evidence?.focusedEmail?.providerID, "fixture-murray-new")
        XCTAssertNotEqual(replay.intent, "general")
        XCTAssertTrue(replay.cardLabels.contains { $0.contains("Walk-through today") }, "\(replay.cardLabels)")
    }

    private func murray(id: String, subject: String, label: String) -> EmailItem {
        EmailItem(
            providerID: id,
            fromName: "Murray Mitchell",
            fromEmail: "murray@example.com",
            sentAtLabel: label,
            subject: subject,
            preview: subject,
            body: "Murray body for \(subject).",
            filterTag: "Inbox"
        )
    }
}
