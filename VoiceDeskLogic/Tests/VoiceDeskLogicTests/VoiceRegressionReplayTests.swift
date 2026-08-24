import XCTest
@testable import VoiceDeskLogic

final class VoiceRegressionReplayTests: XCTestCase {
    func testAllSeedFixturesReplay() throws {
        let fixtures = try Self.loadSeedFixtures()
        XCTAssertGreaterThanOrEqual(fixtures.count, 16, "seed utterances are missing")
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
                if fixture.userTranscript.lowercased().contains("murray"),
                   fixture.intent != "inbox-overview" {
                    XCTAssertFalse(replay.stickyCleared, ask)
                    XCTAssertTrue(
                        replay.cardLabels.contains { $0.contains("Murray Mitchell") },
                        "\(ask): \(replay.cardLabels)"
                    )
                    XCTAssertNotEqual(replay.intent, "inbox-overview", ask)
                }
            }

            for note in fixture.requiredNotes ?? [] {
                XCTAssertTrue(replay.notes.contains(note), "\(ask): missing note \(note) in \(replay.notes)")
            }
            if !fixture.cardsAttached.isEmpty {
                XCTAssertEqual(replay.cardLabels, fixture.cardsAttached, ask)
            }
            if fixture.shouldAssertReply {
                XCTAssertEqual(replay.reply, fixture.assistantReply, ask)
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
