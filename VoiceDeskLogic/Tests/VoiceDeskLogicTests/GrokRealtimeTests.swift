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
        XCTAssertTrue(text.contains("NO Settings screen"))
        XCTAssertTrue(text.contains("Tap Connect Google on the card below."))
        XCTAssertTrue(text.contains("NEVER invent Settings, Account, or Integrations"))
        XCTAssertTrue(text.contains("NEVER say you cannot connect"))
        XCTAssertTrue(text.contains("NEVER say open it in Gmail"))
        XCTAssertTrue(text.contains("NEVER say they need Gmail for the rest"))
        XCTAssertFalse(text.contains("only have the subject"))
    }

    func testConnectedPresenceDropsSampleDeskLies() {
        let snapshot = DeskSnapshot(
            accountEmail: "ada@example.com",
            emails: [SampleData.syncedEmail()],
            events: [
                CalendarItem(title: "Offer review", whenLabel: "Today 3:00 PM", location: "Coastal office")
            ],
            tasks: [TaskItem(title: "Call lender", dueLabel: "Tue")]
        )
        let text = GrokRealtime.presenceInstructions(for: DeskContext(isConnected: true, snapshot: snapshot))
        XCTAssertTrue(text.contains("ada@example.com"))
        XCTAssertTrue(text.contains("Inspection questions"))
        XCTAssertTrue(text.contains("Offer review"))
        XCTAssertFalse(text.contains("Jordan Hale"))
        XCTAssertFalse(text.contains("1842 Beach Drive"))
        XCTAssertTrue(text.contains("Do not mention any sample listing"))
        XCTAssertTrue(text.contains("ALREADY connected as ada@example.com"))
        XCTAssertTrue(text.contains("NO Settings screen"))
        XCTAssertTrue(text.contains("NEVER tell them to open app settings"))
        XCTAssertTrue(text.contains("You’re already connected as ada@example.com. Use Disconnect on the card if you need to switch."))
        XCTAssertTrue(text.contains("NEVER say open it in Gmail"))
        XCTAssertTrue(text.contains("sync failed"))
        XCTAssertFalse(text.contains("only have the subject"))
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
                json: ["transcript": "What’s in my inbox?", "item_id": "item_1"]
            ),
            .userTranscript(text: "What’s in my inbox?", itemID: "item_1")
        )
        XCTAssertEqual(
            GrokRealtime.parse(
                type: "conversation.item.created",
                json: [
                    "item": [
                        "id": "item_1",
                        "role": "user",
                        "content": [["type": "input_text", "text": "What’s in my inbox?"]]
                    ] as [String: Any]
                ]
            ),
            .userTranscript(text: "What’s in my inbox?", itemID: "item_1")
        )
        XCTAssertEqual(
            GrokRealtime.parse(
                type: "response.output_audio_transcript.delta",
                json: ["delta": "Jordan wrote "]
            ),
            .assistantTranscriptDelta("Jordan wrote ", source: .audio)
        )
        XCTAssertEqual(
            GrokRealtime.parse(
                type: "response.output_text.delta",
                json: ["delta": "Jordan wrote "]
            ),
            .assistantTranscriptDelta("Jordan wrote ", source: .outputText)
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
