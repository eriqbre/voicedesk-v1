import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

/// Production `GrokVoiceService.speak("1.2.3")` on the loopback
/// `URLSessionWebSocketTask` (`opened && task`).
/// 83a5c6a swallow is UP: Eve chosen (opened && armed), send no-ops
/// or void-returns, speak() returns with zero ClientTTS.
/// Never-connected DOWN already wrote ClientTTS on 83a5c6a.
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
        XCTAssertTrue(sawCreate, "UP speak must deliver response.create on the real task")
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

    /// 83a5c6a: `shouldSpeakViaRealtime(isConnected: opened && armed)`
    /// then void `speakLiveReplyViaEve` + unconditional return.
    /// Eve chosen, send cannot go out, zero ClientTTS = 6m silence.
    func testSpeak123EveChosenSendNoOpWritesClientTTS() async throws {
        let loopback = try await ListenLoopWebSocketLoopback.start()
        defer { loopback.stop() }
        let voice = try await openProductionSpeakSocket(
            apiKey: "speak-123-swallow",
            loopback: loopback
        )
        voice.startListenLoopAudioForTests()
        voice.attachListenLoopClientTTSRecorderForTests()
        voice.dropListenLoopSendTaskKeepingOpenedForTests()
        XCTAssertTrue(voice.listenLoopSocketOpened, "Eve is still chosen")
        XCTAssertTrue(voice.listenLoopLiveSessionArmed)
        XCTAssertFalse(
            voice.listenLoopHasProductionSendTask,
            "send path no-ops — opened && task is gone"
        )
        let before = loopback.receivedTexts.count

        await voice.speak("1.2.3")

        XCTAssertEqual(
            voice.listenLoopClientTTSSpeakCount,
            1,
            "83a5c6a returned after void Eve send with zero ClientTTS"
        )
        XCTAssertEqual(voice.listenLoopClientTTSRecordedTexts, ["1.2.3"])
        let after = loopback.receivedTexts.dropFirst(before)
        XCTAssertFalse(
            after.contains { LiveGrokVoiceClient.typeOfSend($0) == "response.create" },
            "no-op Eve send must not count as delivered wire"
        )
        voice.cancel()
    }

    func testSpeak123SocketDownWritesClientVoiceSpeech() async {
        let voice = GrokVoiceService(apiKey: "speak-123-down")
        voice.attachListenLoopClientTTSRecorderForTests()

        await voice.speak("1.2.3")

        XCTAssertEqual(
            voice.listenLoopClientTTSSpeakCount,
            1,
            "never-connected already wrote ClientTTS on 83a5c6a — not the swallow"
        )
        XCTAssertEqual(voice.listenLoopClientTTSRecordedTexts, ["1.2.3"])
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

        loopback.sendPeerJSON(
            #"{"type":"response.created","response_id":"verbatim-1"}"#
        )
        let bound = await waitUntil(timeoutMs: 2000) {
            voice.listenLoopVerbatimSpeakResponseID == "verbatim-1"
        }
        XCTAssertTrue(bound, "peer response.created must bind the speak id")
        XCTAssertFalse(voice.listenLoopAwaitingVerbatimSpeakID)

        let afterBind = loopback.receivedTexts.count
        loopback.sendPeerJSON(
            #"{"type":"response.done","response_id":"foreign"}"#
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
        XCTAssertTrue(opened, "UP speak needs opened && task")
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

    private func waitUntil(timeoutMs: Int, _ predicate: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
        while ContinuousClock.now < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return predicate()
    }
}
