import XCTest
@testable import VoiceDeskLogic

/// Dogfood 2026-08-24: named-sender pick, reject+topic refine, Eric vs Eriq.
final class SenderRefineTests: XCTestCase {
    static let latestLauren = "What's the latest email from Lauren?"
    static let rejectFleeman =
        "No. Not that one. I'm looking for the one that Lauren wrote regarding Fleeman Road."
    static let rejectFamily = [
        "No. Not that one. I'm looking for the one that Lauren wrote regarding Fleeman Road.",
        "not that one",
        "No. Not that one.",
        "the other one",
        "not that",
        "wrong one",
        "that's not it"
    ]
    static let ericAsk = "When was Eric's last email?"

    func testLatestLaurenClarifiesDistinctSendersNotAlexAndLarenAlone() {
        let ask = Self.latestLauren
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(ask))
        XCTAssertTrue(ConversationPresence.looksLikeMailAsk(ask))
        let evidence = ConversationPresence.deskEvidence(
            for: ask,
            context: VoiceRegressionDesk.laurenSeveral
        )
        XCTAssertEqual(evidence?.text, ConversationPresence.gmailSearchSeveralReply)
        XCTAssertNotEqual(evidence?.shouldSearchGmail, true)
        let names = evidence?.cards.compactMap { card -> String? in
            if case .email(let item) = card { return item.fromName }
            return nil
        } ?? []
        XCTAssertTrue(names.contains("Alex & Laren"), "\(names)")
        XCTAssertTrue(names.contains("Laren Jansen"), "\(names)")
        XCTAssertEqual(names.count, 2, "\(names)")
        XCTAssertNil(evidence?.focusedEmail, "must not silently attach one Lauren")
        XCTAssertTrue(evidence?.awaitsSearchClarify == true)
        XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("client will"))
    }

    func testRejectAfterWrongLaurenStaysDeskAndFindsFleeman() {
        for phrase in Self.rejectFamily where phrase.contains("Fleeman") || phrase.contains("not that one") {
            XCTAssertTrue(ConversationPresence.isSenderRejectRefine(phrase), phrase)
        }
        XCTAssertTrue(ConversationPresence.isSenderRejectRefine(Self.rejectFleeman))
        XCTAssertTrue(ConversationPresence.hasDeskMailIntent(Self.rejectFleeman))
        XCTAssertTrue(ConversationPresence.looksLikeMailAsk(Self.rejectFleeman))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(Self.rejectFleeman))
        XCTAssertTrue(
            ConversationPresence.ownsConnectedDeskTurn(
                "No. Not that one.",
                hasFocusedEmail: true
            )
        )
        XCTAssertFalse(
            ConversationPresence.ownsConnectedDeskTurn("No. Not that one."),
            "bare reject without a card is not a desk steal"
        )

        let evidence = ConversationPresence.deskEvidence(
            for: Self.rejectFleeman,
            context: VoiceRegressionDesk.laurenSeveral,
            focusedEmail: VoiceRegressionDesk.alexAndLaren
        )
        XCTAssertTrue(evidence?.keepsSenderRefine == true)
        XCTAssertNotEqual(evidence?.shouldSearchGmail, true, evidence?.gmailQuery ?? "")
        XCTAssertEqual(evidence?.focusedEmail?.fromName, "Laren Jansen")
        XCTAssertEqual(evidence?.focusedEmail?.subject, "Fleeman Road disclosures")
        if case .email(let item) = evidence?.cards.first {
            XCTAssertEqual(item.fromName, "Laren Jansen")
            XCTAssertFalse(item.fromName.contains("Alex"))
        } else {
            XCTFail("expected Laren Jansen Fleeman card, got \(evidence?.cards ?? [])")
        }
        XCTAssertFalse(ConversationPresence.isGrokDeskMeta(evidence?.text ?? ""))
        XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("client will"))
        XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("full read"))
    }

    func testRejectSynonymsStayDeskAfterNamedCard() {
        for phrase in ["No. Not that one.", "not that one", "the other one", "not that"] {
            XCTAssertTrue(ConversationPresence.isSenderRejectRefine(phrase), phrase)
            XCTAssertTrue(
                ConversationPresence.ownsConnectedDeskTurn(
                    phrase,
                    hasFocusedEmail: true
                ),
                phrase
            )
            let evidence = ConversationPresence.deskEvidence(
                for: phrase,
                context: VoiceRegressionDesk.laurenSeveral,
                focusedEmail: VoiceRegressionDesk.alexAndLaren
            )
            XCTAssertNotNil(evidence, phrase)
            XCTAssertNotEqual(evidence?.topic, .general, phrase)
            XCTAssertFalse(ConversationPresence.isGrokDeskMeta(evidence?.text ?? ""), phrase)
        }
    }

    func testYeahAfterRefineStaysDeskNotSmallTalk() {
        XCTAssertTrue(
            ConversationPresence.ownsConnectedDeskTurn(
                "Yeah",
                pendingSenderRefine: true,
                hasFocusedEmail: true
            )
        )
        XCTAssertFalse(
            ConversationPresence.ownsConnectedDeskTurn("Yeah"),
            "Yeah without a pending refine is not a desk steal"
        )
        let evidence = ConversationPresence.deskEvidence(
            for: "Yeah",
            context: VoiceRegressionDesk.laurenSeveral,
            focusedEmail: VoiceRegressionDesk.larenJansen,
            pendingSenderRefine: true
        )
        XCTAssertEqual(evidence?.focusedEmail?.fromName, "Laren Jansen")
        XCTAssertNotEqual(evidence?.topic, .general)
        XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("i’m with you"))
        XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("i'm with you"))
        XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("what else"))

        let replay = VoiceTurnReplay.play(
            utterance: "Yeah",
            context: VoiceRegressionDesk.laurenSeveral,
            focusedEmail: VoiceRegressionDesk.larenJansen,
            pendingSenderRefine: true
        )
        XCTAssertTrue(replay.ownsDeskTurn)
        XCTAssertNotEqual(replay.intent, "general")
        XCTAssertFalse(replay.notes.contains("live Grok"))
        XCTAssertEqual(replay.evidence?.focusedEmail?.subject, "Fleeman Road disclosures")
    }

    func testEricPrefersEricGrossNotMailboxOwnerEriq() {
        let ask = Self.ericAsk
        XCTAssertEqual(GmailSearchQuery.query(from: ask), "from:eric")
        let evidence = ConversationPresence.deskEvidence(
            for: ask,
            context: VoiceRegressionDesk.ericWithGross
        )
        XCTAssertEqual(evidence?.focusedEmail?.fromName, "Eric Gross")
        XCTAssertNotEqual(evidence?.focusedEmail?.fromName, "Eriq Cole")
        if case .email(let item) = evidence?.cards.first {
            XCTAssertEqual(item.fromEmail, "eric.gross@example.com")
        } else {
            XCTFail("expected Eric Gross card")
        }
        XCTAssertFalse((evidence?.text ?? "").contains("Eriq Cole"))
    }

    func testEricSelfOnlyClarifiesInsteadOfAttachingEriq() {
        let ask = Self.ericAsk
        let evidence = ConversationPresence.deskEvidence(
            for: ask,
            context: VoiceRegressionDesk.ericSelfOnly
        )
        XCTAssertTrue(evidence?.cards.isEmpty == true, "\(evidence?.cards ?? [])")
        XCTAssertNil(evidence?.focusedEmail)
        XCTAssertTrue((evidence?.text ?? "").contains("you"))
        XCTAssertTrue((evidence?.text ?? "").localizedCaseInsensitiveContains("eric"))
        XCTAssertFalse((evidence?.text ?? "").contains("Eric Gross"), "do not invent a missing Eric")
        XCTAssertNotEqual(evidence?.shouldSearchGmail, true)
    }

    func testRejectFleemanReplayIsDeskSearchNotGrok() {
        let replay = VoiceTurnReplay.play(
            utterance: Self.rejectFleeman,
            context: VoiceRegressionDesk.laurenSeveral,
            focusedEmail: VoiceRegressionDesk.alexAndLaren
        )
        XCTAssertTrue(replay.ownsDeskTurn)
        XCTAssertNotEqual(replay.intent, "general")
        XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), replay.intent)
        XCTAssertTrue(replay.cardLabels.contains { $0.contains("Laren Jansen") }, "\(replay.cardLabels)")
        XCTAssertFalse(replay.cardLabels.contains { $0.contains("Family Fun Day") })
        XCTAssertFalse(replay.notes.contains("live Grok"))
        XCTAssertTrue(
            replay.notes.contains(where: { $0.contains("from:lauren") && $0.contains("fleeman") })
                || (replay.gmailQuery ?? "").contains("fleeman")
                || replay.cardLabels.contains { $0.contains("Fleeman") },
            "\(replay.notes) \(replay.gmailQuery ?? "") \(replay.cardLabels)"
        )
    }
}
