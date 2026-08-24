import XCTest
@testable import VoiceDeskLogic

final class InboxGlanceTests: XCTestCase {
    func testHeuristicIsOneLinePerEmailAndSkipsRecitation() {
        let greenacre = VoiceRegressionDesk.greenacre
        var authentisign = VoiceRegressionDesk.steve
        authentisign.fromName = "Authentisign"
        authentisign.fromEmail = "noreply@authentisign.example.com"
        authentisign.subject = "Signing complete"
        authentisign.preview = "Please do not reply to this email. Hello Bridget, signing is complete."
        authentisign.body = "Please do not reply to this email.\n\nHello Bridget,\n\nSigning is complete for the Beach Drive package."

        let digest = ConversationPresence.inboxOverviewCopy([
            greenacre,
            VoiceRegressionDesk.murray,
            authentisign
        ])
        let lines = digest.split(whereSeparator: \.isNewline).map(String.init)
        XCTAssertEqual(lines.count, 3, digest)
        XCTAssertTrue(InboxGlance.isMultiline(digest))
        XCTAssertTrue(lines[0].contains("Greenacre"), lines[0])
        XCTAssertTrue(lines[0].contains("Board meeting") || lines[0].contains("meeting"), lines[0])
        XCTAssertTrue(lines[1].contains("Murray"), lines[1])
        XCTAssertTrue(lines[2].contains("Authentisign"), lines[2])
        XCTAssertTrue(lines[2].contains("Signing complete"), lines[2])
        XCTAssertFalse(digest.localizedCaseInsensitiveContains("please do not reply"), digest)
        XCTAssertFalse(digest.localizedCaseInsensitiveContains("hello bridget"), digest)
        XCTAssertFalse(digest.contains("Need you to notarize the closing package"), digest)
        XCTAssertEqual(digest, InboxGlance.heuristic([greenacre, VoiceRegressionDesk.murray, authentisign]))
    }

    func testGlanceIsMuchShorterThanThreadSummary() {
        let murray = EmailItem(
            fromName: "Murray Mitchell",
            fromEmail: "murray@example.com",
            sentAtLabel: "Today 9:00 AM",
            subject: "Closing / notarization",
            preview: "Need you to notarize",
            body: """
            Need you to notarize the closing package today. The buyer is coming at 3.
            Please confirm the walk-through window and the HOA packet.
            """,
            earlierMessages: [
                EmailThreadMessage(id: "e1", fromName: "Murray Mitchell", plainBody: "Can we walk the lot this week?")
            ],
            filterTag: "Inbox"
        )
        let glance = InboxGlance.heuristic([
            VoiceRegressionDesk.greenacre,
            murray,
            VoiceRegressionDesk.steve
        ])
        let thread = ConversationPresence.emailThreadReply(murray)
        XCTAssertTrue(InboxGlance.isMultiline(glance), glance)
        XCTAssertLessThan(glance.count, thread.count)
        XCTAssertLessThan(glance.split(separator: "\n").first?.count ?? 999, 90)
        XCTAssertGreaterThan(thread.count, 80, thread)
        XCTAssertEqual(DeskReplySpeech.textToSpeak(glance, lastSpoken: nil), glance)
        XCTAssertFalse(ConversationPresence.isGrokDeskMeta(glance))
    }

    func testAIParserRejectsMashedRecitationAndKeepsLines() {
        let mashed = "Here’s the recent inbox. Greenacre Properties, Inc.: Board meeting notice. Please do not reply. Hello Bridget…"
        XCTAssertNil(InboxGlance.acceptedLines(mashed, expectedCount: 2))
        let good = """
        Greenacre — HOA board meeting Aug 25.
        Murray — notarize closing today.
        """
        XCTAssertEqual(
            InboxGlance.acceptedLines(good, expectedCount: 2),
            ["Greenacre — HOA board meeting Aug 25.", "Murray — notarize closing today."]
        )
        XCTAssertTrue(InboxGlance.isRecitationDump("Please do not reply to this email."))
        XCTAssertEqual(InboxGlance.sanitizeSnippet("Please do not reply.\nHello Bridget,\nBoard packet attached."), "Board packet attached.")
    }

    func testNewestClarifyPickUsesSentAtLabel() {
        let older = murray(id: "old", subject: "Old walk-through", label: "Yesterday 4:00 PM")
        let middle = murray(id: "mid", subject: "Closing / notarization", label: "Today 9:00 AM")
        let newest = murray(id: "new", subject: "Walk-through today", label: "Today 2:00 PM")
        let matches = [older, middle, newest]

        XCTAssertTrue(ConversationPresence.isClarifyPick("The most recent one."))
        XCTAssertTrue(ConversationPresence.isClarifyPick("the latest"))
        XCTAssertTrue(ConversationPresence.isClarifyPick("the first one"))
        XCTAssertFalse(ConversationPresence.isClarifyPick("Show me the most recent email by showing time."))
        XCTAssertFalse(ConversationPresence.wantsInboxOverview("The most recent one."))
        XCTAssertFalse(ConversationPresence.ownsConnectedDeskTurn("The most recent one."))
        XCTAssertTrue(
            ConversationPresence.ownsConnectedDeskTurn(
                "The most recent one.",
                pendingSearchClarify: true,
                hasClarifyMatches: true
            )
        )
        XCTAssertFalse(
            ConversationPresence.ownsConnectedDeskTurn(
                "What's for dinner?",
                pendingSearchClarify: true,
                hasClarifyMatches: true
            )
        )

        XCTAssertEqual(
            ConversationPresence.pickClarifiedEmail(ask: "The most recent one.", candidates: matches)?.subject,
            "Walk-through today"
        )
        XCTAssertEqual(
            ConversationPresence.pickClarifiedEmail(ask: "the latest", candidates: matches)?.providerID,
            "new"
        )
        XCTAssertEqual(
            ConversationPresence.pickClarifiedEmail(ask: "the first one", candidates: matches)?.providerID,
            "old"
        )

        let evidence = ConversationPresence.deskEvidence(
            for: "The most recent one.",
            context: DeskContext(isConnected: true, snapshot: .empty),
            pendingSearchClarify: true,
            clarifyMatches: matches
        )
        XCTAssertEqual(evidence?.focusedEmail?.subject, "Walk-through today")
        XCTAssertEqual(evidence?.shouldFetchBody, true)
        XCTAssertNotEqual(evidence?.shouldSearchGmail, true)
        if case .email(let item) = evidence?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
            XCTAssertEqual(item.subject, "Walk-through today")
        } else {
            XCTFail("expected newest Murray card")
        }
        XCTAssertFalse(ConversationPresence.isGrokDeskMeta(evidence?.text ?? ""))
        XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("stay quiet"))
        XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("ios app"))
    }

    func testMurrayClarifyThenMostRecentReplayIsDeskPerson() {
        let older = murray(id: "old", subject: "Old walk-through", label: "Yesterday 4:00 PM")
        let newest = murray(id: "new", subject: "Walk-through today", label: "Today 2:00 PM")
        let replay = VoiceTurnReplay.play(
            utterance: "The most recent one.",
            context: VoiceRegressionDesk.greenacreOnly,
            focusedEmail: older,
            pendingSearchClarify: true,
            clarifyMatches: [older, newest]
        )
        XCTAssertTrue(replay.ownsDeskTurn)
        XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), replay.intent)
        XCTAssertNotEqual(replay.intent, "general")
        XCTAssertNotEqual(replay.intent, "inbox-overview")
        XCTAssertFalse(replay.shouldSearchGmail)
        XCTAssertEqual(replay.evidence?.focusedEmail?.providerID, "new")
        XCTAssertTrue(replay.cardLabels.contains { $0.contains("Murray Mitchell") && $0.contains("Walk-through today") }, "\(replay.cardLabels)")
        XCTAssertFalse(replay.cardLabels.contains { $0.contains("Greenacre") }, "\(replay.cardLabels)")
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
