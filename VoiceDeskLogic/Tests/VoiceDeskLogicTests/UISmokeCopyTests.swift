import Foundation
import XCTest
@testable import VoiceDeskLogic

/// `VoiceDeskUITests` only runs on `macos-15` behind `workflow_dispatch`, so a
/// renamed accessibility identifier or reworded string can sit broken on `main`
/// indefinitely — that is how the Connect Google coach copy drifted until the
/// launch smoke test asserted a label no view rendered.
///
/// These tests read `LaunchSmokeTests.swift` and check that every literal it
/// expects to find still exists somewhere in the app or logic sources. Substring
/// presence does not prove the string reaches the screen, so this is not a
/// replacement for the Simulator run; it only catches deletions, renames, and
/// rewordings, which is the whole failure mode.
final class UISmokeCopyTests: XCTestCase {
    func testEveryIdentifierTheLaunchSmokeExpectsExistsInSources() throws {
        let expected = try positiveLiterals(
            patterns: [
                #"\.(?:buttons|staticTexts|navigationBars|descendants\(matching: \.any\))\["([^"]+)"\]"#,
                #"waitForCard\("([^"]+)"\)"#
            ]
        )
        XCTAssertFalse(expected.isEmpty, "expected to find element lookups in LaunchSmokeTests.swift")

        let sources = try sourceCorpus()
        for literal in expected {
            // Match the quoted literal, not a substring: renaming "card.listing"
            // to "card.listingV2" must fail rather than match on the prefix.
            XCTAssertTrue(
                sources.contains("\"\(literal)\""),
                "LaunchSmokeTests looks up \"\(literal)\" but no app or logic source declares it"
            )
        }
    }

    func testEveryCopyStringTheLaunchSmokeExpectsExistsInSources() throws {
        let expected = try positiveLiterals(patterns: [#"label CONTAINS '([^']+)'"#])
        XCTAssertFalse(expected.isEmpty, "expected to find label predicates in LaunchSmokeTests.swift")

        let sources = try sourceCorpus()
        for literal in expected {
            XCTAssertTrue(
                sources.contains(literal),
                "LaunchSmokeTests waits for copy containing \"\(literal)\" but no app or logic source contains it"
            )
        }
    }

    /// The unprompted offer and the "how do I connect?" answer are different
    /// beats. Collapsing them is what broke the smoke test before.
    func testConnectCoachNamesThePayoffAndStaysDistinctFromTheHowTo() {
        XCTAssertNotEqual(ConversationPresence.connectCoach, ConversationPresence.connectHowToReply)
        let coach = ConversationPresence.connectCoach.lowercased()
        for word in ["inbox", "calendar", "tasks"] {
            XCTAssertTrue(coach.contains(word), "coach should name \(word) as the payoff of connecting")
        }
        XCTAssertTrue(ConversationPresence.connectHowToReply.contains("Tap Connect Google"))
    }

    // MARK: - Helpers

    /// Literals the smoke test expects to be present. A lookup on an
    /// `XCTAssertFalse` line asserts absence, so it is not required to exist.
    private func positiveLiterals(patterns: [String]) throws -> Set<String> {
        let smoke = try XCTUnwrap(
            repoFile("VoiceDeskUITests/LaunchSmokeTests.swift"),
            "LaunchSmokeTests.swift should sit next to VoiceDeskLogic"
        )
        var found: Set<String> = []
        for line in smoke.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.contains("XCTAssertFalse") { continue }
            for pattern in patterns {
                found.formUnion(captures(of: pattern, in: String(line)))
            }
        }
        return found
    }

    private func captures(of pattern: String, in line: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: line)
            else { return nil }
            return String(line[captured])
        }
    }

    private func sourceCorpus() throws -> String {
        var corpus = ""
        for directory in ["VoiceDesk", "VoiceDeskLogic/Sources"] {
            let root = try XCTUnwrap(repoDirectory(directory), "missing \(directory)")
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            while let url = files?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                corpus += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
        }
        XCTAssertFalse(corpus.isEmpty, "source corpus should not be empty")
        return corpus
    }

    private func repoFile(_ relative: String) -> String? {
        guard let url = repoURL(relative) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func repoDirectory(_ relative: String) -> URL? {
        repoURL(relative)
    }

    private func repoURL(_ relative: String) -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
