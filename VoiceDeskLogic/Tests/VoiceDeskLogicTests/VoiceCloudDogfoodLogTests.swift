import XCTest
@testable import VoiceDeskLogic

final class VoiceCloudDogfoodLogTests: XCTestCase {
    func testAppStoreReleaseGateIsOff() {
        XCTAssertFalse(VoiceDogfoodGate.allowsLogging(compileDebug: false, isTestFlight: false))
        XCTAssertTrue(VoiceDogfoodGate.allowsLogging(compileDebug: true, isTestFlight: false))
        XCTAssertTrue(VoiceDogfoodGate.allowsLogging(compileDebug: false, isTestFlight: true))
        XCTAssertFalse(VoiceDogfoodGate.isTestFlightReceipt(receiptLastPathComponent: "receipt"))
        XCTAssertTrue(VoiceDogfoodGate.isTestFlightReceipt(receiptLastPathComponent: "sandboxReceipt"))
        XCTAssertFalse(VoiceDogfoodGate.isTestFlightReceipt(receiptLastPathComponent: nil))
    }

    func testSerializeIncludesStickyFocusedPersonSearchAndErrors() throws {
        let entry = sampleEntry()
        guard let data = VoiceCloudLogCodec.jsonlLine(for: entry),
              let text = String(data: data, encoding: .utf8)
        else {
            return XCTFail("expected jsonl")
        }
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertEqual(text.filter { $0 == "\n" }.count, 1)
        XCTAssertTrue(text.contains("\"schemaVersion\":2"))
        XCTAssertTrue(text.contains("\"sticky\":\"reused\""))
        XCTAssertTrue(text.contains("John Madison"))
        XCTAssertTrue(text.contains("from:john"))
        XCTAssertTrue(text.contains("Murray"))
        XCTAssertTrue(text.contains("Eve realtime"))
        XCTAssertFalse(VoiceCloudLogRedactor.containsAudioKey(in: text))

        let decoded = try VoiceCloudLogCodec.jsonDecoder().decode(VoiceInteractionEntry.self, from: Data(text.utf8))
        XCTAssertEqual(decoded.userTranscript, entry.userTranscript)
        XCTAssertEqual(decoded.intent, "desk-person")
        XCTAssertEqual(decoded.sticky, .reused)
        XCTAssertEqual(decoded.focusedPerson, "John Madison")
        XCTAssertEqual(decoded.searchQuery, "from:john@coastal.test")
        XCTAssertEqual(decoded.errors, ["timeout talking to Eve"])
        XCTAssertEqual(decoded.cardsAttached, ["email:John Madison:Listing referral"])
    }

    func testLegacyJSONLDecodesWithoutNewKeys() throws {
        let legacy = """
        {"source":"voice","userTranscript":"hi","intent":"general","routingNotes":[],"cardsAttached":[],"assistantReply":"hey","voicePath":"AVSpeech"}
        """
        let decoded = try VoiceCloudLogCodec.jsonDecoder().decode(
            VoiceInteractionEntry.self,
            from: Data(legacy.utf8)
        )
        XCTAssertEqual(decoded.sticky, .none)
        XCTAssertNil(decoded.focusedPerson)
        XCTAssertEqual(decoded.errors, [])
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testRedactStripsSecretsAndEmailsKeepsTranscriptAndPerson() {
        let entry = VoiceInteractionEntry(
            source: "voice",
            userTranscript: "Okay, got it. Hey, can you give me a summary of Murray's latest email?",
            intent: "desk-person",
            sticky: .reused,
            focusedPerson: "John Madison",
            searchQuery: "from:john@coastal.com",
            routingNotes: ["sticky reused (John Madison)", "search from:john@coastal.com"],
            cardsAttached: ["email:John Madison:Listing referral"],
            assistantReply: "John Madison wrote about a listing referral. Call 813-555-0199.",
            voicePath: "Eve realtime",
            errors: [
                "Authorization: Bearer ghp_ABCDEFGHIJKLMNOPQRSTUVWX",
                "xai-supersecretkeyvalue",
                "failed for jane@example.com"
            ]
        )
        let redacted = VoiceCloudLogRedactor.redact(entry)
        XCTAssertEqual(
            redacted.userTranscript,
            "Okay, got it. Hey, can you give me a summary of Murray's latest email?"
        )
        XCTAssertEqual(redacted.focusedPerson, "John Madison")
        XCTAssertEqual(redacted.searchQuery, "from:john@redacted")
        XCTAssertTrue(redacted.routingNotes.contains("sticky reused (John Madison)"))
        XCTAssertEqual(redacted.cardsAttached, ["email:John Madison:Listing referral"])
        XCTAssertTrue(redacted.assistantReply.contains("John Madison"))
        XCTAssertFalse(redacted.assistantReply.contains("813-555-0199"))
        XCTAssertTrue(redacted.assistantReply.contains("[phone]"))
        let errors = redacted.errors.joined(separator: "\n")
        XCTAssertFalse(errors.contains("ghp_"))
        XCTAssertFalse(errors.contains("xai-super"))
        XCTAssertTrue(errors.contains("Bearer [redacted]"))
        XCTAssertTrue(errors.contains("jane@redacted"))
        XCTAssertEqual(
            VoiceCloudLogRedactor.redactHeaders([
                "Authorization": "Bearer ghp_ABCDEFGHIJKLMNOPQRSTUVWX",
                "X-VoiceDesk-Secret": "super-secret",
                "User-Agent": "VoiceDesk-dogfood"
            ])["Authorization"],
            "[redacted]"
        )
    }

    func testUploaderNoopsWhenReleaseOrToggleOff() async {
        let transport = FakeVoiceCloudTransport()
        let config = VoiceCloudLogConfig(kind: .https, httpsURL: "https://logs.example/voice", httpsSecret: "s")
        let offRelease = VoiceCloudLogUploader(
            config: config,
            transport: transport,
            allowsLogging: false,
            optedIn: true
        )
        await XCTAssertThrowsErrorAsync(VoiceCloudLogError.notAllowed) {
            _ = try await offRelease.upload(sampleEntry())
        }
        let offToggle = VoiceCloudLogUploader(
            config: config,
            transport: transport,
            allowsLogging: true,
            optedIn: false
        )
        await XCTAssertThrowsErrorAsync(VoiceCloudLogError.notAllowed) {
            _ = try await offToggle.upload(sampleEntry())
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testGistAppendUsesFakeTransportAndKeepsJSONL() async throws {
        let transport = FakeVoiceCloudTransport()
        transport.gistFiles["voice-log.jsonl"] = "{\"userTranscript\":\"prior\"}\n"
        let config = VoiceCloudLogConfig(
            kind: .githubGist,
            token: "ghp_TESTTOKENTESTTOKENTESTTOK",
            gistID: "gist123"
        )
        let uploader = VoiceCloudLogUploader(
            config: config,
            transport: transport,
            allowsLogging: true,
            optedIn: true
        )
        let result = try await uploader.upload(sampleEntry())
        XCTAssertEqual(result.destination, "gist:gist123")
        XCTAssertEqual(transport.requests.map(\.method), ["GET", "PATCH"])
        XCTAssertEqual(transport.requests[0].url, "https://api.github.com/gists/gist123")
        XCTAssertEqual(transport.requests[0].headers["Authorization"], "Bearer ghp_TESTTOKENTESTTOKENTESTTOK")
        XCTAssertEqual(
            VoiceCloudLogRedactor.redactHeaders(transport.requests[0].headers)["Authorization"],
            "[redacted]"
        )
        let patched = transport.gistFiles["voice-log.jsonl"] ?? ""
        XCTAssertTrue(patched.contains("prior"))
        XCTAssertTrue(patched.contains("Murray"))
        XCTAssertTrue(patched.contains("John Madison"))
        XCTAssertFalse(VoiceCloudLogRedactor.containsAudioKey(in: patched))
        XCTAssertFalse(patched.contains("audioBase64"))
    }

    func testGistCreatePersistsNewID() async throws {
        let transport = FakeVoiceCloudTransport()
        transport.nextCreatedGistID = "newgist99"
        let config = VoiceCloudLogConfig(
            kind: .githubGist,
            token: "ghp_TESTTOKENTESTTOKENTESTTOK",
            persistCreatedGistID: true
        )
        let uploader = VoiceCloudLogUploader(
            config: config,
            transport: transport,
            allowsLogging: true,
            optedIn: true
        )
        let result = try await uploader.upload(sampleEntry())
        XCTAssertEqual(result.createdGistID, "newgist99")
        XCTAssertEqual(transport.requests.first?.method, "POST")
        XCTAssertEqual(transport.requests.first?.url, "https://api.github.com/gists")
        let created = try JSONSerialization.jsonObject(with: transport.requests[0].body) as? [String: Any]
        XCTAssertEqual(created?["public"] as? Bool, false)
    }

    func testHTTPSUsesSecretHeaderNotQueryAndRedactedBody() async throws {
        let transport = FakeVoiceCloudTransport()
        transport.httpsStatus = 204
        let config = VoiceCloudLogConfig(
            kind: .https,
            httpsURL: "https://logs.example.com/voice",
            httpsSecret: "super-secret"
        )
        let uploader = VoiceCloudLogUploader(
            config: config,
            transport: transport,
            allowsLogging: true,
            optedIn: true,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        var dirty = sampleEntry()
        dirty.errors = ["Authorization: Bearer ghp_ABCDEFGHIJKLMNOPQRSTUVWX"]
        dirty.searchQuery = "from:john@coastal.com"
        let result = try await uploader.upload(dirty)
        XCTAssertEqual(result.destination, "https:logs.example.com")
        XCTAssertEqual(transport.requests.count, 1)
        let request = transport.requests[0]
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, "https://logs.example.com/voice")
        XCTAssertFalse(request.url.contains("super-secret"))
        XCTAssertEqual(request.headers["X-VoiceDesk-Secret"], "super-secret")
        let body = String(data: request.body, encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"hasAudio\":false"))
        XCTAssertTrue(body.contains("Murray"))
        XCTAssertTrue(body.contains("John Madison"))
        XCTAssertFalse(body.contains("ghp_"))
        XCTAssertTrue(body.contains("john@redacted"))
        XCTAssertFalse(VoiceCloudLogRedactor.containsAudioKey(in: body))
    }

    func testRepoAppendPutsBase64JSONL() async throws {
        let transport = FakeVoiceCloudTransport()
        transport.repoContent = "{\"userTranscript\":\"older\"}\n"
        transport.repoSHA = "abcsha"
        let config = VoiceCloudLogConfig(
            kind: .githubRepo,
            token: "ghp_TESTTOKENTESTTOKENTESTTOK",
            repo: "eriqbre/voicedesk-dogfood-logs",
            repoPath: ".debug/voice-log.jsonl"
        )
        let uploader = VoiceCloudLogUploader(
            config: config,
            transport: transport,
            allowsLogging: true,
            optedIn: true
        )
        _ = try await uploader.upload(sampleEntry())
        XCTAssertEqual(transport.requests.map(\.method), ["GET", "PUT"])
        XCTAssertTrue(transport.requests[0].url.contains("/repos/eriqbre/voicedesk-dogfood-logs/contents/"))
        let put = try JSONSerialization.jsonObject(with: transport.requests[1].body) as? [String: Any]
        XCTAssertEqual(put?["sha"] as? String, "abcsha")
        let encoded = try XCTUnwrap(put?["content"] as? String)
        let decoded = String(data: try XCTUnwrap(Data(base64Encoded: encoded)), encoding: .utf8) ?? ""
        XCTAssertTrue(decoded.contains("older"))
        XCTAssertTrue(decoded.contains("Murray"))
    }

    func testConfigResolvePrefersGistThenRepoThenHTTPS() {
        let gist = VoiceCloudLogConfig.resolve(
            token: "tok",
            gistID: "g1",
            repo: "o/r",
            httpsURL: "https://x",
            httpsSecret: "s"
        )
        XCTAssertEqual(gist?.kind, .githubGist)
        XCTAssertEqual(gist?.gistID, "g1")
        XCTAssertTrue(gist?.pullHint.contains("gh gist view g1") == true)

        let repo = VoiceCloudLogConfig.resolve(
            token: "tok",
            gistID: nil,
            repo: "eriqbre/voicedesk-dogfood-logs",
            httpsURL: "https://x",
            httpsSecret: "s"
        )
        XCTAssertEqual(repo?.kind, .githubRepo)
        XCTAssertTrue(repo?.pullHint.contains("gh api repos/eriqbre/voicedesk-dogfood-logs") == true)

        let https = VoiceCloudLogConfig.resolve(
            token: nil,
            gistID: nil,
            repo: nil,
            httpsURL: "https://logs.example/voice",
            httpsSecret: "s"
        )
        XCTAssertEqual(https?.kind, .https)

        XCTAssertNil(
            VoiceCloudLogConfig.resolve(
                token: nil,
                gistID: nil,
                repo: nil,
                httpsURL: nil,
                httpsSecret: nil
            )
        )
    }

    func testClassifyMurrayAskVsStickyJohnIsFirstClass() {
        let john = EmailItem(
            providerID: "jm",
            fromName: "John Madison",
            fromEmail: "john@example.com",
            sentAtLabel: "Today 4:00 PM",
            subject: "Listing referral",
            preview: "Referral",
            body: "Listing referral.",
            filterTag: "Inbox"
        )
        let evidence = ConversationPresence.DeskEvidence(
            topic: .inbox,
            text: "John Madison wrote about Listing referral.",
            cards: [.email(john)],
            focusedEmail: john,
            resetsFocusedEmail: false
        )
        let classified = VoiceInteractionLog.classify(
            utterance: "Okay, got it. Hey, can you give me a summary of Murray's latest email?",
            evidence: evidence,
            hadFocusedEmail: true
        )
        XCTAssertEqual(classified.sticky, .reused)
        XCTAssertEqual(classified.focusedPerson, "John Madison")
        XCTAssertNotEqual(classified.intent, "inbox-overview")
        XCTAssertTrue(
            classified.notes.contains { $0.contains("sticky reused") },
            classified.notes.joined(separator: ",")
        )
    }
}

private func sampleEntry() -> VoiceInteractionEntry {
    VoiceInteractionEntry(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        source: "live voice",
        userTranscript: "Okay, got it. Hey, can you give me a summary of Murray's latest email?",
        intent: "desk-person",
        sticky: .reused,
        focusedPerson: "John Madison",
        searchQuery: "from:john@coastal.test",
        routingNotes: ["sticky reused (John Madison)", "search from:john@coastal.test"],
        cardsAttached: ["email:John Madison:Listing referral"],
        assistantReply: "John Madison wrote about Listing referral.",
        voicePath: "Eve realtime",
        errors: ["timeout talking to Eve"]
    )
}

private final class FakeVoiceCloudTransport: VoiceCloudLogTransporting, @unchecked Sendable {
    var requests: [VoiceCloudLogHTTPRequest] = []
    var gistFiles: [String: String] = [:]
    var nextCreatedGistID = "created1"
    var repoContent = ""
    var repoSHA: String?
    var httpsStatus = 204

    func send(_ request: VoiceCloudLogHTTPRequest) async throws -> VoiceCloudLogHTTPResponse {
        requests.append(request)
        if request.url.contains("/gists") {
            return try gistResponse(request)
        }
        if request.url.contains("/repos/") {
            return try repoResponse(request)
        }
        return VoiceCloudLogHTTPResponse(status: httpsStatus)
    }

    private func gistResponse(_ request: VoiceCloudLogHTTPRequest) throws -> VoiceCloudLogHTTPResponse {
        if request.method == "GET" {
            let files = gistFiles.mapValues { ["content": $0] }
            let data = try JSONSerialization.data(withJSONObject: ["files": files])
            return VoiceCloudLogHTTPResponse(status: 200, body: data)
        }
        if request.method == "POST" {
            let object = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
            let files = object?["files"] as? [String: Any]
            if let file = files?["voice-log.jsonl"] as? [String: Any], let content = file["content"] as? String {
                gistFiles["voice-log.jsonl"] = content
            }
            let data = try JSONSerialization.data(withJSONObject: ["id": nextCreatedGistID])
            return VoiceCloudLogHTTPResponse(status: 201, body: data)
        }
        if request.method == "PATCH" {
            let object = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
            let files = object?["files"] as? [String: Any]
            if let file = files?["voice-log.jsonl"] as? [String: Any], let content = file["content"] as? String {
                gistFiles["voice-log.jsonl"] = content
            }
            return VoiceCloudLogHTTPResponse(status: 200)
        }
        return VoiceCloudLogHTTPResponse(status: 400)
    }

    private func repoResponse(_ request: VoiceCloudLogHTTPRequest) throws -> VoiceCloudLogHTTPResponse {
        if request.method == "GET" {
            let encoded = Data(repoContent.utf8).base64EncodedString()
            var payload: [String: Any] = ["content": encoded]
            if let repoSHA { payload["sha"] = repoSHA }
            return VoiceCloudLogHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: payload))
        }
        return VoiceCloudLogHTTPResponse(status: 200)
    }
}

private func XCTAssertThrowsErrorAsync<E: Equatable & Error>(
    _ expected: E,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ work: @escaping () async throws -> Void
) async {
    do {
        try await work()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch let error as E {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("unexpected \(error)", file: file, line: line)
    }
}
