import XCTest
@testable import VoiceDeskLogic

final class GrokVoiceTapeTests: XCTestCase {
    func testAppendCommitCreateWireJSON() throws {
        XCTAssertEqual(
            GrokRealtime.appendAudioJSON(base64: "AQID"),
            #"{"type":"input_audio_buffer.append","audio":"AQID"}"#
        )
        XCTAssertEqual(GrokRealtime.commitAudioJSON(), #"{"type":"input_audio_buffer.commit"}"#)
        XCTAssertEqual(GrokRealtime.commitAudioObject()["type"] as? String, "input_audio_buffer.commit")

        let item = GrokRealtime.textItemObject("show me my latest emails")
        XCTAssertEqual(item["type"] as? String, "conversation.item.create")
        let payload = try XCTUnwrap(item["item"] as? [String: Any])
        XCTAssertEqual(payload["role"] as? String, "user")
        let parts = try XCTUnwrap(payload["content"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["type"] as? String, "input_text")
        XCTAssertEqual(parts.first?["text"] as? String, "show me my latest emails")

        let create = GrokRealtime.responseCreateObject()
        XCTAssertEqual(create["type"] as? String, "response.create")
        let response = try XCTUnwrap(create["response"] as? [String: Any])
        XCTAssertEqual(response["modalities"] as? [String], ["text", "audio"])

        for object in [item, create, GrokRealtime.commitAudioObject()] {
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertFalse(data.isEmpty)
            XCTAssertNotNil(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
    }

    func testSeedFixturesAreDogfoodPhrasesWithoutPCM() throws {
        let fixtures = try Self.loadSeedFixtures()
        XCTAssertEqual(fixtures.count, 5)
        XCTAssertEqual(fixtures.map(\.id), [
            "latest-emails",
            "murray-last-email",
            "calendar-this-week",
            "john-wick-year",
            "the-last-one"
        ])
        XCTAssertEqual(fixtures.map(\.utterance), [
            "show me my latest emails",
            "summarize Murray's last email",
            "what's on my calendar this week",
            "what year was John Wick released?",
            "the last one"
        ])
        XCTAssertTrue(fixtures.allSatisfy { !$0.hasPCM })
    }

    func testAPIKeyIsEnvironmentOnlyAndNeverLooksAtSecretsPlist() {
        XCTAssertNil(GrokVoiceTape.apiKeyFromEnvironment([:]))
        XCTAssertNil(GrokVoiceTape.apiKeyFromEnvironment(["XAI_API_KEY": "  "]))
        XCTAssertEqual(
            GrokVoiceTape.apiKeyFromEnvironment(["XAI_API_KEY": "xai-live"]),
            "xai-live"
        )
        XCTAssertEqual(
            GrokVoiceTape.apiKeyFromEnvironment(["VOICEDESK_XAI_API_KEY": "xai-alias"]),
            "xai-alias"
        )
        XCTAssertEqual(
            GrokVoiceTape.apiKeyFromEnvironment([
                "XAI_API_KEY": "primary",
                "VOICEDESK_XAI_API_KEY": "alias"
            ]),
            "primary"
        )
        XCTAssertEqual(GrokVoiceTape.environmentKeyNames, ["XAI_API_KEY", "VOICEDESK_XAI_API_KEY"])
        XCTAssertFalse(GrokVoiceTape.environmentKeyNames.contains("Secrets.plist"))
    }

    func testEvaluateFailsOnMissingAudioOrDeskRefusal() {
        XCTAssertEqual(
            GrokVoiceTape.evaluate(assistantText: "John Wick came out in 2014.", firstAudioDeltaMilliseconds: 420),
            []
        )
        XCTAssertEqual(
            GrokVoiceTape.evaluate(assistantText: "John Wick came out in 2014.", firstAudioDeltaMilliseconds: nil),
            [.noFirstAudio]
        )
        XCTAssertEqual(
            GrokVoiceTape.evaluate(assistantText: "John Wick came out in 2014.", firstAudioDeltaMilliseconds: 13_000),
            [.noFirstAudio]
        )
        XCTAssertEqual(
            GrokVoiceTape.evaluate(
                assistantText: "I’ll let the app handle that.",
                firstAudioDeltaMilliseconds: 300
            ),
            [.deskRefusal]
        )
        XCTAssertTrue(
            GrokVoiceTape.evaluate(
                assistantText: "I can’t pull that thread — not in the last sync.",
                firstAudioDeltaMilliseconds: nil
            ).contains(.noFirstAudio)
        )
        XCTAssertTrue(
            GrokVoiceTape.evaluate(
                assistantText: "I can’t pull that thread — not in the last sync.",
                firstAudioDeltaMilliseconds: nil
            ).contains(.deskRefusal)
        )
    }

    func testDeskRefusalReusesConversationPresenceDetectors() {
        XCTAssertTrue(GrokVoiceTape.isDeskRefusal("I’ll let the app handle that."))
        XCTAssertTrue(GrokVoiceTape.isDeskRefusal("I'll stay quiet — the iOS app handles Gmail."))
        XCTAssertTrue(GrokVoiceTape.isDeskRefusal("I cannot pull the full email."))
        XCTAssertTrue(ConversationPresence.isGrokDeskRefusal("I’ll let the app handle that."))
        XCTAssertTrue(ConversationPresence.isGrokDeskHandoff("I’ll let the app handle that."))
        XCTAssertFalse(GrokVoiceTape.isDeskRefusal("Murray wrote: Need you to notarize today."))
        XCTAssertFalse(GrokVoiceTape.isDeskRefusal("John Wick was released in 2014."))
    }

    func testPCM16WAVAndRawLoadAt24kMono() throws {
        var pcm = Data()
        for frame in 0..<2_400 {
            let sample = Int16(frame % 128)
            var little = sample.littleEndian
            withUnsafeBytes(of: &little) { pcm.append(contentsOf: $0) }
        }
        XCTAssertEqual(pcm.count, 4_800)

        let rawChunks = GrokRealtime.pcmAppendChunks(pcm, milliseconds: 100)
        XCTAssertEqual(rawChunks.count, 1)
        XCTAssertEqual(rawChunks[0].count, 4_800)

        let wav = Self.makeWAV(pcm: pcm, sampleRate: 24_000)
        XCTAssertEqual(try GrokVoiceTape.pcm16LE24kMono(from: wav), pcm)
        XCTAssertEqual(try GrokVoiceTape.pcm16LE24kMono(from: pcm), pcm)

        XCTAssertThrowsError(try GrokVoiceTape.pcm16LE24kMono(from: Self.makeWAV(pcm: pcm, sampleRate: 16_000)))
        XCTAssertThrowsError(try GrokVoiceTape.pcm16LE24kMono(from: Data([0x01])))
    }

    func testSessionUpdateStillPinsProductAudioContract() throws {
        let data = try GrokRealtime.sessionUpdateJSON()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try XCTUnwrap(object["session"] as? [String: Any])
        XCTAssertEqual(session["voice"] as? String, "eve")
        XCTAssertEqual((session["turn_detection"] as? [String: Any])?["type"] as? String, "server_vad")
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap((audio["input"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(input["type"] as? String, "audio/pcm")
        XCTAssertEqual(input["rate"] as? Int ?? (input["rate"] as? NSNumber)?.intValue, 24_000)
        XCTAssertEqual(GrokRealtime.realtimeURLString(), "wss://api.x.ai/v1/realtime?model=grok-voice-latest")
    }

    private static func loadSeedFixtures() throws -> [GrokVoiceTape.Fixture] {
        let directory = try XCTUnwrap(seedDirectory(), "grok-voice-tape fixtures missing")
        let fixtures = try GrokVoiceTape.loadFixtures(from: directory)
        XCTAssertFalse(fixtures.isEmpty)
        return fixtures
    }

    static func seedDirectory() -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            let candidate = url.appendingPathComponent("Fixtures/grok-voice-tape")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let nested = url.appendingPathComponent("VoiceDeskLogic/Tests/VoiceDeskLogicTests/Fixtures/grok-voice-tape")
            if FileManager.default.fileExists(atPath: nested.path) {
                return nested
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    private static func makeWAV(pcm: Data, sampleRate: Int) -> Data {
        var data = Data()
        func appendASCII(_ text: String) { data.append(contentsOf: text.utf8) }
        func append32(_ value: Int) {
            var little = UInt32(value).littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: Int) {
            var little = UInt16(value).littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        appendASCII("RIFF")
        append32(36 + pcm.count)
        appendASCII("WAVE")
        appendASCII("fmt ")
        append32(16)
        append16(1)
        append16(1)
        append32(sampleRate)
        append32(sampleRate * 2)
        append16(2)
        append16(16)
        appendASCII("data")
        append32(pcm.count)
        data.append(pcm)
        return data
    }
}
