import XCTest
@testable import VoiceDeskLogic

/// Linux fixtures for the Grok tape harness. Live socket is Elon-on-Mac
/// (`./scripts/replay-voice-tape.py`). No key → skip, never fail CI.
final class VoiceTapeHarnessTests: XCTestCase {
    func testManifestMatchesCatalogAndLatestEmailsRace() throws {
        let url = try XCTUnwrap(fixtureURL("manifest.json"))
        let data = try Data(contentsOf: url)
        let items = try JSONDecoder().decode([VoiceTape.Item].self, from: data)
        XCTAssertEqual(items, VoiceTape.catalog)

        let emails = items.filter { $0.intent == "inbox-overview" }
        XCTAssertEqual(emails.map(\.say), [
            "show my latest emails",
            "my latest emails",
            "okay show me my latest emails"
        ])
        for item in emails {
            let decision = VoiceTape.evaluate(item)
            XCTAssertTrue(decision.matches(item), item.say)
            XCTAssertEqual(decision.intent, "inbox-overview", item.say)
            XCTAssertFalse(decision.dropped, item.say)
        }
    }

    func testEchoBargeInSpeakingEmptyLastSpokenAcceptsEveryTape() {
        for item in VoiceTape.catalog {
            let decision = VoiceTape.evaluate(item)
            XCTAssertTrue(decision.accepted, item.say)
            XCTAssertFalse(decision.dropped, item.say)
            XCTAssertTrue(item.allowedIntents.contains(decision.intent), "\(item.say) → \(decision.intent)")
            XCTAssertNotEqual(decision.intent, "general", item.say)
        }
        let pair = VoiceTape.twoAskDecisions()
        XCTAssertTrue(pair.first.accepted)
        XCTAssertTrue(pair.second.accepted)
        XCTAssertEqual(pair.first.intent, "inbox-overview")
        XCTAssertEqual(pair.second.intent, "inbox-overview")
    }

    func testAppendAudioJSONAndSessionUpdateAreThePhoneWire() {
        XCTAssertEqual(
            GrokRealtime.appendAudioJSON(base64: "ABC+12/="),
            #"{"type":"input_audio_buffer.append","audio":"ABC+12/="}"#
        )
        let object = VoiceTape.sessionUpdateObject(contextName: "connected")
        XCTAssertEqual(object["type"] as? String, "session.update")
        let session = object["session"] as? [String: Any]
        let turn = session?["turn_detection"] as? [String: Any]
        XCTAssertEqual(turn?["type"] as? String, "server_vad")
        XCTAssertEqual(GrokRealtime.realtimeHost, "wss://api.x.ai/v1/realtime")
        XCTAssertEqual(GrokRealtime.sampleRate, 24_000)
    }

    func testPCM16WAVIsLittleEndianMono24k() {
        var samples = [Int16](repeating: 0, count: 24)
        samples[0] = 1234
        samples[1] = -1234
        let pcm = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let wav = VoiceTape.pcm16WAV(fromPCM16LE: pcm)
        XCTAssertEqual(String(data: wav[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(VoiceTape.pcm16LE(fromWAV: wav), pcm)
        XCTAssertEqual(wav[24], 0xC0)
        XCTAssertEqual(wav[25], 0x5D)
        XCTAssertEqual(wav[26], 0x00)
        XCTAssertEqual(wav[27], 0x00)
    }

    func testClose1000AfterAudioStartReconnects() {
        XCTAssertEqual(VoiceTape.stayLiveAfterClose1000(), .reconnect)
        XCTAssertNotEqual(
            VoiceTape.stayLiveAfterClose1000(userWantsVoiceOff: false, audioStarted: true),
            .stayIdle
        )
        XCTAssertEqual(
            VoiceTape.stayLiveAfterClose1000(userWantsVoiceOff: true, audioStarted: true),
            .stayIdle
        )
    }

    func testReplayScriptSkipsWithoutKeyAndHasOneCommand() throws {
        let script = try XCTUnwrap(repoFile("scripts/replay-voice-tape.py"))
        XCTAssertTrue(script.contains("./scripts/replay-voice-tape.py"))
        XCTAssertTrue(script.contains("EchoBargeIn"))
        XCTAssertTrue(script.contains("input_audio_buffer.append"))
        XCTAssertTrue(script.contains("session.update") || script.contains("session-update"))
        XCTAssertTrue(script.contains("Never prints the key") || script.contains("Never print"))
        XCTAssertTrue(script.contains("No BlackHole"))
        XCTAssertFalse(script.contains("via BlackHole"))
        XCTAssertTrue(script.contains("No simctl mic"))
        XCTAssertTrue(script.contains("skip: no XAI_API_KEY"))
        XCTAssertTrue(script.contains("args.dry_run or not load_api_key()"))
        XCTAssertTrue(VoiceTape.shouldSkipLive(hasAPIKey: false))
        XCTAssertTrue(VoiceTape.shouldSkipLive(hasAPIKey: true, dryRun: true))
        XCTAssertFalse(VoiceTape.shouldSkipLive(hasAPIKey: true, dryRun: false))
    }

    func testNamedKatherineIsDeskOwnedOnTheTapeCatalog() {
        for ask in GrokSpeakingEmptyEchoWalk.namedKatherineFamily {
            let walk = GrokSpeakingEmptyEchoWalk.race(
                ask: ask,
                context: VoiceRegressionDesk.massimoCalendar
            )
            XCTAssertTrue(walk.accepted, ask)
            XCTAssertTrue(["desk-person", "desk-thread"].contains(walk.intent), "\(ask) → \(walk.intent)")
            XCTAssertNotEqual(walk.intent, "dropped", ask)
            XCTAssertNotEqual(walk.intent, "general", ask)
        }
    }

    private func fixtureURL(_ name: String) -> URL? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            url.deleteLastPathComponent()
            let candidate = url
                .appendingPathComponent("VoiceDeskLogicTests/Fixtures/voice-tapes")
                .appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url
                .appendingPathComponent("VoiceDeskLogic/Tests/VoiceDeskLogicTests/Fixtures/voice-tapes")
                .appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func repoFile(_ relative: String) -> String? {
        guard let url = repoURL(relative) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
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

extension VoiceTape {
    static func twoAskDecisions() -> (first: Decision, second: Decision) {
        let first = catalog[0]
        let second = catalog[1]
        return (evaluate(first), evaluate(second))
    }
}
