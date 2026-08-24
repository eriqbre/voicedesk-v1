import XCTest
@testable import VoiceDeskLogic

/// Live Grok speech tape. Skips unless `XAI_API_KEY` or `VOICEDESK_XAI_API_KEY` is set.
/// Never fails CI for a missing key. Never reads `Secrets.plist`.
///
///     XAI_API_KEY=... swift test --package-path VoiceDeskLogic --filter GrokVoiceTape
final class GrokVoiceTapeLiveTests: XCTestCase {
    func testLiveTapeDogfoodPhrasesSpeakWithoutDeskRefusal() async throws {
        guard let apiKey = GrokVoiceTape.apiKeyFromEnvironment() else {
            throw XCTSkip("XAI_API_KEY / VOICEDESK_XAI_API_KEY not set — live tape skipped")
        }
        let directory = try XCTUnwrap(GrokVoiceTapeTests.seedDirectory())
        let fixtures = try GrokVoiceTape.loadFixtures(from: directory)
        XCTAssertFalse(fixtures.isEmpty)

        for fixture in fixtures {
            var pcm: Data?
            if let url = GrokVoiceTape.resolvePCMURL(fixture: fixture, directory: directory) {
                pcm = try GrokVoiceTape.loadPCM16LE24kMono(from: url)
            }
            let result = await GrokVoiceTape.run(fixture: fixture, pcm: pcm, apiKey: apiKey)
            XCTAssertTrue(
                result.passed,
                "\(fixture.id): \(result.failures.map(\.description).joined(separator: "; ")) assistant=\(result.assistantText) errors=\(result.errors) audioMS=\(result.firstAudioDeltaMilliseconds as Any)"
            )
            XCTAssertNotNil(result.firstAudioDeltaMilliseconds, fixture.id)
            XCTAssertFalse(GrokVoiceTape.isDeskRefusal(result.assistantText), fixture.id)
        }
    }
}
