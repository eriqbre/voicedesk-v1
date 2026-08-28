import XCTest
@testable import VoiceDeskLogic

final class VoiceRegressionReplayTests: XCTestCase {
    func testAllSeedFixturesReplay() throws {
        let fixtures = try Self.loadSeedFixtures()
        XCTAssertGreaterThanOrEqual(fixtures.count, 25, "seed utterances are missing")
        for fixture in fixtures {
            let replay = VoiceTurnReplay.play(fixture)
            let ask = fixture.userTranscript

            XCTAssertTrue(
                fixture.intentsThatPass.contains(replay.intent),
                "\(ask): intent \(replay.intent) not in \(fixture.intentsThatPass.sorted())"
            )

            if fixture.isGeneralRoute {
                XCTAssertFalse(replay.ownsDeskTurn, "\(ask): general must not own the desk turn")
                XCTAssertFalse(replay.looksLikeMailAsk, "\(ask): general is not a mail ask")
                XCTAssertFalse(replay.attachesEmailCard, "\(ask): general must not attach an email card")
                XCTAssertNotEqual(replay.intent, "desk-person", ask)
                XCTAssertNotEqual(replay.intent, "inbox-overview", ask)
                XCTAssertNil(replay.gmailQuery, "\(ask): general must not invent a Gmail q=")
                XCTAssertFalse(replay.shouldSearchGmail, ask)
            } else {
                XCTAssertTrue(replay.ownsDeskTurn || replay.looksLikeMailAsk || replay.evidence != nil, ask)
                if fixture.intent == "inbox-overview" {
                    XCTAssertTrue(replay.stickyCleared, "\(ask): inbox-overview must clear sticky")
                    XCTAssertNil(replay.evidence?.focusedEmail, ask)
                    XCTAssertGreaterThanOrEqual(replay.cardLabels.count, 2, ask)
                }
                let lowerAsk = fixture.userTranscript.lowercased()
                let namedMurray = lowerAsk.contains("murray") && fixture.intent != "inbox-overview"
                let namedLauren = lowerAsk.contains("lauren") || lowerAsk.contains("laren")
                if namedMurray || namedLauren {
                    XCTAssertNotEqual(replay.intent, "inbox-overview", ask)
                    XCTAssertFalse(
                        replay.cardLabels.contains { $0.contains("Greenacre") },
                        "\(ask): named person must not attach Greenacre \(replay.cardLabels)"
                    )
                    if namedMurray, !replay.shouldSearchGmail {
                        XCTAssertTrue(
                            replay.cardLabels.contains { $0.contains("Murray Mitchell") },
                            "\(ask): \(replay.cardLabels)"
                        )
                    }
                    if namedLauren, !replay.shouldSearchGmail {
                        XCTAssertTrue(
                            replay.cardLabels.contains {
                                $0.contains("Laren") || $0.contains("Lauren")
                            } || replay.reply.contains("Which one"),
                            "\(ask): \(replay.cardLabels) \(replay.reply)"
                        )
                    }
                    let stickyName = (fixture.stickyFromName ?? "").lowercased()
                    if fixture.hadFocusedEmail == true,
                       !stickyName.contains("murray"), !stickyName.contains("lauren"), !stickyName.contains("laren"),
                       !stickyName.isEmpty {
                        XCTAssertTrue(replay.stickyCleared, "\(ask): named person must clear mismatched sticky")
                    }
                }
            }

            for note in fixture.requiredNotes ?? [] {
                XCTAssertTrue(replay.notes.contains(note), "\(ask): missing note \(note) in \(replay.notes)")
            }
            if !fixture.cardsAttached.isEmpty {
                XCTAssertEqual(replay.cardLabels, fixture.cardsAttached, ask)
            }
            if fixture.shouldAssertReply {
                if fixture.intent == "inbox-overview" {
                    if ConversationPresence.wantsInboxSummary(ask) {
                        XCTAssertTrue(
                            InboxGlance.isShortSpokenSummary(replay.reply),
                            "\(ask) spoken: \(replay.reply)"
                        )
                    } else if !ConversationPresence.wantsInboxCount(ask) {
                        XCTAssertFalse(
                            replay.reply.isEmpty,
                            "fd4a772 \(ask) empty reply + cards"
                        )
                        XCTAssertTrue(
                            InboxGlance.isShortSpokenSummary(replay.reply),
                            "\(ask) spoken: \(replay.reply)"
                        )
                        XCTAssertNotEqual(replay.reply, "Here they are.", ask)
                    }
                } else {
                    XCTAssertEqual(replay.reply, fixture.assistantReply, ask)
                }
            }
            if replay.evidence?.hidesSpokenSummaryOnScreen == true {
                XCTAssertTrue(
                    InboxGlance.isShortOnScreenLeadIn(replay.onScreen),
                    "\(ask): cards-only must not print Eve: \(replay.onScreen)"
                )
                if !replay.reply.isEmpty {
                    XCTAssertNotEqual(replay.onScreen, replay.reply, ask)
                }
            }

            let haystack = (replay.notes + replay.cardLabels + [replay.gmailQuery ?? "", replay.reply, replay.intent])
                .joined(separator: "\n")
                .lowercased()
            for banned in fixture.forbiddenSubstrings ?? [] {
                XCTAssertFalse(
                    haystack.contains(banned.lowercased()),
                    "\(ask): found \(banned) in \(haystack)"
                )
            }
        }
    }

    func testPromoteAcceptsRawVoiceLogLine() throws {
        let entry = VoiceInteractionEntry(
            source: "voice",
            userTranscript: "What year did John Wick get released",
            intent: "general",
            routingNotes: [],
            cardsAttached: [],
            assistantReply: "2014 — Grok can say this; CI does not assert it.",
            voicePath: "Eve realtime"
        )
        guard let data = VoiceDebugLogPaths.jsonlLineData(for: entry),
              let line = String(data: data, encoding: .utf8)
        else {
            return XCTFail("expected a JSONL line")
        }
        let fixture = try VoiceRegressionFixture.promote(logLine: line)
        XCTAssertEqual(fixture.userTranscript, entry.userTranscript)
        XCTAssertEqual(fixture.intent, "general")
        XCTAssertFalse(fixture.shouldAssertReply)
        let replay = VoiceTurnReplay.play(fixture)
        XCTAssertEqual(replay.intent, "general")
        XCTAssertFalse(replay.attachesEmailCard)
    }

    func testSeedFixturesAreSanitized() throws {
        for fixture in try Self.loadSeedFixtures() {
            XCTAssertTrue(
                fixture.piiWarnings().isEmpty,
                "\(fixture.userTranscript): \(fixture.piiWarnings())"
            )
        }
    }

    func testWhenWasMurraysLastEmailReplayForbidsWasMurrayQuery() {
        let ask = "When was Murray's last email sent?"
        XCTAssertEqual(GmailSearchQuery.query(from: ask), "from:murray")
        let replay = VoiceTurnReplay.play(
            utterance: ask,
            context: VoiceRegressionDesk.connected,
            focusedEmail: VoiceRegressionDesk.steve
        )
        XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), replay.intent)
        XCTAssertTrue(replay.cardLabels.contains { $0.contains("Murray Mitchell") }, "\(replay.cardLabels)")
        XCTAssertTrue(
            replay.notes.contains(where: { $0.contains("from:murray") })
                || (replay.gmailQuery ?? "").contains("from:murray"),
            "\(replay.notes) \(replay.gmailQuery ?? "")"
        )
        let haystack = (replay.notes + [replay.gmailQuery ?? ""]).joined(separator: "\n").lowercased()
        XCTAssertFalse(haystack.contains("was murray"), haystack)
        XCTAssertFalse(haystack.contains("from:(\"was murray\")"), haystack)
    }

    func testHowAboutMurraysLatestEmailReplayForbidsHowMurrayQuery() {
        let ask = "Okay, perfect. How about Murray's latest email?"
        XCTAssertEqual(GmailSearchQuery.query(from: ask), "from:murray")
        let replay = VoiceTurnReplay.play(
            utterance: ask,
            context: VoiceRegressionDesk.connected,
            focusedEmail: VoiceRegressionDesk.steve
        )
        XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), replay.intent)
        XCTAssertTrue(replay.cardLabels.contains { $0.contains("Murray Mitchell") }, "\(replay.cardLabels)")
        XCTAssertTrue(
            replay.notes.contains(where: { $0.contains("from:murray") })
                || (replay.gmailQuery ?? "").contains("from:murray"),
            "\(replay.notes) \(replay.gmailQuery ?? "")"
        )
        let haystack = (replay.notes + [replay.gmailQuery ?? ""]).joined(separator: "\n").lowercased()
        XCTAssertFalse(haystack.contains("how murray"), haystack)
        XCTAssertFalse(haystack.contains("from:(\"how murray\")"), haystack)
    }

    func testLatestEmailsFamilyAfterEricSearchShowsInboxNotEric() {
        let desk = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [VoiceRegressionDesk.laren])
        )
        let ericHits = [
            VoiceRegressionDesk.ericGross,
            VoiceRegressionDesk.ericGross
        ]
        let latestFamily = [
            "Show me my latest emails.",
            "see my latest emails",
            "Just show me my latest emails.",
            "latest emails",
            "Can you pull my latest emails?"
        ]
        for ask in latestFamily {
            let replay = VoiceTurnReplay.play(
                utterance: ask,
                context: desk,
                focusedEmail: VoiceRegressionDesk.ericGross,
                pendingSearchClarify: true,
                clarifyMatches: ericHits
            )
            XCTAssertEqual(replay.intent, "inbox-overview", ask)
            XCTAssertNotEqual(replay.intent, "desk-person", ask)
            XCTAssertTrue(replay.stickyCleared, ask)
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Laren Cole") },
                "\(ask) → \(replay.cardLabels)"
            )
            XCTAssertFalse(
                replay.cardLabels.contains { $0.contains("Eric") },
                "\(ask) must not attach Eric search hits: \(replay.cardLabels)"
            )
            XCTAssertFalse(replay.reply.localizedCaseInsensitiveContains("Eric Gross"), ask)
        }
    }

    func testInboxOverviewThenMurraySummaryIsMurrayNotGreenacre() {
        let overview = VoiceTurnReplay.play(
            utterance: "Uh, that's cool. Just show me my latest emails.",
            context: VoiceRegressionDesk.greenacreFirst
        )
        XCTAssertTrue(overview.stickyCleared)
        XCTAssertNil(overview.evidence?.focusedEmail)
        XCTAssertTrue(overview.cardLabels.contains { $0.contains("Greenacre") })

        let murrayAsk = "Give me a summary of Murray's last email."
        XCTAssertEqual(GmailSearchQuery.query(from: murrayAsk), "from:murray")
        let replay = VoiceTurnReplay.play(
            utterance: murrayAsk,
            context: VoiceRegressionDesk.greenacreFirst,
            focusedEmail: nil
        )
        XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), replay.intent)
        XCTAssertTrue(replay.cardLabels.contains { $0.contains("Murray Mitchell") }, "\(replay.cardLabels)")
        XCTAssertFalse(replay.cardLabels.contains { $0.contains("Greenacre") }, "\(replay.cardLabels)")
        XCTAssertEqual(replay.evidence?.focusedEmail?.fromName, "Murray Mitchell")
        XCTAssertNotEqual(replay.shouldSearchGmail, true)
        XCTAssertTrue(
            replay.notes.contains(where: { $0.contains("from:murray") })
                || (replay.gmailQuery ?? "").contains("from:murray"),
            "\(replay.notes)"
        )
    }

    func testLaurenAfterGreenacreStickyMatchesLarenAndClearsSticky() {
        let ask = "Give me a summary of Lauren's latest, latest email."
        XCTAssertEqual(GmailSearchQuery.query(from: ask), "from:lauren")
        let replay = VoiceTurnReplay.play(
            utterance: ask,
            context: VoiceRegressionDesk.greenacreFirst,
            focusedEmail: VoiceRegressionDesk.greenacre
        )
        XCTAssertTrue(replay.stickyCleared, "\(replay.notes)")
        XCTAssertTrue(replay.notes.contains("sticky cleared"), "\(replay.notes)")
        XCTAssertFalse(replay.notes.contains(where: { $0.contains("sticky reused") }), "\(replay.notes)")
        XCTAssertTrue(replay.cardLabels.contains { $0.contains("Laren Cole") }, "\(replay.cardLabels)")
        XCTAssertFalse(replay.cardLabels.contains { $0.contains("Greenacre") }, "\(replay.cardLabels)")
        XCTAssertEqual(replay.evidence?.focusedEmail?.fromName, "Laren Cole")
        XCTAssertTrue(
            replay.notes.contains(where: { $0.contains("from:lauren") }),
            "\(replay.notes)"
        )
    }

    func testNamedMurrayWithNoCacheHitSearchesAndDoesNotAttachGreenacre() {
        let ask = "Give me a summary of Murray's last email."
        let replay = VoiceTurnReplay.play(
            utterance: ask,
            context: VoiceRegressionDesk.greenacreOnly,
            focusedEmail: VoiceRegressionDesk.greenacre
        )
        XCTAssertTrue(replay.shouldSearchGmail)
        XCTAssertEqual(replay.gmailQuery, "from:murray")
        XCTAssertTrue(replay.stickyCleared)
        XCTAssertTrue(replay.cardLabels.isEmpty, "\(replay.cardLabels)")
        XCTAssertNil(replay.evidence?.focusedEmail)
        XCTAssertFalse(replay.reply.contains("Greenacre"))
        XCTAssertEqual(replay.reply, ConversationPresence.gmailSearchingBeat)
    }

    func testClarifyPickPhrasesReplayNewestMurrayNotGeneral() {
        for phrase in ["The last one.", "The most recent one.", "the latest", "that one"] {
            let replay = VoiceTurnReplay.play(
                utterance: phrase,
                context: DeskContext(isConnected: true, snapshot: VoiceRegressionDesk.murraySeveralSnapshot),
                pendingSearchClarify: true,
                clarifyMatches: VoiceRegressionDesk.murraySeveralMatches
            )
            XCTAssertTrue(replay.ownsDeskTurn, phrase)
            XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), "\(phrase) → \(replay.intent)")
            XCTAssertNotEqual(replay.intent, "general", "\(phrase) must not yield to live Grok")
            XCTAssertEqual(replay.evidence?.focusedEmail?.providerID, "fixture-murray-new", phrase)
            XCTAssertTrue(
                replay.cardLabels.contains { $0.contains("Murray Mitchell") && $0.contains("Walk-through today") },
                "\(phrase) → \(replay.cardLabels)"
            )
            XCTAssertFalse(replay.cardLabels.contains { $0.contains("Greenacre") }, phrase)
            XCTAssertTrue(replay.notes.contains("clarify pick"), "\(phrase) → \(replay.notes)")
            XCTAssertFalse(replay.notes.contains("live Grok"), "\(phrase) → \(replay.notes)")
        }
    }

    func testDogfoodLaurenEricUtterancesStayDesk() {
        let fleemanAsk = VoiceTurnReplay.play(
            utterance: "Hey, give me a summary of the email from Lauren about Fleeman Road.",
            context: VoiceRegressionDesk.laurenSeveral
        )
        XCTAssertTrue(fleemanAsk.ownsDeskTurn)
        XCTAssertNotEqual(fleemanAsk.intent, "general")
        XCTAssertEqual(fleemanAsk.cardLabels, ["email:Laren Jansen:Fleeman Road disclosures"])
        XCTAssertFalse(fleemanAsk.cardLabels.contains { $0.contains("Family Fun Day") })
        XCTAssertFalse(fleemanAsk.reply.localizedCaseInsensitiveContains("which one"))

        let regarding = VoiceTurnReplay.play(
            utterance: "The one regarding Fleeman Road.",
            context: VoiceRegressionDesk.laurenSeveral,
            pendingSearchClarify: true,
            clarifyMatches: [VoiceRegressionDesk.alexAndLaren, VoiceRegressionDesk.larenJansen],
            priorSearchAsk: "Hey, give me a summary of the email from Lauren about Fleeman Road."
        )
        XCTAssertTrue(regarding.ownsDeskTurn)
        XCTAssertNotEqual(regarding.intent, "general")
        XCTAssertTrue(regarding.cardLabels.contains { $0.contains("Laren Jansen") })
        XCTAssertFalse(regarding.cardLabels.contains { $0.contains("Family Fun Day") })
        XCTAssertFalse(regarding.notes.contains("live Grok"))

        let lauren = VoiceTurnReplay.play(
            utterance: "What's the latest email from Lauren?",
            context: VoiceRegressionDesk.laurenSeveral
        )
        XCTAssertTrue(lauren.ownsDeskTurn)
        XCTAssertNotEqual(lauren.intent, "general")
        XCTAssertTrue(lauren.cardLabels.contains { $0.contains("Alex & Laren") })
        XCTAssertTrue(lauren.cardLabels.contains { $0.contains("Laren Jansen") })
        XCTAssertEqual(lauren.reply, ConversationPresence.gmailSearchSeveralReply)

        let refine = VoiceTurnReplay.play(
            utterance: "No. Not that one. I'm looking for the one that Lauren wrote regarding Fleeman Road.",
            context: VoiceRegressionDesk.laurenSeveral,
            focusedEmail: VoiceRegressionDesk.alexAndLaren
        )
        XCTAssertTrue(refine.ownsDeskTurn)
        XCTAssertNotEqual(refine.intent, "general")
        XCTAssertTrue(refine.cardLabels.contains { $0.contains("Laren Jansen") })
        XCTAssertFalse(refine.cardLabels.contains { $0.contains("Family Fun Day") })

        let yeah = VoiceTurnReplay.play(
            utterance: "Yeah",
            context: VoiceRegressionDesk.laurenSeveral,
            focusedEmail: VoiceRegressionDesk.larenJansen,
            pendingSenderRefine: true
        )
        XCTAssertTrue(yeah.ownsDeskTurn)
        XCTAssertNotEqual(yeah.intent, "general")

        let eric = VoiceTurnReplay.play(
            utterance: "When was Eric's last email?",
            context: VoiceRegressionDesk.ericWithGross
        )
        XCTAssertEqual(eric.evidence?.focusedEmail?.fromName, "Eric Gross")
        XCTAssertFalse(eric.cardLabels.contains { $0.contains("Eriq Cole") })
    }

    func testDidJohnTriviaDoesNotBuildFromJohn() {
        let replay = VoiceTurnReplay.play(
            utterance: "did John Wick get released",
            context: VoiceRegressionDesk.connected,
            focusedEmail: VoiceRegressionDesk.murray
        )
        XCTAssertEqual(replay.intent, "general")
        XCTAssertNil(replay.gmailQuery)
        XCTAssertFalse(GmailSearchQuery.hasSenderPattern("did John Wick get released"))
        XCTAssertNil(GmailSearchQuery.plan(from: "did John Wick get released"))
        XCTAssertFalse((replay.gmailQuery ?? "").contains("from:john"))
    }

    private static func loadSeedFixtures() throws -> [VoiceRegressionFixture] {
        let urls = try fixtureURLs()
        XCTAssertFalse(urls.isEmpty, "no voice-regression JSONL fixtures on disk")
        var all: [VoiceRegressionFixture] = []
        for url in urls {
            let text = try String(contentsOf: url, encoding: .utf8)
            all.append(contentsOf: try VoiceRegressionFixture.decodeJSONL(text))
        }
        return all
    }

    private static func fixtureURLs() throws -> [URL] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            let candidate = url.appendingPathComponent("Fixtures/voice-regression")
            if let found = jsonlFiles(in: candidate), !found.isEmpty {
                return found
            }
            let nested = url.appendingPathComponent("VoiceDeskLogic/Tests/VoiceDeskLogicTests/Fixtures/voice-regression")
            if let found = jsonlFiles(in: nested), !found.isEmpty {
                return found
            }
            url.deleteLastPathComponent()
        }
        return []
    }

    private static func jsonlFiles(in directory: URL) -> [URL]? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        let found = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return found
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
