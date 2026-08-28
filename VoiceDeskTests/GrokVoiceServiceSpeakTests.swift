import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

/// Production `GrokVoiceService.speak("1.2.3")` on the loopback
/// `URLSessionWebSocketTask` (`opened && task`).
/// 83a5c6a swallow is UP: Eve chosen (opened && armed), send no-ops
/// or void-returns, speak() returns with zero ClientTTS.
/// Never-connected DOWN already wrote ClientTTS on 83a5c6a.
/// Leftover teaching is asserted on delivered session.update
/// instructions (the wire), not a Linux string detector.
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

        let instructionBlobs = loopback.receivedTexts.compactMap {
            GrokRealtime.instructions(inSessionUpdate: $0)
        }
        XCTAssertFalse(
            instructionBlobs.isEmpty,
            "connect + speak must put session.update instructions on the task"
        )
        for blob in instructionBlobs {
            XCTAssertFalse(
                GrokRealtime.teachesLeftoverDeskRouting(blob),
                "83a5c6a put stay silent / let the app handle / NEVER narrate routing on this wire: \(blob)"
            )
            XCTAssertFalse(
                GrokRealtime.teachesNoTools(blob),
                "83a5c6a put you have no tools / do not pretend to call functions on this wire: \(blob)"
            )
        }
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

    /// 12:14 leftover: 83a5c6a / 7ef2f6d left `create_response` true
    /// (or omitted) on speech_started, so server VAD created a mouth
    /// before client tools, then another create after tools landed.
    /// This walk is the production socket: peer `speech_started` /
    /// user transcript / AppModel begin+end tool-wait. Not a
    /// CreateTrace factory, leftover1214() string, or source scrape.
    func testCalendarAskWaitsForToolsThenOneResponseCreate() async throws {
        let loopback = try await ListenLoopWebSocketLoopback.start()
        defer { loopback.stop() }
        let voice = try await openProductionSpeakSocket(
            apiKey: "speak-1214-tool-wait",
            loopback: loopback
        )
        voice.attachListenLoopClientTTSRecorderForTests()

        let connectUpdates = loopback.receivedTexts.filter {
            LiveGrokVoiceClient.typeOfSend($0) == "session.update"
        }
        XCTAssertFalse(connectUpdates.isEmpty, "connect must put session.update on the task")
        XCTAssertFalse(
            connectUpdates.contains { GrokRealtime.createResponse(inSessionUpdate: $0) == false },
            "listen connect must not wait on tools: \(connectUpdates)"
        )

        let afterConnect = loopback.receivedTexts.count
        let snapshot = DeskSnapshot(accountEmail: "agent@example.com")
        voice.eventHandler = { event in
            if case .userTranscript(let text, _, _) = event,
               LiveToolMouth.needsClientTools(
                ask: text,
                snapshot: snapshot,
                isConnected: true,
                isOnline: true
               ) {
                voice.beginToolWaitCreate()
            }
        }

        loopback.sendPeerJSON(#"{"type":"input_audio_buffer.speech_started"}"#)
        let sawToolWait = await waitUntilNewReceived(loopback, after: afterConnect) {
            GrokRealtime.createResponse(inSessionUpdate: $0) == false
        }
        XCTAssertTrue(
            sawToolWait,
            "83a5c6a / 7ef2f6d noon: speech_started sent no create_response false; VAD created before tools"
        )
        let toolWaitUpdate = try XCTUnwrap(
            loopback.receivedTexts.dropFirst(afterConnect).first(where: {
                GrokRealtime.createResponse(inSessionUpdate: $0) == false
            })
        )
        XCTAssertFalse(
            GrokRealtime.vadCreatesOnSpeechStopped(
                createResponse: GrokRealtime.createResponse(inSessionUpdate: toolWaitUpdate)
            ),
            "wire flag must stop VAD create: \(toolWaitUpdate)"
        )

        loopback.sendPeerJSON(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(
            loopback.receivedTexts.dropFirst(afterConnect).contains {
                LiveGrokVoiceClient.typeOfSend($0) == "response.create"
            },
            "no client response.create before tools"
        )

        let afterSpeech = loopback.receivedTexts.count
        loopback.sendPeerJSON(
            #"{"type":"conversation.item.input_audio_transcription.completed","transcript":"what's on my calendar","item_id":"cal-1"}"#
        )
        let beganWait = await waitUntilNewReceived(loopback, after: afterSpeech) {
            GrokRealtime.createResponse(inSessionUpdate: $0) == false
        }
        XCTAssertTrue(
            beganWait,
            "tools ask must send another create_response false (AppModel beginToolWaitCreate)"
        )
        XCTAssertFalse(
            loopback.receivedTexts.dropFirst(afterConnect).contains {
                LiveGrokVoiceClient.typeOfSend($0) == "response.create"
            },
            "transcript + tools-needed must not create a mouth before the tool result"
        )

        let beforeTools = loopback.receivedTexts.count
        voice.endToolWaitCreate()
        let sawCreate = await waitUntilNewReceived(loopback, after: beforeTools) {
            LiveGrokVoiceClient.typeOfSend($0) == "response.create"
        }
        XCTAssertTrue(sawCreate, "one response.create after tools on the real task")
        try? await Task.sleep(for: .milliseconds(80))
        let createsAfterTools = loopback.receivedTexts.dropFirst(beforeTools).filter {
            LiveGrokVoiceClient.typeOfSend($0) == "response.create"
        }
        XCTAssertEqual(
            createsAfterTools.count,
            1,
            "exactly one mouth after tools; 83a5c6a noon added a later create on top of the VAD mouth: \(createsAfterTools)"
        )
        XCTAssertEqual(voice.listenLoopClientTTSSpeakCount, 0)
        XCTAssertTrue(voice.listenLoopClientTTSRecordedTexts.isEmpty)
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

    private func waitUntilNewReceived(
        _ loopback: ListenLoopWebSocketLoopback,
        after count: Int,
        timeoutMs: Int = 2000,
        matching: @escaping (String) -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
        while ContinuousClock.now < deadline {
            if loopback.receivedTexts.dropFirst(count).contains(where: matching) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return loopback.receivedTexts.dropFirst(count).contains(where: matching)
    }
}
