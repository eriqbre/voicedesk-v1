import XCTest
@testable import VoiceDeskLogic

final class GrokRealtimeTests: XCTestCase {
    func testRealtimeURLPinsVoiceModel() {
        XCTAssertEqual(
            GrokRealtime.realtimeURLString(),
            "wss://api.x.ai/v1/realtime?model=grok-voice-latest"
        )
        XCTAssertEqual(
            GrokRealtime.realtimeURLString(model: "grok-voice-think-fast-2.0"),
            "wss://api.x.ai/v1/realtime?model=grok-voice-think-fast-2.0"
        )
    }

    func testSessionUpdateMatchesSpeechToSpeechContract() throws {
        let data = try GrokRealtime.sessionUpdateJSON(voice: "eve")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "session.update")

        let session = try XCTUnwrap(object["session"] as? [String: Any])
        XCTAssertEqual(session["voice"] as? String, "eve")
        XCTAssertEqual(session["instructions"] as? String, GrokRealtime.presenceInstructions)

        let turn = try XCTUnwrap(session["turn_detection"] as? [String: Any])
        XCTAssertEqual(turn["type"] as? String, "server_vad")

        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap((audio["input"] as? [String: Any])?["format"] as? [String: Any])
        let output = try XCTUnwrap((audio["output"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(input["type"] as? String, "audio/pcm")
        XCTAssertEqual(output["type"] as? String, "audio/pcm")
        XCTAssertEqual(intValue(input["rate"]), 24_000)
        XCTAssertEqual(intValue(output["rate"]), 24_000)
    }

    func testPresenceInstructionsFollowPromptShape() {
        let text = GrokRealtime.presenceInstructions
        for heading in [
            "## Role & Persona",
            "## Objective",
            "## Conversation Flow",
            "## Guardrails & Escalation",
            "## Voice & Communication Style"
        ] {
            XCTAssertTrue(text.contains(heading), "missing \(heading)")
        }
        XCTAssertTrue(text.contains("1842 Beach Drive"))
        XCTAssertTrue(text.contains("Jordan Hale"))
        XCTAssertTrue(text.contains("475.278"))
        XCTAssertFalse(text.contains("web_search"))
    }

    func testAppendAudioJSONIsHotPathSafe() {
        XCTAssertEqual(
            GrokRealtime.appendAudioJSON(base64: "ABC+12/="),
            #"{"type":"input_audio_buffer.append","audio":"ABC+12/="}"#
        )
    }

    func testParsesUserAndAssistantTranscriptEvents() {
        XCTAssertEqual(
            GrokRealtime.parse(
                type: "conversation.item.input_audio_transcription.completed",
                json: ["transcript": "What’s in my inbox?"]
            ),
            .userTranscript("What’s in my inbox?")
        )
        XCTAssertEqual(
            GrokRealtime.parse(
                type: "response.output_audio_transcript.delta",
                json: ["delta": "Jordan wrote "]
            ),
            .assistantTranscriptDelta("Jordan wrote ")
        )
        XCTAssertEqual(
            GrokRealtime.parse(type: "response.audio.delta", json: ["delta": "AAAA"]),
            .outputAudioDelta("AAAA")
        )
        XCTAssertEqual(
            GrokRealtime.parse(
                type: "error",
                json: ["code": "timeout", "message": "idle"]
            ),
            .error(code: "timeout", message: "idle")
        )
    }

    func testCancelAndTextTurnPayloads() {
        XCTAssertEqual(GrokRealtime.responseCancelObject()["type"] as? String, "response.cancel")
        XCTAssertEqual(GrokRealtime.clearBufferObject()["type"] as? String, "input_audio_buffer.clear")

        let item = GrokRealtime.textItemObject("Hello")
        XCTAssertEqual(item["type"] as? String, "conversation.item.create")
        let response = GrokRealtime.responseCreateObject()
        XCTAssertEqual(response["type"] as? String, "response.create")
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
