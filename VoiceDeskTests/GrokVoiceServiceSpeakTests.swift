import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

/// Production `GrokVoiceService.speak("1.2.3")`. UP uses the in-process
/// loopback `URLSessionWebSocketTask` (`opened && task`). That is the
/// send recorder — not `markOpenedForTests` / testSendSink.
/// DOWN writes ClientVoiceSpeech. 83a5c6a guard-return silence fails
/// at runtime if this count stays 0.
/// Linux `VoiceDeskLogic` never runs this file.
@MainActor
final class GrokVoiceServiceSpeakTests: XCTestCase {
    override func tearDown() {
        ClientVoiceSpeech.shared.resetTestSpeakRecorder()
        super.tearDown()
    }

    func testSpeak123SocketUpDeliversEveWireAndZeroClientTTS() async throws {
        let loopback = try await ListenLoopWebSocketLoopback.start()
        defer { loopback.stop() }
        let voice = try await openProductionSpeakSocket(
            apiKey: "speak-123-up",
            loopback: loopback
        )
        voice.attachListenLoopClientTTSRecorderForTests()
        let before = loopback.receivedTexts.count

        await voice.speak("1.2.3")
        let sawCreate = await loopback.waitUntilReceived {
            LiveGrokVoiceClient.typeOfSend($0) == "response.create"
        }
        XCTAssertTrue(
            sawCreate,
            "UP speak must deliver response.create on the real task — swallow is 6m silence"
        )
        let delivered = loopback.receivedTexts
            .dropFirst(before)
            .compactMap { LiveGrokVoiceClient.typeOfSend($0) }
        XCTAssertTrue(
            containsInOrder(delivered, [
                "session.update",
                "conversation.item.create",
                "response.create"
            ]),
            "delivered \(delivered)"
        )
        XCTAssertEqual(voice.listenLoopClientTTSSpeakCount, 0)
        XCTAssertTrue(voice.listenLoopClientTTSRecordedTexts.isEmpty)
        voice.cancel()
    }

    func testSpeak123SocketDownWritesClientVoiceSpeech() async {
        let voice = GrokVoiceService(apiKey: "speak-123-down")
        voice.attachListenLoopClientTTSRecorderForTests()

        await voice.speak("1.2.3")

        XCTAssertEqual(
            voice.listenLoopClientTTSSpeakCount,
            1,
            "83a5c6a speakLiveReplyViaEve guard-return wrote nothing — 6m silence"
        )
        XCTAssertEqual(voice.listenLoopClientTTSRecordedTexts, ["1.2.3"])
        XCTAssertFalse(voice.listenLoopDeliveredSendTypes.contains("response.create"))
        voice.cancel()
    }

    func testForeignResponseDoneDoesNotClearVerbatimOrResumeListen() async throws {
        let loopback = try await ListenLoopWebSocketLoopback.start()
        defer { loopback.stop() }
        let voice = try await openProductionSpeakSocket(
            apiKey: "speak-123-foreign-done",
            loopback: loopback
        )
        voice.attachListenLoopClientTTSRecorderForTests()

        await voice.speak("1.2.3")
        let sawCreate = await loopback.waitUntilReceived {
            LiveGrokVoiceClient.typeOfSend($0) == "response.create"
        }
        XCTAssertTrue(sawCreate)
        XCTAssertTrue(voice.listenLoopAwaitingVerbatimSpeakID)

        voice.injectListenLoopJSON(
            ["type": "response.created", "response_id": "verbatim-1"],
            type: "response.created"
        )
        XCTAssertEqual(voice.listenLoopVerbatimSpeakResponseID, "verbatim-1")
        XCTAssertFalse(voice.listenLoopAwaitingVerbatimSpeakID)

        let afterBind = loopback.receivedTexts.count
        voice.injectListenLoopJSON(
            ["type": "response.done", "response_id": "foreign"],
            type: "response.done"
        )
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(
            voice.listenLoopVerbatimSpeakResponseID,
            "verbatim-1",
            "foreign done must not clear the speak bind — stayIdle-after-version"
        )
        let extra = Array(loopback.receivedTexts.dropFirst(afterBind))
        for payload in extra {
            XCTAssertNotEqual(
                GrokRealtime.createResponse(inSessionUpdate: payload),
                true,
                "foreign done must not send listen-resume session.update: \(payload)"
            )
        }
        voice.cancel()
    }

    private func openProductionSpeakSocket(
        apiKey: String,
        loopback: ListenLoopWebSocketLoopback
    ) async throws -> GrokVoiceService {
        let voice = GrokVoiceService(apiKey: apiKey)
        voice.setListenLoopRealtimeURLOverrideForTests(loopback.url)
        try await voice.connectListenLoopProductionForTests()
        let opened = await voice.waitUntilListenLoopHasProductionSendTask()
        XCTAssertTrue(
            opened,
            "UP speak needs opened && task — not markOpenedForTests"
        )
        XCTAssertFalse(voice.listenLoopUsesTestSendSink)
        XCTAssertNotNil(voice.listenLoopProductionWebSocketTask)
        return voice
    }

    private func containsInOrder(_ types: [String], _ required: [String]) -> Bool {
        var index = 0
        for type in types {
            if index < required.count, type == required[index] {
                index += 1
            }
        }
        return index == required.count
    }
}
