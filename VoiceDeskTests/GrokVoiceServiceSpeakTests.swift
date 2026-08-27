import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

/// Unit gate: production `GrokVoiceService.speak("1.2.3")` through a
/// fake `LiveGrokVoiceClient`. `markOpenedForTests` is a testSendSink
/// paper socket — no `URLSessionWebSocketTask`. Not a live WS proof.
/// Not phone-proof. Linux `VoiceDeskLogic` never runs this file.
/// Ryan Mac xcodebuild is the iOS gate.
@MainActor
final class GrokVoiceServiceSpeakTests: XCTestCase {
    override func tearDown() {
        ClientVoiceSpeech.shared.resetTestSpeakRecorder()
        super.tearDown()
    }

    /// Socket up + `speak("1.2.3")` must deliver the Eve wire and
    /// must not enter ClientVoiceSpeech.
    func testSpeak123SocketUpDeliversEveWireAndZeroClientTTS() async {
        let voice = connectedVoice(apiKey: "speak-123-up")
        voice.attachListenLoopClientTTSRecorderForTests()
        let before = voice.listenLoopDeliveredSendTypes.count

        await voice.speak("1.2.3")

        let delivered = Array(voice.listenLoopDeliveredSendTypes.dropFirst(before))
        XCTAssertTrue(
            containsInOrder(delivered, [
                "session.update",
                "conversation.item.create",
                "response.create"
            ]),
            "delivered \(delivered)"
        )
        XCTAssertEqual(
            voice.listenLoopClientTTSSpeakCount,
            0,
            "socket up must not write ClientVoiceSpeech"
        )
        XCTAssertTrue(voice.listenLoopClientTTSRecordedTexts.isEmpty)
        voice.cancel()
    }

    /// Socket down + `speak("1.2.3")` must write ClientVoiceSpeech.
    /// 83a5c6a guard-return swallowed this (6m silence). That path
    /// must fail here: zero ClientTTS + no Eve wire is a fail.
    func testSpeak123SocketDownWritesClientVoiceSpeech() async {
        let voice = GrokVoiceService(apiKey: "speak-123-down")
        voice.attachListenLoopClientTTSRecorderForTests()

        await voice.speak("1.2.3")

        XCTAssertEqual(
            voice.listenLoopClientTTSSpeakCount,
            1,
            "old speakLiveReplyViaEve guard-return swallowed the line"
        )
        XCTAssertEqual(voice.listenLoopClientTTSRecordedTexts, ["1.2.3"])
        XCTAssertFalse(
            voice.listenLoopDeliveredSendTypes.contains("response.create"),
            "down socket must not send Eve create"
        )
        voice.cancel()
    }

    /// Foreign `response.done` must not clear the verbatim bind and
    /// must not send listen-resume `session.update`.
    func testForeignResponseDoneDoesNotClearVerbatimOrResumeListen() async {
        let voice = connectedVoice(apiKey: "speak-123-foreign-done")
        voice.attachListenLoopClientTTSRecorderForTests()

        await voice.speak("1.2.3")
        XCTAssertTrue(voice.listenLoopAwaitingVerbatimSpeakID)

        voice.injectListenLoopJSON(
            ["type": "response.created", "response_id": "verbatim-1"],
            type: "response.created"
        )
        XCTAssertEqual(voice.listenLoopVerbatimSpeakResponseID, "verbatim-1")
        XCTAssertFalse(voice.listenLoopAwaitingVerbatimSpeakID)

        let afterBind = voice.listenLoopDeliveredSends.count
        voice.injectListenLoopJSON(
            ["type": "response.done", "response_id": "foreign"],
            type: "response.done"
        )

        XCTAssertEqual(
            voice.listenLoopVerbatimSpeakResponseID,
            "verbatim-1",
            "foreign done must not clear the speak bind"
        )
        let extra = Array(voice.listenLoopDeliveredSends.dropFirst(afterBind))
        for payload in extra {
            XCTAssertNotEqual(
                GrokRealtime.createResponse(inSessionUpdate: payload),
                true,
                "foreign done must not send listen-resume session.update: \(payload)"
            )
        }
        voice.cancel()
    }

    /// Canned c1cd758 fixture stays red (empty eve-speaks-identity).
    /// Not a device walk. In-flight VAD `speak()` must clear before
    /// `response.create`. Do not flip a source scrape.
    func testInFlightVADSpeakInterruptsBeforeCreateAndDoesNotStarveEve() async {
        XCTAssertTrue(
            C1CD758Walk.isEmptyEveSpeaksIdentity(
                try XCTUnwrap(C1CD758Walk.versionTurn())
            ),
            "c1cd758 version walk: eve speaks identity + empty reply + no PCM"
        )
        XCTAssertTrue(LiveVADPlayerKeep.c1cd758Regression().voiceCutsAfterFirstDelta)

        let voice = connectedVoice(apiKey: "speak-123-inflight")
        voice.attachListenLoopClientTTSRecorderForTests()
        voice.injectListenLoopJSON(
            ["type": "response.created", "response_id": "vad-A"],
            type: "response.created"
        )
        voice.playListenLoopOutputAudioDeltaForTests(
            responseID: "vad-A",
            pcm: Data([0, 0, 1, 0, 2, 0, 3, 0])
        )

        let before = voice.listenLoopDeliveredSendTypes.count
        await voice.speak("1.2.3")
        let delivered = Array(voice.listenLoopDeliveredSendTypes.dropFirst(before))

        guard let clearAt = delivered.firstIndex(of: "input_audio_buffer.clear"),
              let createAt = delivered.firstIndex(of: "response.create")
        else {
            return XCTFail(
                "in-flight VAD speak must clear then create; got \(delivered)"
            )
        }
        XCTAssertLessThan(
            clearAt,
            createAt,
            "create without interrupt/clear is the c1cd758 starve"
        )
        XCTAssertTrue(
            containsInOrder(delivered, [
                "session.update",
                "conversation.item.create",
                "response.create"
            ]),
            "delivered \(delivered)"
        )
        XCTAssertEqual(
            voice.listenLoopClientTTSSpeakCount,
            0,
            "desk ClientVoiceSpeech on live VAD is a second mouth"
        )
        XCTAssertFalse(
            LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: "1.2.3",
                identityLine: "1.2.3"
            )
        )
        voice.cancel()
    }

    private func connectedVoice(apiKey: String) -> GrokVoiceService {
        let voice = GrokVoiceService(apiKey: apiKey)
        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        voice.markListenLoopOpenedForTests()
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
