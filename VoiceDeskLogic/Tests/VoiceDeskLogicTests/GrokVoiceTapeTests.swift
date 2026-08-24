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

    func testSeedFixturesAreSynonymFamilies() throws {
        let fixtures = try Self.loadSeedFixtures()
        XCTAssertGreaterThanOrEqual(fixtures.count, 20)
        XCTAssertTrue(fixtures.allSatisfy { !$0.hasPCM })

        let families = Dictionary(grouping: fixtures, by: \.family)
        for name in [
            "inbox-overview",
            "named-person",
            "clarify-pick-newest",
            "calendar-overview",
            "general"
        ] {
            let group = try XCTUnwrap(families[name], "missing family \(name)")
            XCTAssertGreaterThanOrEqual(group.count, 4, name)
            XCTAssertFalse(Set(group.map(\.utterance)).count < group.count, "\(name) has duplicate utterances")
        }

        let live = GrokVoiceTape.liveSubset(fixtures)
        XCTAssertEqual(Set(live.map(\.family)).count, 5, "live subset must hit every family")
        XCTAssertLessThan(live.count, fixtures.count)
        XCTAssertTrue(live.allSatisfy(\.runLive))
        XCTAssertEqual(live.filter { $0.family == "general" }.count, 1)
        XCTAssertTrue(live.filter { $0.family != "general" }.allSatisfy(\.isDeskOwnedFamily))
    }

    func testSynonymFamiliesReplayExpectedIntent() throws {
        let fixtures = try Self.loadSeedFixtures()
        for fixture in fixtures {
            let replay = GrokVoiceTape.replay(fixture)
            let ask = fixture.utterance
            XCTAssertTrue(
                fixture.intentsThatPass.contains(replay.intent),
                "\(fixture.family) \(ask): intent \(replay.intent) not in \(fixture.intentsThatPass.sorted())"
            )
            XCTAssertFalse(GrokVoiceTape.isDeskRefusal(replay.reply), "\(ask): \(replay.reply)")
            XCTAssertFalse(replay.notes.contains("live Grok"), ask)

            let haystack = (replay.notes + replay.cardLabels + [replay.gmailQuery ?? "", replay.reply, replay.intent])
                .joined(separator: "\n")
                .lowercased()
            XCTAssertFalse(haystack.contains("ios app"), "\(ask): \(haystack)")
            XCTAssertFalse(haystack.contains("let the app handle"), "\(ask): \(haystack)")
            XCTAssertFalse(haystack.contains("i'll stay quiet"), "\(ask): \(haystack)")

            switch fixture.family {
            case "inbox-overview":
                XCTAssertEqual(replay.intent, "inbox-overview", ask)
                XCTAssertTrue(replay.stickyCleared, ask)
                XCTAssertGreaterThanOrEqual(replay.cardLabels.count, 2, "\(ask): \(replay.cardLabels)")
                XCTAssertFalse(replay.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ask)
            case "named-person":
                XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), "\(ask) → \(replay.intent)")
                XCTAssertTrue(replay.cardLabels.contains { $0.contains("Murray Mitchell") }, "\(ask): \(replay.cardLabels)")
                XCTAssertFalse(replay.cardLabels.contains { $0.contains("Greenacre") }, "\(ask): \(replay.cardLabels)")
                XCTAssertTrue(replay.stickyCleared, ask)
                XCTAssertFalse(replay.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ask)
                XCTAssertFalse((replay.gmailQuery ?? "").contains("from:steve"), ask)
            case "clarify-pick-newest":
                XCTAssertTrue(replay.ownsDeskTurn, ask)
                XCTAssertNotEqual(replay.intent, "general", ask)
                XCTAssertEqual(replay.evidence?.focusedEmail?.providerID, "fixture-murray-new", ask)
                XCTAssertTrue(
                    replay.cardLabels.contains { $0.contains("Murray Mitchell") && $0.contains("Walk-through today") },
                    "\(ask): \(replay.cardLabels)"
                )
                XCTAssertFalse(replay.cardLabels.contains { $0.contains("Greenacre") }, ask)
            case "calendar-overview":
                XCTAssertEqual(replay.intent, "calendar", ask)
                XCTAssertFalse(replay.attachesEmailCard, ask)
                XCTAssertNil(replay.gmailQuery, ask)
                XCTAssertFalse(haystack.contains("from:"), "\(ask): \(haystack)")
                XCTAssertFalse(haystack.contains("inventing mail"), ask)
            case "general":
                XCTAssertEqual(replay.intent, "general", ask)
                XCTAssertFalse(replay.ownsDeskTurn, ask)
                XCTAssertFalse(replay.looksLikeMailAsk, ask)
                XCTAssertFalse(replay.attachesEmailCard, ask)
                XCTAssertNil(replay.gmailQuery, ask)
                XCTAssertFalse((replay.gmailQuery ?? "").contains("from:john"), ask)
            default:
                XCTFail("unknown family \(fixture.family)")
            }
        }
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
            GrokVoiceTape.evaluate(
                assistantText: "John Wick came out in 2014.",
                firstAudioDeltaMilliseconds: 420,
                family: "general"
            ),
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

    func testLiveEvaluateAllowsHonestDisconnectedDesk() {
        let calendarHonest =
            "I don't have live access to your calendar, so I can't pull what's actually scheduled."
        let murrayHonest = "I don't have the full thread on Murray."
        let inboxHonest = "I don't have live access to your inbox yet — that's the sample desk."
        let iosMeta = "I'll stay quiet — the iOS app handles Gmail."
        let clientJump = "The client will jump in for that."

        XCTAssertEqual(
            GrokVoiceTape.evaluate(
                assistantText: calendarHonest,
                firstAudioDeltaMilliseconds: 913,
                family: "calendar-overview"
            ),
            []
        )
        XCTAssertEqual(
            GrokVoiceTape.evaluate(
                assistantText: murrayHonest,
                firstAudioDeltaMilliseconds: 791,
                family: "named-person"
            ),
            []
        )
        XCTAssertEqual(
            GrokVoiceTape.evaluate(
                assistantText: inboxHonest,
                firstAudioDeltaMilliseconds: 853,
                family: "inbox-overview"
            ),
            []
        )
        XCTAssertEqual(
            GrokVoiceTape.evaluate(
                assistantText: "the last one — that's Murray's walk-through.",
                firstAudioDeltaMilliseconds: 824,
                family: "clarify-pick-newest"
            ),
            []
        )
        XCTAssertEqual(
            GrokVoiceTape.evaluate(
                assistantText: calendarHonest,
                firstAudioDeltaMilliseconds: nil,
                family: "calendar-overview"
            ),
            [.noFirstAudio]
        )
        XCTAssertEqual(
            GrokVoiceTape.evaluate(
                assistantText: iosMeta,
                firstAudioDeltaMilliseconds: 400,
                family: "calendar-overview"
            ),
            [.deskRefusal]
        )
        XCTAssertEqual(
            GrokVoiceTape.evaluate(
                assistantText: clientJump,
                firstAudioDeltaMilliseconds: 400,
                family: "inbox-overview"
            ),
            [.deskRefusal]
        )
        XCTAssertEqual(
            GrokVoiceTape.evaluate(
                assistantText: "I’ll let the app handle that.",
                firstAudioDeltaMilliseconds: 400,
                family: "named-person"
            ),
            [.deskRefusal]
        )
        XCTAssertEqual(
            GrokVoiceTape.evaluate(
                assistantText: calendarHonest,
                firstAudioDeltaMilliseconds: 400,
                family: "general"
            ),
            [.deskRefusal]
        )
        XCTAssertTrue(GrokVoiceTape.isDeskRefusal(calendarHonest))
        XCTAssertFalse(GrokVoiceTape.isLiveMetaHandoff(calendarHonest))
        XCTAssertFalse(GrokVoiceTape.isLiveMetaHandoff(murrayHonest))
        XCTAssertTrue(GrokVoiceTape.isLiveMetaHandoff(iosMeta))
        XCTAssertTrue(GrokVoiceTape.isLiveMetaHandoff(clientJump))
        XCTAssertTrue(GrokVoiceTape.isDeskOwnedFamily("calendar-overview"))
        XCTAssertTrue(GrokVoiceTape.isDeskOwnedFamily("inbox-overview"))
        XCTAssertTrue(GrokVoiceTape.isDeskOwnedFamily("named-person"))
        XCTAssertTrue(GrokVoiceTape.isDeskOwnedFamily("clarify-pick-newest"))
        XCTAssertFalse(GrokVoiceTape.isDeskOwnedFamily("general"))
    }

    func testDeskRefusalReusesConversationPresenceDetectors() {
        XCTAssertTrue(GrokVoiceTape.isDeskRefusal("I’ll let the app handle that."))
        XCTAssertTrue(GrokVoiceTape.isDeskRefusal("I'll stay quiet — the iOS app handles Gmail."))
        XCTAssertTrue(GrokVoiceTape.isDeskRefusal("I cannot pull the full email."))
        XCTAssertTrue(ConversationPresence.isGrokDeskRefusal("I’ll let the app handle that."))
        XCTAssertTrue(ConversationPresence.isGrokDeskHandoff("I’ll let the app handle that."))
        XCTAssertFalse(GrokVoiceTape.isDeskRefusal("Murray wrote: Need you to notarize today."))
        XCTAssertFalse(GrokVoiceTape.isDeskRefusal("John Wick was released in 2014."))
        XCTAssertTrue(GrokVoiceTape.isDeskRefusal("I don't have the full thread on Murray."))
        XCTAssertTrue(GrokVoiceTape.isDeskRefusal("I can't pull what's actually scheduled."))
        XCTAssertTrue(GrokVoiceTape.isLiveMetaHandoff("I'll stay quiet — the iOS app handles Gmail."))
        XCTAssertTrue(GrokVoiceTape.isLiveMetaHandoff("the client will jump in"))
        XCTAssertFalse(GrokVoiceTape.isLiveMetaHandoff("I don't have live access to your calendar."))
        XCTAssertFalse(GrokVoiceTape.isLiveMetaHandoff("I can't pull what's actually scheduled."))
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
