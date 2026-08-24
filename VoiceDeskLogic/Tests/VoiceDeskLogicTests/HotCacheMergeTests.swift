import XCTest
@testable import VoiceDeskLogic

/// Live fail 2026-08-24: restore replaced the hot store with the latest-25
/// inbox pull, then “from Lauren dealing with Fleeman” searched Gmail as
/// from:("lauren dealing") and missed the cached Laren Jansen card.
final class HotCacheMergeTests: XCTestCase {
    static let dealingAsk =
        "Summarize the latest email from Lauren dealing with Fleeman Road."

    static let namedTopicFamily = [
        "Summarize the latest email from Lauren dealing with Fleeman Road.",
        "Summarize the latest email from Lauren regarding Fleeman Road.",
        "Summarize the latest email from Lauren about Fleeman Road.",
        "Give me a summary of the email from Laren dealing with Fleeman Road.",
        "Hey, give me a summary of the email from Lauren about Fleeman Road.",
        "I'm looking for the one that Lauren wrote regarding Fleeman Road."
    ]

    func testSyncMergesAgedOutFleemanAndGlanceStaysNewestFive() {
        let fleeman = VoiceRegressionDesk.larenJansen
        let newer = Self.newerInboxWindow(count: GoogleSyncPolicy.recentInboxLimit)
        XCTAssertEqual(newer.count, 25)

        let cached = DeskSnapshot(accountEmail: "agent@example.com", emails: [fleeman])
        let incoming = DeskSnapshot(
            accountEmail: "agent@example.com",
            lastSyncedAt: Date(timeIntervalSince1970: 200),
            emails: newer
        )
        let merged = DeskSnapshotMerge.applying(incoming: incoming, onto: cached)

        XCTAssertEqual(merged.emails.count, 26, "store must keep Fleeman after a 25-row pull that omits it")
        XCTAssertTrue(merged.emails.contains { $0.providerID == fleeman.providerID })
        XCTAssertEqual(merged.emails.first?.providerID, newer.first?.providerID)
        XCTAssertEqual(merged.glanceEmails.count, InboxGlance.overviewLimit)
        XCTAssertEqual(merged.glanceEmails.map(\.providerID), newer.prefix(5).map(\.providerID))
        XCTAssertFalse(
            merged.glanceEmails.contains { $0.providerID == fleeman.providerID },
            "glance is the newest 5 — a view, not a shrink of the store"
        )
        XCTAssertEqual(
            ConversationPresence.cards(for: .inbox, context: DeskContext(isConnected: true, snapshot: merged)).count,
            5
        )
        let glance = ConversationPresence.inboxOverviewCopy(merged.emails)
        XCTAssertFalse(glance.localizedCaseInsensitiveContains("Fleeman"))
        XCTAssertFalse(glance.localizedCaseInsensitiveContains("Laren Jansen"))
        XCTAssertTrue(glance.contains(newer[0].fromName))
    }

    func testExistingRowUpdatesInPlaceAndKeepsRicherBody() {
        var cachedFleeman = VoiceRegressionDesk.larenJansen
        cachedFleeman.body = "Disclosures for the Fleeman Road listing are attached."
        var incomingFleeman = VoiceRegressionDesk.larenJansen
        incomingFleeman.id = UUID()
        incomingFleeman.subject = "Fleeman Road disclosures (updated)"
        incomingFleeman.preview = "Updated packet."
        incomingFleeman.body = nil

        let merged = DeskSnapshotMerge.emails(
            incoming: [incomingFleeman],
            onto: [cachedFleeman]
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, cachedFleeman.id)
        XCTAssertEqual(merged[0].subject, "Fleeman Road disclosures (updated)")
        XCTAssertEqual(merged[0].body, "Disclosures for the Fleeman Road listing are attached.")
    }

    func testOfflineIncomingEmptyDoesNotDropCachedMailWhenMergingOntoStore() {
        let cached = DeskSnapshot(
            accountEmail: "agent@example.com",
            emails: [VoiceRegressionDesk.larenJansen],
            lastError: nil
        )
        let failedPull = DeskSnapshot(
            accountEmail: "agent@example.com",
            emails: [],
            lastError: "network"
        )
        let merged = DeskSnapshotMerge.applying(incoming: failedPull, onto: cached)
        XCTAssertEqual(merged.emails.map(\.providerID), [VoiceRegressionDesk.larenJansen.providerID])
    }

    func testDealingWithIsTopicGlueNotALastName() {
        let plan = GmailSearchQuery.plan(from: Self.dealingAsk)
        XCTAssertTrue(plan?.senders.contains("lauren") == true, "\(plan?.senders ?? [])")
        XCTAssertFalse(plan?.senders.contains("dealing") == true, "\(plan?.senders ?? [])")
        XCTAssertFalse(plan?.phrases.contains(where: { $0.contains("dealing") }) == true, "\(plan?.phrases ?? [])")
        XCTAssertTrue(plan?.subjectTokens.contains("fleeman") == true, "\(plan?.subjectTokens ?? [])")
        XCTAssertEqual(plan?.primary, "from:lauren fleeman road", plan?.primary ?? "nil")
        for variant in plan?.variants ?? [] {
            XCTAssertFalse(variant.contains("lauren dealing"), variant)
            XCTAssertFalse(variant.contains("from:(\"lauren dealing\")"), variant)
            XCTAssertFalse(variant.contains("laurendealing"), variant)
        }
        XCTAssertEqual(
            GmailSearchQuery.fromSpokenPhrase(in: Self.dealingAsk),
            "lauren"
        )
    }

    func testNamedTopicFamilyHitsCachedFleemanNotGmail() {
        let newer = Self.newerInboxWindow(count: GoogleSyncPolicy.recentInboxLimit)
        let store = DeskSnapshotMerge.applying(
            incoming: DeskSnapshot(emails: newer),
            onto: DeskSnapshot(emails: [VoiceRegressionDesk.larenJansen])
        )
        let context = DeskContext(isConnected: true, snapshot: store)
        XCTAssertFalse(store.glanceEmails.contains { $0.subject.contains("Fleeman") })
        XCTAssertTrue(store.emails.contains { $0.subject.contains("Fleeman") })

        for ask in Self.namedTopicFamily {
            XCTAssertFalse(EarlyFinalHold.shouldHold(ask), ask)
            XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(ask), ask)
            XCTAssertTrue(ConversationPresence.looksLikeMailAsk(ask), ask)

            let plan = GmailSearchQuery.plan(from: ask)
            XCTAssertTrue(plan?.senders.contains(where: { $0 == "lauren" || $0 == "laren" }) == true, "\(ask) \(plan?.senders ?? [])")
            XCTAssertTrue(plan?.subjectTokens.contains("fleeman") == true, "\(ask) \(plan?.subjectTokens ?? [])")
            for variant in plan?.variants ?? [] {
                XCTAssertFalse(variant.contains("lauren dealing"), "\(ask) \(variant)")
                XCTAssertFalse(variant.contains("from:(\"lauren dealing\")"), "\(ask) \(variant)")
            }

            let evidence = ConversationPresence.deskEvidence(for: ask, context: context)
            XCTAssertNotEqual(evidence?.shouldSearchGmail, true, ask)
            XCTAssertEqual(evidence?.focusedEmail?.fromName, "Laren Jansen", ask)
            XCTAssertEqual(evidence?.focusedEmail?.subject, "Fleeman Road disclosures", ask)
            XCTAssertEqual(
                VoiceInteractionLog.cardLabels(evidence?.cards ?? []),
                ["email:Laren Jansen:Fleeman Road disclosures"],
                ask
            )

            let classified = VoiceInteractionLog.classify(utterance: ask, evidence: evidence)
            XCTAssertFalse(classified.notes.contains("cache miss"), "\(ask) \(classified.notes)")
            XCTAssertFalse((evidence?.gmailQuery ?? "").contains("lauren dealing"), ask)

            let replay = VoiceTurnReplay.play(utterance: ask, context: context)
            XCTAssertFalse(replay.shouldSearchGmail, ask)
            XCTAssertTrue(replay.cardLabels.contains { $0.contains("Laren Jansen") && $0.contains("Fleeman") }, "\(ask) \(replay.cardLabels)")
        }
    }

    func testNamedTopicMissesOnlyWhenStoreHasNoMatch() {
        let context = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: Self.newerInboxWindow(count: 5))
        )
        let evidence = ConversationPresence.deskEvidence(for: Self.dealingAsk, context: context)
        XCTAssertEqual(evidence?.shouldSearchGmail, true)
        XCTAssertEqual(evidence?.gmailQuery, "from:lauren fleeman road")
        XCTAssertFalse((evidence?.gmailQuery ?? "").contains("lauren dealing"))
    }

    private static func newerInboxWindow(count: Int) -> [EmailItem] {
        (0..<count).map { index in
            EmailItem(
                id: UUID(uuidString: String(format: "11111111-1111-4000-8000-%012d", index))!,
                providerID: "inbox-newer-\(index)",
                fromName: index == 0 ? "Eriq Breland" : "Inbox \(index)",
                fromEmail: "inbox\(index)@example.com",
                sentAtLabel: "Today 4:\(String(format: "%02d", 50 - index)) PM",
                subject: "Newer inbox \(index)",
                preview: "Newer than Fleeman.",
                body: "Newer than Fleeman.",
                filterTag: "Inbox"
            )
        }
    }
}
