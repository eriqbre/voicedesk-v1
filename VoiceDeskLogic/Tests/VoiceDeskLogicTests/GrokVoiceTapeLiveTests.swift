import XCTest
@testable import VoiceDeskLogic

/// Live Grok speech tape. Skips unless `XAI_API_KEY` or `VOICEDESK_XAI_API_KEY` is set.
/// Never fails CI for a missing key. Never reads `Secrets.plist`.
///
/// Desk-owned live turns (inbox / Murray / calendar / clarify) only require first
/// audio and no iOS-app / client-jump meta. Honest disconnected “no live
/// calendar/inbox” is correct — this tape has no AppModel. Intent stays on
/// Linux `VoiceTurnReplay`.
///
///     XAI_API_KEY=... swift test --package-path VoiceDeskLogic --filter GrokVoiceTape
final class GrokVoiceTapeLiveTests: XCTestCase {
    func testLiveTapeDogfoodPhrasesSpeak() async throws {
        guard let apiKey = GrokVoiceTape.apiKeyFromEnvironment() else {
            throw XCTSkip("XAI_API_KEY / VOICEDESK_XAI_API_KEY not set — live tape skipped")
        }
        let directory = try XCTUnwrap(GrokVoiceTapeTests.seedDirectory())
        let all = try GrokVoiceTape.loadFixtures(from: directory)
        let fixtures = GrokVoiceTape.liveSubset(all)
        XCTAssertEqual(Set(fixtures.map(\.family)).count, 5, "live tape must hit one of each family")
        XCTAssertFalse(fixtures.isEmpty)

        continueAfterFailure = true
        for fixture in fixtures {
            var pcm: Data?
            if let url = GrokVoiceTape.resolvePCMURL(fixture: fixture, directory: directory) {
                pcm = try GrokVoiceTape.loadPCM16LE24kMono(from: url)
            }
            let result = await GrokVoiceTape.run(fixture: fixture, pcm: pcm, apiKey: apiKey)
            let audio = result.firstAudioDeltaMilliseconds.map(String.init) ?? "none"
            print(
                "TAPE \(fixture.id) pass=\(result.passed) audioMS=\(audio) user=\(result.userTranscript ?? "") assistant=\(result.assistantText)"
            )
            XCTAssertTrue(
                result.passed,
                "\(fixture.id): \(result.failures.map(\.description).joined(separator: "; ")) assistant=\(result.assistantText) errors=\(result.errors) audioMS=\(result.firstAudioDeltaMilliseconds as Any)"
            )
            XCTAssertNotNil(result.firstAudioDeltaMilliseconds, fixture.id)
            XCTAssertFalse(GrokVoiceTape.isLiveMetaHandoff(result.assistantText), fixture.id)
            if fixture.family == "general" {
                XCTAssertFalse(GrokVoiceTape.isDeskRefusal(result.assistantText), fixture.id)
                XCTAssertFalse(
                    result.assistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(fixture.id): general must answer"
                )
            }
        }
    }
}
