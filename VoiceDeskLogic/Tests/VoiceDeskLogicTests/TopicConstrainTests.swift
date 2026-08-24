import XCTest
@testable import VoiceDeskLogic

/// Dogfood 2026-08-24T20:13Z: Lauren + Fleeman must drop Family Fun Day and
/// never yield “the one regarding Fleeman Road” to live Grok.
final class TopicConstrainTests: XCTestCase {
    static let laurenFleeman =
        "Hey, give me a summary of the email from Lauren about Fleeman Road."
    static let regardingFleeman = "The one regarding Fleeman Road."
    static let followFamily = [
        "The one regarding Fleeman Road.",
        "the one regarding Fleeman Road",
        "regarding Fleeman Road",
        "the Fleeman one",
        "the disclosures one",
        "um, the one regarding Fleeman Road",
        "how about the one regarding Fleeman Road",
        "that one"
    ]

    func testLaurenAboutFleemanQueryAndPlan() {
        let plan = GmailSearchQuery.plan(from: Self.laurenFleeman)
        XCTAssertTrue(plan?.senders.contains("lauren") == true, "\(plan?.senders ?? [])")
        XCTAssertTrue(plan?.subjectTokens.contains("fleeman") == true, "\(plan?.subjectTokens ?? [])")
        XCTAssertEqual(plan?.primary, "from:lauren fleeman road", plan?.primary ?? "nil")
        for variant in plan?.variants ?? [] {
            XCTAssertFalse(variant == "from:lauren", "topic-less from:lauren must not be a q= fallback")
            XCTAssertFalse(variant == "from:lauren OR lauren", variant)
        }
    }

    func testTopicDropsFamilyFunDayEvenWhenBodySaysRoad() {
        var picnic = VoiceRegressionDesk.alexAndLaren
        picnic = EmailItem(
            id: picnic.id,
            providerID: picnic.providerID,
            fromName: picnic.fromName,
            fromEmail: picnic.fromEmail,
            sentAtLabel: picnic.sentAtLabel,
            subject: picnic.subject,
            preview: picnic.preview,
            body: "Meet us on the road by the park for Family Fun Day.",
            filterTag: picnic.filterTag
        )
        XCTAssertFalse(
            GmailSearchQuery.topicHit(picnic, tokens: ["fleeman", "road"]),
            "body-only “road” is not a topic hit"
        )
        XCTAssertEqual(
            GmailSearchQuery.pick(
                [picnic, VoiceRegressionDesk.larenJansen],
                ask: Self.laurenFleeman
            ),
            .one(VoiceRegressionDesk.larenJansen)
        )
    }

    func testLaurenAboutFleemanTakesOnlyDisclosures() {
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(Self.laurenFleeman))
        XCTAssertTrue(ConversationPresence.looksLikeMailAsk(Self.laurenFleeman))
        let evidence = ConversationPresence.deskEvidence(
            for: Self.laurenFleeman,
            context: VoiceRegressionDesk.laurenSeveral
        )
        XCTAssertNotEqual(evidence?.text, ConversationPresence.gmailSearchSeveralReply)
        XCTAssertNotEqual(evidence?.shouldSearchGmail, true)
        XCTAssertEqual(evidence?.focusedEmail?.fromName, "Laren Jansen")
        XCTAssertEqual(evidence?.focusedEmail?.subject, "Fleeman Road disclosures")
        let labels = VoiceInteractionLog.cardLabels(evidence?.cards ?? [])
        XCTAssertEqual(labels, ["email:Laren Jansen:Fleeman Road disclosures"], "\(labels)")
        XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("which one"))
        XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("client will"))
    }

    func testRegardingFollowUpIsDeskPickOfFleemanNotGrok() {
        for phrase in Self.followFamily {
            XCTAssertTrue(
                ConversationPresence.ownsConnectedDeskTurn(
                    phrase,
                    pendingSearchClarify: true,
                    hasClarifyMatches: true
                ),
                phrase
            )
            XCTAssertFalse(ConversationPresence.isGrokDeskMeta(phrase), phrase)
            let evidence = ConversationPresence.deskEvidence(
                for: phrase,
                context: VoiceRegressionDesk.laurenSeveral,
                pendingSearchClarify: true,
                clarifyMatches: [
                    VoiceRegressionDesk.alexAndLaren,
                    VoiceRegressionDesk.larenJansen
                ],
                priorSearchAsk: Self.laurenFleeman
            )
            XCTAssertEqual(evidence?.focusedEmail?.fromName, "Laren Jansen", phrase)
            XCTAssertEqual(evidence?.focusedEmail?.subject, "Fleeman Road disclosures", phrase)
            XCTAssertNotEqual(evidence?.shouldSearchGmail, true, phrase)
            XCTAssertNotEqual(evidence?.topic, .general, phrase)
            XCTAssertFalse(ConversationPresence.isGrokDeskMeta(evidence?.text ?? ""), phrase)
            XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("client will"), phrase)
            XCTAssertFalse((evidence?.text ?? "").localizedCaseInsensitiveContains("which one"), phrase)

            let replay = VoiceTurnReplay.play(
                utterance: phrase,
                context: VoiceRegressionDesk.laurenSeveral,
                pendingSearchClarify: true,
                clarifyMatches: [
                    VoiceRegressionDesk.alexAndLaren,
                    VoiceRegressionDesk.larenJansen,
                    VoiceRegressionDesk.greenacre
                ],
                priorSearchAsk: Self.laurenFleeman
            )
            XCTAssertTrue(replay.ownsDeskTurn, phrase)
            XCTAssertNotEqual(replay.intent, "general", "\(phrase) must not yield to live Grok")
            XCTAssertTrue(replay.cardLabels.contains { $0.contains("Laren Jansen") }, "\(phrase) → \(replay.cardLabels)")
            XCTAssertFalse(replay.cardLabels.contains { $0.contains("Family Fun Day") }, phrase)
            XCTAssertFalse(replay.notes.contains("live Grok"), "\(phrase) → \(replay.notes)")
        }
    }

    func testLaurenFleemanReplayIsSingleCardNotClarify() {
        let replay = VoiceTurnReplay.play(
            utterance: Self.laurenFleeman,
            context: VoiceRegressionDesk.laurenSeveral
        )
        XCTAssertTrue(replay.ownsDeskTurn)
        XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), replay.intent)
        XCTAssertEqual(replay.cardLabels, ["email:Laren Jansen:Fleeman Road disclosures"])
        XCTAssertFalse(replay.cardLabels.contains { $0.contains("Family Fun Day") })
        XCTAssertFalse(replay.reply.localizedCaseInsensitiveContains("which one"))
        XCTAssertFalse(replay.notes.contains("live Grok"))
        XCTAssertTrue(
            replay.notes.contains(where: { $0.contains("from:lauren") && $0.contains("fleeman") })
                || (replay.gmailQuery ?? "").contains("fleeman"),
            "\(replay.notes) \(replay.gmailQuery ?? "")"
        )
    }

    func testClientWillHandleIsGrokDeskMeta() {
        XCTAssertTrue(ConversationPresence.isGrokDeskMeta("I'll get that for you. The client will handle the summary."))
        XCTAssertTrue(ConversationPresence.isGrokDeskHandoff("The client will handle the summary."))
    }
}
