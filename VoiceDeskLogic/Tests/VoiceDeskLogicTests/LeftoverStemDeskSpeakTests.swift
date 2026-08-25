import XCTest
@testable import VoiceDeskLogic

/// Walk fail 2026-08-25: leftover hold-stem stayed on the user line
/// (“What's, give me a summary of the latest email from Murray”) and a
/// desk-thread / desk-person card attached with an empty mouth.
///
/// Synonym families, not one golden phrase. Assert intent / outcome —
/// never Eve’s exact wording.
final class LeftoverStemDeskSpeakTests: XCTestCase {
    /// Same leftover family as last night: Voice / What’s. / What’s / Hm. / Zero,
    /// plus the recorded comma form.
    static let leftoverFamily = [
        "What's,",
        "What's.",
        "What's",
        "Voice",
        "Hm.",
        "Zero"
    ]

    static let murrayAskFamily = [
        "give me a summary of the latest email from Murray",
        "how about Murray's latest",
        "summarize Murray's last email"
    ]

    /// Recorded dogfood phrase from the 2026-08-25 walk.
    static let dogfoodMurrayAsk =
        "What's, give me a summary of the latest email from Murray"

    static let sandyAskFamily = [
        "What about that email from Sandy?",
        "give me a summary of the latest email from Sandy",
        "summarize Sandy's last email"
    ]

    // MARK: A — leftover hold-stem is dropped before the desk ask

    func testLeftoverHoldStemFamilyIsDroppedBeforeMurrayDeskAsk() {
        let context = VoiceRegressionDesk.leftoverSpeak
        for leftover in Self.leftoverFamily {
            for ask in Self.murrayAskFamily {
                let spoken = Self.combine(leftover: leftover, ask: ask)
                var hold = EarlyFinalHold()
                let decision = hold.decide(spoken, context: context)
                let accepted = decision.acceptedText ?? ""

                XCTAssertNotEqual(decision.intent, "held", spoken)
                XCTAssertNotEqual(decision.intent, "general", "\(spoken) must not go to live Grok")
                XCTAssertTrue(
                    ["desk-thread", "desk-person"].contains(decision.intent),
                    "\(spoken) → \(decision.intent)"
                )
                XCTAssertFalse(Self.acceptedKeepsLeftoverPrefix(accepted, leftover: leftover), accepted)
                XCTAssertTrue(accepted.localizedCaseInsensitiveContains("murray"), accepted)
                XCTAssertFalse(EarlyFinalHold.shouldHold(accepted), accepted)
            }
        }
    }

    func testRecordedDogfoodWhatsCommaMurrayAskDropsLeftoverAndStaysDesk() {
        var hold = EarlyFinalHold()
        let decision = hold.decide(Self.dogfoodMurrayAsk, context: VoiceRegressionDesk.leftoverSpeak)
        XCTAssertEqual(decision.acceptedText, "give me a summary of the latest email from Murray")
        XCTAssertTrue(["desk-thread", "desk-person"].contains(decision.intent), decision.intent)
        XCTAssertNotEqual(decision.intent, "general")

        let replay = VoiceTurnReplay.play(
            utterance: Self.dogfoodMurrayAsk,
            context: VoiceRegressionDesk.leftoverSpeak
        )
        XCTAssertTrue(["desk-thread", "desk-person"].contains(replay.intent), replay.intent)
        XCTAssertNotEqual(replay.intent, "general")
        XCTAssertTrue(replay.attachesEmailCard)
        XCTAssertEqual(replay.evidence?.focusedEmail?.fromName, "Murray Mitchell")
        XCTAssertTrue(
            replay.cardLabels.contains { $0.contains("Murray Mitchell") && $0.contains("302") },
            "\(replay.cardLabels)"
        )
    }

    func testCompleteAsksKeepTheirLeadingWhatOrZero() {
        let calendar = EarlyFinalHold.dropLeadingLeftoverStem("What's on my calendar")
        XCTAssertEqual(calendar, "What's on my calendar")
        XCTAssertEqual(
            ConversationPresence.plan(for: calendar, context: VoiceRegressionDesk.connected).topic,
            .calendar
        )

        let inbox = EarlyFinalHold.dropLeadingLeftoverStem("What's in my inbox?")
        XCTAssertEqual(inbox, "What's in my inbox?")

        let zeroEmails = EarlyFinalHold.dropLeadingLeftoverStem("Zero emails today")
        XCTAssertEqual(zeroEmails, "Zero emails today")

        let sandy = EarlyFinalHold.dropLeadingLeftoverStem("What about that email from Sandy?")
        XCTAssertEqual(sandy, "What about that email from Sandy?")
    }

    // MARK: B — empty speak on a desk hit is illegal

    func testDeskHitWithCardNeverSpeaksEmptyEvenWhenXAIIsEmptySlowOrSkipped() {
        let murray = VoiceRegressionDesk.murrayGeorgia
        let sandy = VoiceRegressionDesk.sandyGut
        let emptyXAI: [String?] = [nil, "", "   ", "\n"]

        for xai in emptyXAI {
            let spoken = DeskReplySpeech.spokenDeskHit(murray, xaiSummarize: xai)
            XCTAssertFalse(spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "xai=\(xai ?? "nil")")
            XCTAssertNotNil(DeskReplySpeech.textToSpeak(spoken, lastSpoken: nil), spoken)
            XCTAssertTrue(spoken.contains("Murray Mitchell"), spoken)
            XCTAssertTrue(
                spoken.localizedCaseInsensitiveContains("302")
                    || spoken.localizedCaseInsensitiveContains("georgia")
                    || spoken.localizedCaseInsensitiveContains("closing"),
                spoken
            )
        }

        let sandySpoken = DeskReplySpeech.spokenDeskHit(sandy, xaiSummarize: "")
        XCTAssertFalse(sandySpoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, sandySpoken)
        XCTAssertTrue(sandySpoken.contains("Sandy Woodcock"), sandySpoken)
        XCTAssertTrue(sandySpoken.localizedCaseInsensitiveContains("gut"), sandySpoken)

        let heuristicMurray = EmailSummary.heuristic(EmailSummaryRequest.from(murray, includeEarlier: false))
        XCTAssertEqual(
            DeskReplySpeech.spokenDeskHit(murray, xaiSummarize: ""),
            heuristicMurray
        )
    }

    func testMurrayAndSandyDeskHitsSpeakHeuristicDigest() {
        let desk = VoiceRegressionDesk.leftoverSpeak

        for ask in Self.murrayAskFamily + [Self.dogfoodMurrayAsk] {
            let replay = VoiceTurnReplay.play(utterance: ask, context: desk)
            XCTAssertTrue(["desk-thread", "desk-person"].contains(replay.intent), "\(ask) → \(replay.intent)")
            XCTAssertTrue(replay.attachesEmailCard, ask)
            XCTAssertFalse(replay.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ask)
            XCTAssertNotNil(DeskReplySpeech.textToSpeak(replay.reply, lastSpoken: nil), "\(ask) \(replay.reply)")
            XCTAssertEqual(replay.evidence?.focusedEmail?.fromName, "Murray Mitchell", ask)
            XCTAssertTrue(replay.reply.contains("Murray Mitchell"), "\(ask) \(replay.reply)")
            XCTAssertTrue(
                replay.reply.localizedCaseInsensitiveContains("302")
                    || replay.reply.localizedCaseInsensitiveContains("georgia")
                    || replay.reply.localizedCaseInsensitiveContains("closing"),
                "\(ask) \(replay.reply)"
            )
            XCTAssertFalse(replay.notes.contains("live Grok"), ask)
        }

        for ask in Self.sandyAskFamily {
            let replay = VoiceTurnReplay.play(utterance: ask, context: desk)
            XCTAssertTrue(["desk-thread", "desk-person"].contains(replay.intent), "\(ask) → \(replay.intent)")
            XCTAssertTrue(replay.attachesEmailCard, ask)
            XCTAssertFalse(replay.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ask)
            XCTAssertEqual(replay.evidence?.focusedEmail?.fromName, "Sandy Woodcock", ask)
            XCTAssertTrue(replay.reply.contains("Sandy Woodcock"), "\(ask) \(replay.reply)")
            XCTAssertTrue(replay.reply.localizedCaseInsensitiveContains("gut"), "\(ask) \(replay.reply)")
        }
    }

    // MARK: - helpers

    private static func combine(leftover: String, ask: String) -> String {
        if leftover.hasSuffix(",") || leftover.hasSuffix(".") {
            return "\(leftover) \(ask)"
        }
        return "\(leftover) \(ask)"
    }

    private static func acceptedKeepsLeftoverPrefix(_ accepted: String, leftover: String) -> Bool {
        let trimmed = accepted.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = leftover
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,!?;:")))
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
        let head = trimmed
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
        return head == stem || head.hasPrefix(stem + ",") || head.hasPrefix(stem + ".") || head.hasPrefix(stem + " ")
    }
}
