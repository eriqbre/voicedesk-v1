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

        let emails = [greenacre, VoiceRegressionDesk.murray, authentisign]
        let digest = InboxGlance.heuristic(emails)
        let spoken = ConversationPresence.inboxOverviewCopy(emails)
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
        XCTAssertFalse(spoken.isEmpty, "fd4a772 list/show spoke empty then cards: \(spoken)")
        XCTAssertTrue(InboxGlance.isShortSpokenSummary(spoken), spoken)
        XCTAssertFalse(InboxGlance.isShortSpokenAck(spoken), spoken)
        XCTAssertNotEqual(spoken, "Here they are.")
        XCTAssertFalse(spoken.localizedCaseInsensitiveContains("here they are"), spoken)
        XCTAssertFalse(InboxGlance.isMultiline(spoken), spoken)
        XCTAssertFalse(spoken.contains("—"), spoken)
    }

    /// fd4a772 leftover: list/show logged empty assistantReply + cards.
    /// 83a5c6a first mouth was “Here they are.” Speak a short line after tools.
    func testListShowDoesNotSpeakHereTheyAre() {
        let emails = [
            VoiceRegressionDesk.murray,
            VoiceRegressionDesk.steve
        ]
        let events = [
            CalendarItem(title: "Massimo showing", whenLabel: "Today 3:00 PM")
        ]
        for ask in ["show me my emails", "see my latest emails", "what's in my inbox?"] {
            let spoken = InboxGlance.spokenInbox(ask: ask, emails: emails)
            XCTAssertFalse(spoken.isEmpty, "fd4a772 \(ask) empty reply + cards: \(spoken)")
            XCTAssertTrue(InboxGlance.isShortSpokenSummary(spoken), "\(ask) → \(spoken)")
            XCTAssertFalse(InboxGlance.isShortSpokenAck(spoken), ask)
            XCTAssertNotEqual(spoken, "Here they are.", ask)
            XCTAssertFalse(spoken.localizedCaseInsensitiveContains("here they are"), ask)
            let overview = ConversationPresence.inboxOverviewCopy(emails, ask: ask)
            XCTAssertFalse(overview.isEmpty, "\(ask) overview → \(overview)")
            XCTAssertFalse(overview.localizedCaseInsensitiveContains("here they are"), ask)
            let plan = InboxGlanceSpeakPlan.fromCachedEmails(
                emails,
                ask: ask,
                fallbackText: ""
            )
            XCTAssertNotEqual(plan.spokenText, "Here they are.", ask)
            XCTAssertFalse(plan.spokenText.localizedCaseInsensitiveContains("here they are"), ask)
        }
        let calendarSpoken = InboxGlance.spokenCalendar(ask: "show my calendar", events: events)
        XCTAssertFalse(calendarSpoken.isEmpty, "fd4a772 calendar list empty reply + cards")
        XCTAssertTrue(InboxGlance.isShortSpokenSummary(calendarSpoken), calendarSpoken)
        let leftoverFollowUp = ConversationPresence.notSeeingCardsReply(hasInbox: true)
        XCTAssertTrue(
            leftoverFollowUp.isEmpty,
            "83a5c6a notSeeingCardsReply spoke Here they are — the synced emails."
        )
        XCTAssertFalse(leftoverFollowUp.localizedCaseInsensitiveContains("here they are"))
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

        for phrase in Self.newestClarifyPhrases {
            XCTAssertTrue(ConversationPresence.isClarifyPick(phrase), phrase)
            XCTAssertEqual(ConversationPresence.clarifyPickKind(phrase), .newest, phrase)
            XCTAssertFalse(ConversationPresence.wantsInboxOverview(phrase), phrase)
            XCTAssertFalse(ConversationPresence.ownsConnectedDeskTurn(phrase), phrase)
            XCTAssertTrue(
                ConversationPresence.ownsConnectedDeskTurn(
                    phrase,
                    pendingSearchClarify: true,
                    hasClarifyMatches: true
                ),
                phrase
            )
        }
        XCTAssertTrue(ConversationPresence.isClarifyPick("the first one"))
        XCTAssertTrue(ConversationPresence.isClarifyPick("the second"))
        XCTAssertFalse(ConversationPresence.isClarifyPick("Show me the most recent email by showing time."))
        XCTAssertFalse(ConversationPresence.isClarifyPick("Give me a summary of Murray's last email."))
        XCTAssertFalse(ConversationPresence.wantsInboxOverview("The last one."))
        XCTAssertFalse(ConversationPresence.ownsConnectedDeskTurn("The last one."))
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

        for phrase in Self.newestClarifyPhrases {
            XCTAssertEqual(
                ConversationPresence.pickClarifiedEmail(ask: phrase, candidates: matches)?.subject,
                "Walk-through today",
                phrase
            )
            XCTAssertEqual(
                ConversationPresence.pickClarifiedEmail(ask: phrase, candidates: matches)?.providerID,
                "new",
                phrase
            )
        }
        XCTAssertEqual(
            ConversationPresence.pickClarifiedEmail(ask: "the first one", candidates: matches)?.providerID,
            "old"
        )
        XCTAssertEqual(
            ConversationPresence.pickClarifiedEmail(ask: "the second", candidates: matches)?.providerID,
            "mid"
        )

        for phrase in Self.newestClarifyPhrases {
            let evidence = ConversationPresence.deskEvidence(
                for: phrase,
                context: DeskContext(isConnected: true, snapshot: .empty),
                pendingSearchClarify: true,
                clarifyMatches: matches
            )
            XCTAssertEqual(evidence?.focusedEmail?.subject, "Walk-through today", phrase)
            XCTAssertEqual(evidence?.shouldFetchBody, true, phrase)
            XCTAssertNotEqual(evidence?.shouldSearchGmail, true, phrase)
            if case .email(let item) = evidence?.cards.first {
                XCTAssertEqual(item.fromName, "Murray Mitchell", phrase)
                XCTAssertEqual(item.subject, "Walk-through today", phrase)
            } else {
                XCTFail("expected newest Murray card for \(phrase)")
            }
            XCTAssertFalse(ConversationPresence.isGrokDeskMeta(evidence?.text ?? ""), phrase)
            XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("stay quiet"), phrase)
            XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("ios app"), phrase)
            XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("got it. the client"), phrase)
        }
    }

    func testMurrayClarifyThenMostRecentReplayIsDeskPerson() {
        let older = murray(id: "old", subject: "Old walk-through", label: "Yesterday 4:00 PM")
        let newest = murray(id: "new", subject: "Walk-through today", label: "Today 2:00 PM")
        for phrase in Self.newestClarifyPhrases {
            let replay = VoiceTurnReplay.play(
                utterance: phrase,
                context: VoiceRegressionDesk.greenacreOnly,
                focusedEmail: older,
                pendingSearchClarify: true,
                clarifyMatches: [older, newest]
            )
            XCTAssertTrue(replay.ownsDeskTurn, phrase)
            XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), "\(phrase) → \(replay.intent)")
            XCTAssertNotEqual(replay.intent, "general", "\(phrase) must not yield to live Grok")
            XCTAssertNotEqual(replay.intent, "inbox-overview", phrase)
            XCTAssertFalse(replay.shouldSearchGmail, phrase)
            XCTAssertEqual(replay.evidence?.focusedEmail?.providerID, "new", phrase)
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Murray Mitchell") && $0.contains("Walk-through today") },
                "\(phrase) → \(replay.cardLabels)"
            )
            XCTAssertFalse(replay.cardLabels.contains { $0.contains("Greenacre") }, "\(phrase) → \(replay.cardLabels)")
            XCTAssertFalse(replay.notes.contains("live Grok"), "\(phrase) → \(replay.notes)")
        }
    }

    /// Cards are the on-screen list. Eve speaks one short beat, not the heuristic lines.
    func testInboxOverviewOnScreenOmitsGlanceWhenCardsAttached() {
        let emails = [
            VoiceRegressionDesk.greenacre,
            VoiceRegressionDesk.murray,
            VoiceRegressionDesk.steve
        ]
        let glance = InboxGlance.heuristic(emails)
        XCTAssertTrue(InboxGlance.isMultiline(glance), glance)
        XCTAssertTrue(glance.contains("—"), glance)
        XCTAssertTrue(glance.contains("Greenacre") || glance.contains("Murray"), glance)

        let onScreen = InboxGlance.onScreenText(compactCardCount: emails.count)
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(onScreen),
            "on-screen must be empty or a short lead-in, not the glance: \(onScreen)"
        )
        XCTAssertFalse(InboxGlance.repeatsGlanceLines(onScreen), onScreen)
        XCTAssertFalse(onScreen.contains("Greenacre"), onScreen)
        XCTAssertFalse(onScreen.contains("Murray Mitchell"), onScreen)
        XCTAssertFalse(onScreen.contains("—"), onScreen)

        let spoken = InboxGlance.spokenInbox(ask: "see my latest emails", emails: emails)
        XCTAssertFalse(spoken.isEmpty, "fd4a772 latest emails empty reply + cards")
        XCTAssertTrue(InboxGlance.isShortSpokenSummary(spoken), spoken)
        XCTAssertFalse(InboxGlance.isShortSpokenAck(spoken), spoken)
        XCTAssertNotEqual(spoken, "Here they are.")
        XCTAssertFalse(InboxGlance.isMultiline(spoken), spoken)
        XCTAssertFalse(spoken.contains("—"), spoken)
        XCTAssertNotNil(DeskReplySpeech.textToSpeak(spoken, lastSpoken: nil))
        XCTAssertNotEqual(spoken, glance)

        let evidence = ConversationPresence.deskEvidence(
            for: "see my latest emails",
            context: DeskContext(isConnected: true, snapshot: DeskSnapshot(emails: emails))
        )
        XCTAssertEqual(evidence?.shouldGlanceInbox, true)
        XCTAssertEqual(evidence?.cards.count, 3)
        XCTAssertFalse((evidence?.text ?? "").isEmpty, "fd4a772 empty reply + cards: \(evidence?.text ?? "")")
        XCTAssertTrue(InboxGlance.isShortSpokenSummary(evidence?.text ?? ""), evidence?.text ?? "")
        XCTAssertNotEqual(evidence?.text, "Here they are.")
        XCTAssertFalse(InboxGlance.isMultiline(evidence?.text ?? ""), evidence?.text ?? "")
        let bubble = InboxGlance.onScreenText(compactCardCount: evidence?.cards.count ?? 0)
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(bubble), bubble)
        XCTAssertFalse(InboxGlance.repeatsGlanceLines(bubble), bubble)
    }

    /// Single-email card: speak the AI summary, do not reprint it in the bubble.
    func testSingleEmailCardHidesSpokenSummaryOnScreen() {
        let email = VoiceRegressionDesk.murray
        let request = EmailSummaryRequest.from(email, includeEarlier: false)
        let spoken = EmailSummary.heuristic(request)
        XCTAssertFalse(spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, spoken)
        XCTAssertTrue(spoken.contains("Murray") || spoken.contains("notarize") || spoken.count > 40, spoken)

        let onScreen = InboxGlance.onScreenTextHidingSpokenSummary()
        XCTAssertTrue(
            InboxGlance.isShortOnScreenLeadIn(onScreen),
            "single-email bubble must be empty or a short lead-in, not the summary: \(onScreen)"
        )
        XCTAssertEqual(onScreen, InboxGlance.onScreenText(compactCardCount: 1))
        XCTAssertFalse(InboxGlance.repeatsGlanceLines(onScreen), onScreen)
        XCTAssertNotEqual(onScreen, spoken)
        XCTAssertFalse(onScreen.contains("Murray"), onScreen)
        XCTAssertFalse(onScreen.contains("notarize"), onScreen)

        XCTAssertEqual(DeskReplySpeech.textToSpeak(spoken, lastSpoken: nil), spoken)
        XCTAssertNil(DeskReplySpeech.textToSpeak(onScreen, lastSpoken: nil))

        XCTAssertFalse(
            InboxGlance.isShortOnScreenLeadIn(ConversationPresence.gmailSearchSeveralReply),
            "clarify lead-in must stay visible: \(ConversationPresence.gmailSearchSeveralReply)"
        )
        XCTAssertEqual(
            ConversationPresence.gmailSearchSeveralReply,
            "I found a few matches. Which one?"
        )
        XCTAssertFalse(InboxGlance.isShortOnScreenLeadIn(ConversationPresence.gmailSearchEmptyReply))
        XCTAssertFalse(InboxGlance.isShortOnScreenLeadIn(ConversationPresence.gmailSearchFailedReply))
        XCTAssertFalse(InboxGlance.isShortOnScreenLeadIn(ConversationPresence.connectHowToReply))
        XCTAssertFalse(
            InboxGlance.isShortOnScreenLeadIn(
                ConversationPresence.emailBodySyncFailedReply(email)
            )
        )

        let inboxOnScreen = InboxGlance.onScreenText(compactCardCount: 3)
        XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(inboxOnScreen), inboxOnScreen)
        XCTAssertEqual(inboxOnScreen, onScreen)
    }

    /// DD56F6A9 / 677abb9 leftover: spokenInbox is the from/subject dump
    /// that was the live mouth, then cards. Not the product mouth.
    /// fd4a772 was empty reply + cards. Live plan waits; Eve speaks.
    func testFd4a772EmptyAnd677abb9GlanceAreNotTheLiveMouth() {
        let emails = [
            VoiceRegressionDesk.murray,
            VoiceRegressionDesk.steve,
            VoiceRegressionDesk.greenacre,
            VoiceRegressionDesk.laren,
            VoiceRegressionDesk.ericGross
        ]
        let latest = InboxGlance.spokenInbox(ask: "Show me my latest emails.", emails: emails)
        XCTAssertFalse(latest.isEmpty, "fd4a772 latest emails: empty reply + 5 cards")
        XCTAssertTrue(InboxGlance.isFromSubjectGlanceDump(latest), latest)
        XCTAssertFalse(InboxGlance.isShortSpokenAck(latest), latest)
        XCTAssertNotEqual(latest, "Here they are.")
        XCTAssertFalse(GrokRealtime.teachesLeftoverDeskRouting(latest), latest)

        let tapeBlob = "joseph.loparo@cypressrun.com on Join Us Tomorrow Night for Lobster Rolls!, Bank of America on Zelle…, and more."
        XCTAssertTrue(InboxGlance.isFromSubjectGlanceDump(tapeBlob), tapeBlob)

        let plan = InboxGlanceSpeakPlan.liveVAD(
            ask: "Show me my latest emails.",
            snapshot: DeskSnapshot(emails: emails)
        )
        XCTAssertFalse(
            InboxGlance.isFromSubjectGlanceDump(plan.spokenText),
            "677abb9 live plan spoke the dump: \(plan.spokenText)"
        )
        XCTAssertNotEqual(plan.spokenText, latest)
        XCTAssertTrue(plan.waitsOnGmailList)
        XCTAssertTrue(plan.waitsOnModel)
        XCTAssertEqual(plan.spokenSource, InboxGlanceSpeakPlan.eveSpokenSource)
        XCTAssertFalse(InboxGlanceSpeakPlan.isSkippedGlanceListStub(plan))
        XCTAssertNotEqual(plan.spokenText, "Here they are.")

        let events = [
            CalendarItem(title: "Walk the lot", whenLabel: "Tomorrow 9:00 AM"),
            CalendarItem(title: "Massimo showing", whenLabel: "Tomorrow 3:00 PM")
        ]
        let calendar = InboxGlance.spokenCalendar(
            ask: "what's on my calendar tomorrow",
            events: events
        )
        XCTAssertFalse(calendar.isEmpty, "fd4a772 calendar tomorrow: empty reply + 2 cards")
        XCTAssertNotEqual(calendar, "Here they are.")
        XCTAssertFalse(InboxGlance.isShortSpokenAck(calendar), calendar)
    }

    private static let newestClarifyPhrases = [
        "The last one.",
        "the last one",
        "The most recent one.",
        "the latest",
        "that one"
    ]

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
