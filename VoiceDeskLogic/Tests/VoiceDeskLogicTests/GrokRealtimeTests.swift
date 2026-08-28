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
        XCTAssertNil(turn["interrupt_response"], "first-tap / default listen stays server_vad only")
        XCTAssertNil(turn["create_response"])

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
        XCTAssertFalse(GrokRealtime.teachesNoTools(text), text)
        XCTAssertFalse(text.contains("You have no tools"), text)
        XCTAssertFalse(text.contains("do not pretend to call functions"), text)
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
        XCTAssertFalse(
            text.contains("Offer review"),
            "9B23C3AA leftover: calendar rows on the session let her skip the tool"
        )
        XCTAssertFalse(text.contains("Jordan Hale"))
        XCTAssertFalse(text.contains("1842 Beach Drive"))
        XCTAssertTrue(text.contains("Do not mention any sample listing"))
        XCTAssertTrue(text.contains("ALREADY connected as ada@example.com"))
        XCTAssertTrue(text.contains("NO Settings screen"))
        XCTAssertTrue(text.contains("NEVER tell them to open app settings"))
        XCTAssertTrue(text.contains("You’re already connected as ada@example.com. Use Disconnect on the card if you need to switch."))
        XCTAssertTrue(text.contains("NEVER say open it in Gmail"))
        XCTAssertTrue(text.contains("NEVER mention an Email card"))
        XCTAssertTrue(text.contains("pull-to-refresh"))
        XCTAssertTrue(text.contains("NEVER paste a full email body"))
        XCTAssertTrue(text.contains("not in the last sync"))
        XCTAssertFalse(text.contains("NEVER say you are searching"))
        XCTAssertFalse(text.contains("The iOS app can search"))
        XCTAssertFalse(text.contains("I can search Gmail"))
        XCTAssertFalse(text.contains("waiting on the Email card"))
        XCTAssertFalse(text.contains("only have the subject"))
        XCTAssertFalse(text.contains("Snippet only"))
        XCTAssertFalse(text.contains("Can we walk the punch list"))
        XCTAssertTrue(text.contains("from, subject, and when"))
        XCTAssertFalse(text.contains("stay silent"))
        XCTAssertFalse(text.contains("you speak the answer"))
        XCTAssertFalse(text.contains("answer from the facts"))
        XCTAssertFalse(
            text.contains("wait in this same turn"),
            "AEEAB5CC: wait-and-speak was the park/retry mouth"
        )
        XCTAssertFalse(text.contains("let the app handle"))
        XCTAssertFalse(GrokRealtime.teachesLeftoverDeskRouting(text))
        XCTAssertFalse(GrokRealtime.teachesNoTools(text), text)
        XCTAssertFalse(text.contains("NEVER narrate routing"))
        XCTAssertFalse(text.contains("You have no tools"), text)
        XCTAssertFalse(text.contains("do not pretend to call functions"), text)
    }

    func testConnectedDeskFactsNeverLabelSnippetOnly() {
        let snapshot = DeskSnapshot(emails: [SampleData.syncedEmail()])
        let facts = GrokRealtime.connectedDeskFacts(snapshot)
        XCTAssertTrue(facts.contains("Ada Cole"))
        XCTAssertTrue(facts.contains("Inspection questions"))
        XCTAssertTrue(facts.contains("Today 8:02 AM"))
        XCTAssertFalse(facts.contains("Snippet only"))
        XCTAssertFalse(facts.contains("Can we walk the punch list"))
        XCTAssertFalse(facts.localizedCaseInsensitiveContains("preview"))
        XCTAssertFalse(facts.contains("stay silent"))
        XCTAssertFalse(facts.contains("You speak the answer"))
        XCTAssertFalse(GrokRealtime.teachesNoTools(facts), facts)
    }

    func testNoToolsTeachingIsThe83a5c6aSessionUpdateSentence() {
        let wire = "You have no tools this slice — do not pretend to call functions."
        XCTAssertTrue(
            GrokRealtime.teachesNoTools(wire),
            "83a5c6a put this sentence on session.update"
        )
        XCTAssertFalse(GrokRealtime.teachesNoTools(GrokRealtime.presenceInstructions))
        XCTAssertFalse(
            GrokRealtime.teachesNoTools(
                GrokRealtime.presenceInstructions(
                    for: DeskContext(isConnected: true, snapshot: DeskSnapshot(emails: [SampleData.syncedEmail()]))
                )
            )
        )
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
                type: "response.output_audio.delta",
                json: ["audio": "BBBB", "delta": ""]
            ),
            .outputAudioDelta("BBBB")
        )
        XCTAssertEqual(
            GrokRealtime.parse(
                type: "error",
                json: ["code": "timeout", "message": "idle"]
            ),
            .error(code: "timeout", message: "idle")
        )
        XCTAssertEqual(
            GrokRealtime.parse(
                type: "response.done",
                json: ["response": ["id": "handoff-1"] as [String: Any]]
            ),
            .responseDone(id: "handoff-1")
        )
        XCTAssertEqual(
            GrokRealtime.parse(type: "response.done", json: ["response_id": "verbatim-2"]),
            .responseDone(id: "verbatim-2")
        )
    }

    func testLiveSpeakUsesRealtimeWhenConnected() throws {
        XCTAssertTrue(
            GrokRealtime.shouldSpeakViaRealtime(
                usesLiveLoop: true,
                isConnected: true,
                userWantsVoiceOff: false
            ),
            "live Talk answers are Eve — no second desk-TTS mouth"
        )
        XCTAssertFalse(
            GrokRealtime.shouldSpeakViaRealtime(
                usesLiveLoop: false,
                isConnected: true,
                userWantsVoiceOff: false
            ),
            "Mock / ui-testing uses client TTS"
        )
        XCTAssertFalse(
            GrokRealtime.shouldSpeakViaRealtime(
                usesLiveLoop: true,
                isConnected: false,
                userWantsVoiceOff: false
            )
        )
        XCTAssertFalse(
            GrokRealtime.shouldSpeakViaRealtime(
                usesLiveLoop: true,
                isConnected: true,
                userWantsVoiceOff: true
            )
        )
        let spoken = "Murray wrote: Need you to notarize today."
        let prompt = GrokRealtime.verbatimSpeakUserText(text: spoken)
        XCTAssertTrue(GrokRealtime.isVerbatimSpeakPrompt(prompt))
        XCTAssertTrue(prompt.contains(spoken))
        XCTAssertTrue(GrokRealtime.verbatimSpeakInstructions(text: spoken).contains("word-for-word"))
        XCTAssertFalse(GrokRealtime.verbatimSpeakInstructions(text: spoken).contains("let the app handle"))
        XCTAssertFalse(GrokRealtime.teachesLeftoverDeskRouting(GrokRealtime.verbatimSpeakInstructions(text: spoken)))
        XCTAssertFalse(GrokRealtime.teachesNoTools(GrokRealtime.verbatimSpeakInstructions(text: spoken)))
        XCTAssertTrue(GrokRealtime.verbatimSpeakInstructions(text: spoken).contains(spoken))
        XCTAssertFalse(GrokRealtime.isVerbatimSpeakPrompt("What’s in my inbox?"))

        let verbatimSession = GrokRealtime.verbatimSpeakSessionUpdateObject(
            text: "VoiceDesk point 1, build 6."
        )
        let verbatimTurn = try XCTUnwrap(
            (verbatimSession["session"] as? [String: Any])?["turn_detection"] as? [String: Any]
        )
        XCTAssertEqual(verbatimTurn["type"] as? String, "server_vad")
        XCTAssertEqual(verbatimTurn["interrupt_response"] as? Bool, false)
        XCTAssertEqual(verbatimTurn["create_response"] as? Bool, false)
        XCTAssertTrue(
            (verbatimSession["session"] as? [String: Any])?["instructions"] as? String
                == GrokRealtime.verbatimSpeakInstructions(text: "VoiceDesk point 1, build 6.")
        )

        let listenResume = GrokRealtime.listenResumeSessionUpdateObject(
            voice: "eve",
            instructions: "listen"
        )
        let listenTurn = try XCTUnwrap(
            (listenResume["session"] as? [String: Any])?["turn_detection"] as? [String: Any]
        )
        XCTAssertEqual(listenTurn["type"] as? String, "server_vad")
        XCTAssertEqual(listenTurn["interrupt_response"] as? Bool, true)
        XCTAssertEqual(
            listenTurn["create_response"] as? Bool,
            true,
            "verbatim leave-behind create_response:false must be flipped back on"
        )
        XCTAssertEqual((listenResume["session"] as? [String: Any])?["instructions"] as? String, "listen")

        let resumeJSON = try XCTUnwrap(
            String(data: JSONSerialization.data(withJSONObject: listenResume), encoding: .utf8)
        )
        XCTAssertEqual(GrokRealtime.createResponse(inSessionUpdate: resumeJSON), true)
        let toolWait = GrokRealtime.toolWaitSessionUpdateObject()
        let toolWaitTurn = try XCTUnwrap(
            (toolWait["session"] as? [String: Any])?["turn_detection"] as? [String: Any]
        )
        XCTAssertEqual(toolWaitTurn["create_response"] as? Bool, false)
        XCTAssertFalse(GrokRealtime.vadCreatesOnSpeechStopped(createResponse: false))
        XCTAssertTrue(GrokRealtime.vadCreatesOnSpeechStopped(createResponse: true))
        XCTAssertTrue(GrokRealtime.vadCreatesOnSpeechStopped(createResponse: nil))
        let defaultJSON = try XCTUnwrap(
            String(data: GrokRealtime.sessionUpdateJSON(voice: "eve"), encoding: .utf8)
        )
        XCTAssertNil(
            GrokRealtime.createResponse(inSessionUpdate: defaultJSON),
            "omitted create_response is not a response request"
        )
    }

    func testCancelAndTextTurnPayloads() {
        XCTAssertEqual(GrokRealtime.responseCancelObject()["type"] as? String, "response.cancel")
        XCTAssertNil(
            GrokRealtime.responseCancelObject()["response_id"],
            "unscoped cancel races the next response.created"
        )
        let scoped = GrokRealtime.responseCancelObject(responseID: "resp_playing")
        XCTAssertEqual(scoped["type"] as? String, "response.cancel")
        XCTAssertEqual(scoped["response_id"] as? String, "resp_playing")
        XCTAssertEqual(GrokRealtime.responseIDToCancel(playingResponseID: "resp_playing"), "resp_playing")
        XCTAssertNil(GrokRealtime.responseIDToCancel(playingResponseID: nil))
        XCTAssertNil(GrokRealtime.responseIDToCancel(playingResponseID: ""))
        XCTAssertNil(
            GrokRealtime.responseIDToCancel(playingResponseID: "   "),
            "do not cancel the next created — only the playing answer"
        )
        XCTAssertEqual(
            GrokRealtime.bargeInDecision(
                hasPendingPlayback: false,
                alreadyBarged: false,
                playingResponseID: "resp_1",
                interruptTargetID: "resp_1",
                currentResponseID: nil,
                createdCountAtLatch: 0,
                createdCountNow: 0
            ),
            GrokRealtime.BargeInDecision(cancelResponseID: nil, dropLocal: false)
        )
        XCTAssertEqual(
            GrokRealtime.bargeInDecision(
                hasPendingPlayback: true,
                alreadyBarged: false,
                playingResponseID: "resp_1",
                interruptTargetID: "resp_1",
                currentResponseID: nil,
                createdCountAtLatch: 0,
                createdCountNow: 0
            ),
            GrokRealtime.BargeInDecision(cancelResponseID: nil, dropLocal: true),
            "barge drops local — do not send response.cancel"
        )
        XCTAssertEqual(
            GrokRealtime.bargeInDecision(
                hasPendingPlayback: true,
                alreadyBarged: false,
                playingResponseID: "resp_1",
                interruptTargetID: nil,
                currentResponseID: nil,
                createdCountAtLatch: 0,
                createdCountNow: 0
            ),
            GrokRealtime.BargeInDecision(cancelResponseID: nil, dropLocal: true),
            "barge drops local — do not send response.cancel"
        )
        XCTAssertEqual(
            GrokRealtime.bargeInDecision(
                hasPendingPlayback: true,
                alreadyBarged: false,
                playingResponseID: "resp_2",
                interruptTargetID: "resp_1",
                currentResponseID: "resp_2",
                createdCountAtLatch: 1,
                createdCountNow: 2
            ),
            GrokRealtime.BargeInDecision(cancelResponseID: nil, dropLocal: false),
            "interrupt answer already on the player — do not drop or cancel it"
        )
        XCTAssertTrue(
            GrokRealtime.shouldKeepInterruptAnswerOnPlayer(
                playingResponseID: "resp_2",
                interruptTargetID: "resp_1",
                currentResponseID: "resp_2",
                createdCountAtLatch: 1,
                createdCountNow: 2
            )
        )
        XCTAssertEqual(
            GrokRealtime.bargeInDecision(
                hasPendingPlayback: true,
                alreadyBarged: false,
                playingResponseID: "resp_1",
                interruptTargetID: "resp_1",
                currentResponseID: "resp_2",
                createdCountAtLatch: 1,
                createdCountNow: 2
            ),
            GrokRealtime.BargeInDecision(cancelResponseID: nil, dropLocal: true),
            "old answer still on the player — drop local, do not cancel the in-flight created"
        )
        XCTAssertEqual(
            GrokRealtime.bargeProofLine(
                createdID: "resp_2",
                scheduledID: "resp_1",
                cancelID: nil,
                audioDeltaCount: 0
            ),
            "created=resp_2 scheduled=resp_1 cancel=- deltas=0"
        )
        XCTAssertEqual(
            GrokRealtime.bargeProofLine(
                createdID: "resp_2",
                scheduledID: "resp_2",
                cancelID: "resp_1",
                audioDeltaCount: 3
            ),
            "created=resp_2 scheduled=resp_2 cancel=resp_1 deltas=3"
        )
        XCTAssertEqual(
            GrokRealtime.cancelledPlaybackResponseID(
                interruptTargetID: "resp_1",
                lastScheduledResponseID: "resp_1",
                playingResponseID: "resp_2"
            ),
            "resp_1"
        )
        XCTAssertEqual(
            GrokRealtime.cancelledPlaybackResponseID(
                interruptTargetID: nil,
                lastScheduledResponseID: nil,
                playingResponseID: nil,
                lastCreatedResponseID: "resp_1"
            ),
            "resp_1",
            "Grok PCM often omits response_id — latch the first created"
        )
        XCTAssertEqual(
            GrokRealtime.scheduledResponseID(
                deltaResponseID: nil,
                createdAwaitingAudioID: nil,
                lastCreatedResponseID: "resp_2"
            ),
            "resp_2"
        )
        XCTAssertEqual(GrokRealtime.playbackEpochLatch(3), "playback-epoch-3")
        XCTAssertEqual(
            GrokRealtime.latchWhenFirstAnswerPlaying(
                existingScheduledID: nil,
                createdID: "resp_1",
                playbackEpoch: 0
            ),
            "resp_1",
            "copy response.created onto the latch while the first answer is on the player"
        )
        XCTAssertEqual(
            GrokRealtime.latchWhenFirstAnswerPlaying(
                existingScheduledID: "playback-epoch-0",
                createdID: "resp_1",
                playbackEpoch: 0
            ),
            "resp_1",
            "created id wins over a prior epoch latch"
        )
        XCTAssertEqual(
            GrokRealtime.latchWhenFirstAnswerPlaying(
                existingScheduledID: nil,
                createdID: nil,
                playbackEpoch: 4
            ),
            "playback-epoch-4",
            "empty created id still latches leftover via playbackEpoch"
        )
        XCTAssertEqual(
            GrokRealtime.latchWhenFirstAnswerPlaying(
                existingScheduledID: "resp_1",
                createdID: "resp_2",
                playbackEpoch: 0
            ),
            "resp_1",
            "drain-before-transcript interrupt created must not overwrite the first-answer latch"
        )
        XCTAssertTrue(
            GrokRealtime.shouldOverwriteScheduledLatch(
                existingScheduledID: nil,
                taggedID: "resp_1",
                deltaResponseID: nil,
                cancelledResponseID: nil
            )
        )
        XCTAssertFalse(
            GrokRealtime.shouldOverwriteScheduledLatch(
                existingScheduledID: "resp_1",
                taggedID: "resp_2",
                deltaResponseID: nil,
                cancelledResponseID: nil
            ),
            "leftover leftover no-id must not stamp lastCreated onto lastScheduled"
        )
        XCTAssertTrue(
            GrokRealtime.shouldOverwriteScheduledLatch(
                existingScheduledID: "resp_1",
                taggedID: "resp_2",
                deltaResponseID: "resp_2",
                cancelledResponseID: "resp_1"
            ),
            "interrupt JSON response_id may replace the first-answer latch"
        )
        XCTAssertFalse(
            GrokRealtime.shouldOverwriteScheduledLatch(
                existingScheduledID: "resp_1",
                taggedID: "resp_1",
                deltaResponseID: "resp_1",
                cancelledResponseID: "resp_1"
            ),
            "leftover first-answer id must not re-latch"
        )
        XCTAssertEqual(
            GrokRealtime.parse(
                type: "response.created",
                json: ["response_id": "resp_created_top"]
            ),
            .responseCreated(id: "resp_created_top"),
            "xAI may put the created id at response_id, not response.id"
        )
        XCTAssertEqual(
            GrokRealtime.interruptAnswerID(
                createdAwaitingAudioID: "resp_2",
                lastCreatedResponseID: "resp_2",
                cancelledResponseID: "resp_1"
            ),
            "resp_2"
        )
        XCTAssertNil(
            GrokRealtime.interruptAnswerID(
                createdAwaitingAudioID: nil,
                lastCreatedResponseID: "resp_1",
                cancelledResponseID: "resp_1"
            ),
            "first-answer created is not the interrupt answer"
        )
        XCTAssertTrue(
            GrokRealtime.shouldScheduleAfterBarge(
                bargeConsumed: false,
                deltaResponseID: "resp_1",
                cancelledResponseID: nil,
                interruptAnswerID: nil
            ),
            "before barge every delta may schedule"
        )
        XCTAssertFalse(
            GrokRealtime.shouldScheduleAfterBarge(
                bargeConsumed: true,
                deltaResponseID: "resp_1",
                cancelledResponseID: "resp_1",
                interruptAnswerID: "resp_2"
            ),
            "leftover first-answer deltas must not raise pending"
        )
        XCTAssertFalse(
            GrokRealtime.shouldScheduleAfterBarge(
                bargeConsumed: true,
                deltaResponseID: "resp_1",
                cancelledResponseID: "resp_1",
                interruptAnswerID: nil
            ),
            "leftover first-answer before the interrupt created must not schedule"
        )
        XCTAssertTrue(
            GrokRealtime.shouldScheduleAfterBarge(
                bargeConsumed: true,
                deltaResponseID: "resp_2",
                cancelledResponseID: "resp_1",
                interruptAnswerID: "resp_2"
            ),
            "interrupt-answer id may raise pending"
        )
        XCTAssertTrue(
            GrokRealtime.shouldScheduleAfterBarge(
                bargeConsumed: true,
                deltaResponseID: nil,
                cancelledResponseID: "resp_1",
                interruptAnswerID: "resp_2"
            ),
            "Grok PCM without response_id is R2 — do not eat the interrupt answer"
        )
        XCTAssertTrue(
            GrokRealtime.shouldScheduleAfterBarge(
                bargeConsumed: true,
                deltaResponseID: nil,
                cancelledResponseID: "resp_1",
                interruptAnswerID: nil
            ),
            "after barge, wire no-id must schedule even when lastCreated is still the first answer — callers must not invent an id to reject"
        )
        XCTAssertFalse(
            GrokRealtime.shouldScheduleAfterBarge(
                bargeConsumed: false,
                deltaResponseID: "resp_1",
                cancelledResponseID: nil,
                lastScheduledResponseID: "resp_1",
                hasPendingPlayback: false
            ),
            "1488 can pass on lastScheduled while cancelled is nil — drained leftover of that id must not raise pending"
        )
        XCTAssertTrue(
            GrokRealtime.shouldScheduleAfterBarge(
                bargeConsumed: false,
                deltaResponseID: "resp_1",
                cancelledResponseID: nil,
                lastScheduledResponseID: "resp_1",
                hasPendingPlayback: true
            ),
            "first-answer deltas while pending > 0 are the answer, not leftover"
        )
        XCTAssertTrue(
            GrokRealtime.shouldScheduleAfterBarge(
                bargeConsumed: false,
                deltaResponseID: nil,
                cancelledResponseID: nil,
                lastScheduledResponseID: "resp_1",
                hasPendingPlayback: false
            ),
            "no-id after drain is R2 — do not eat the interrupt answer"
        )
        XCTAssertEqual(
            GrokRealtime.scheduledResponseID(
                deltaResponseID: nil,
                createdAwaitingAudioID: nil,
                lastCreatedResponseID: "resp_1"
            ),
            "resp_1",
            "filling lastCreated into the barge gate stamps leftover first-answer and eats R2"
        )
        XCTAssertTrue(
            GrokRealtime.shouldScheduleAfterBarge(
                bargeConsumed: true,
                deltaResponseID: "resp_2",
                cancelledResponseID: nil,
                interruptAnswerID: nil
            ),
            "a nil latch must not drop every delta (dropAssistantAudio in disguise)"
        )
        XCTAssertFalse(
            GrokRealtime.shouldArmCommandBargeLatch(
                alreadyBarged: false,
                hasPendingPlayback: false,
                lastScheduledResponseID: nil,
                playingResponseID: nil
            ),
            "first listen — no answer on the player — is not a barge"
        )
        XCTAssertEqual(
            GrokRealtime.cancelledPlaybackResponseID(
                interruptTargetID: nil,
                lastScheduledResponseID: nil,
                playingResponseID: nil,
                lastCreatedResponseID: "resp_1"
            ),
            "resp_1"
        )
        XCTAssertFalse(
            GrokRealtime.shouldArmCommandBargeLatch(
                alreadyBarged: false,
                hasPendingPlayback: false,
                lastScheduledResponseID: nil,
                playingResponseID: nil
            ),
            "lastCreated-only at pending 0 is first-answer audio about to arrive — do not arm leftover reject"
        )
        XCTAssertEqual(
            GrokRealtime.keepScheduledLatchAfterResponseDone(existingScheduledID: "resp_1"),
            "resp_1",
            "first-answer done must keep lastScheduled — command barge after drain arms leftover from it"
        )
        XCTAssertNil(GrokRealtime.keepScheduledLatchAfterResponseDone(existingScheduledID: nil))
        XCTAssertTrue(
            GrokRealtime.shouldArmCommandBargeLatch(
                alreadyBarged: false,
                hasPendingPlayback: false,
                lastScheduledResponseID: GrokRealtime.keepScheduledLatchAfterResponseDone(
                    existingScheduledID: "resp_1"
                ),
                playingResponseID: nil
            ),
            "kept lastScheduled after done arms leftover without treating lastCreated as a barge"
        )
        XCTAssertTrue(
            GrokRealtime.shouldWriteScheduledLatchOnPlay(
                existingScheduledID: nil,
                bargeConsumed: false
            ),
            "first pending rise must write lastScheduled — nil != nil skips noteScheduled"
        )
        XCTAssertTrue(
            GrokRealtime.shouldWriteScheduledLatchOnPlay(
                existingScheduledID: nil,
                bargeConsumed: true
            ),
            "play after a pending-only barge must still latch — leftover inject needs the id"
        )
        XCTAssertTrue(
            GrokRealtime.shouldWriteScheduledLatchOnPlay(
                existingScheduledID: "resp_1",
                bargeConsumed: false
            ),
            "first answer may refresh lastScheduled from created"
        )
        XCTAssertFalse(
            GrokRealtime.shouldWriteScheduledLatchOnPlay(
                existingScheduledID: "resp_1",
                bargeConsumed: true
            ),
            "after barge do not overwrite the cancelled first-answer latch with lastCreated"
        )
        XCTAssertTrue(
            GrokRealtime.shouldArmCommandBargeLatch(
                alreadyBarged: false,
                hasPendingPlayback: false,
                lastScheduledResponseID: "resp_1",
                playingResponseID: nil
            ),
            "drained first answer still has lastScheduled — latch leftover, do not drop"
        )
        XCTAssertTrue(
            GrokRealtime.shouldArmCommandBargeLatch(
                alreadyBarged: false,
                hasPendingPlayback: false,
                lastScheduledResponseID: nil,
                playingResponseID: "resp_1"
            ),
            "playing id without pending still means an answer was on the player"
        )
        XCTAssertTrue(
            GrokRealtime.shouldArmCommandBargeLatch(
                alreadyBarged: false,
                hasPendingPlayback: true,
                lastScheduledResponseID: nil,
                playingResponseID: nil
            ),
            "first-answer PCM with no response_id must still drop"
        )
        XCTAssertFalse(
            GrokRealtime.shouldArmCommandBargeLatch(
                alreadyBarged: true,
                hasPendingPlayback: true,
                lastScheduledResponseID: "resp_1",
                playingResponseID: "resp_1"
            ),
            "second interruptResponse must not re-drop the interrupt answer"
        )
        XCTAssertEqual(
            GrokRealtime.bargeInDecision(
                hasPendingPlayback: false,
                alreadyBarged: false,
                playingResponseID: nil,
                interruptTargetID: "resp_1",
                currentResponseID: "resp_1",
                createdCountAtLatch: 1,
                createdCountNow: 1
            ),
            GrokRealtime.BargeInDecision(cancelResponseID: nil, dropLocal: false),
            "pending 0 must latch leftover, not drop"
        )
        XCTAssertFalse(
            GrokRealtime.shouldScheduleAfterBarge(
                bargeConsumed: true,
                deltaResponseID: "resp_1",
                cancelledResponseID: "resp_1"
            ),
            "leftover JSON with the latched first-answer id must not raise pending"
        )
        XCTAssertFalse(
            GrokRealtime.shouldResetBargeAfterResponseDone(
                bargeConsumed: true,
                interruptAnswerScheduled: false,
                lastScheduledResponseID: "resp_1",
                cancelledResponseID: "resp_1"
            ),
            "leftover first-answer done must keep the cancelled latch"
        )
        XCTAssertFalse(
            GrokRealtime.shouldResetBargeAfterResponseDone(
                bargeConsumed: true,
                interruptAnswerScheduled: true,
                lastScheduledResponseID: "resp_1",
                cancelledResponseID: "resp_1"
            ),
            "no-id leftover that re-stamped the first-answer id is not the interrupt answer"
        )
        XCTAssertFalse(
            GrokRealtime.shouldResetBargeAfterResponseDone(
                bargeConsumed: true,
                interruptAnswerScheduled: true,
                lastScheduledResponseID: "resp_2",
                cancelledResponseID: "resp_1",
                doneResponseID: "resp_1"
            ),
            "first-answer done must not clear the latch even if R2 already scheduled"
        )
        XCTAssertFalse(
            GrokRealtime.shouldResetBargeAfterResponseDone(
                bargeConsumed: true,
                interruptAnswerScheduled: true,
                lastScheduledResponseID: nil,
                cancelledResponseID: "resp_1"
            ),
            "pending-0 first-answer done with a cleared schedule must keep the cancelled id"
        )
        XCTAssertTrue(
            GrokRealtime.shouldResetBargeAfterResponseDone(
                bargeConsumed: true,
                interruptAnswerScheduled: true,
                lastScheduledResponseID: "resp_2",
                cancelledResponseID: "resp_1",
                doneResponseID: "resp_2"
            ),
            "only a different scheduled interrupt-answer id may reset bargeConsumed"
        )
        XCTAssertFalse(
            GrokRealtime.shouldResetBargeAfterResponseDone(
                bargeConsumed: false,
                interruptAnswerScheduled: true,
                lastScheduledResponseID: "resp_2",
                cancelledResponseID: "resp_1"
            )
        )
        XCTAssertEqual(
            GrokRealtime.bargeInDecision(
                hasPendingPlayback: true,
                alreadyBarged: true,
                playingResponseID: "resp_2",
                interruptTargetID: "resp_2",
                currentResponseID: "resp_2",
                createdCountAtLatch: 1,
                createdCountNow: 2
            ),
            GrokRealtime.BargeInDecision(cancelResponseID: nil, dropLocal: false),
            "second interruptResponse must not cancel the interrupt answer"
        )
        XCTAssertEqual(
            GrokRealtime.bargeInDecision(
                hasPendingPlayback: true,
                alreadyBarged: false,
                playingResponseID: nil,
                interruptTargetID: "resp_1",
                currentResponseID: nil,
                createdCountAtLatch: 0,
                createdCountNow: 0
            ),
            GrokRealtime.BargeInDecision(cancelResponseID: nil, dropLocal: true),
            "barge drops local — do not send response.cancel"
        )
        XCTAssertEqual(
            GrokRealtime.bargeInDecision(
                hasPendingPlayback: true,
                alreadyBarged: false,
                playingResponseID: nil,
                interruptTargetID: nil,
                currentResponseID: nil,
                createdCountAtLatch: 0,
                createdCountNow: 0
            ),
            GrokRealtime.BargeInDecision(cancelResponseID: nil, dropLocal: true)
        )
        XCTAssertFalse(
            GrokRealtime.shouldKeepInterruptAnswerOnPlayer(
                playingResponseID: "resp_1",
                interruptTargetID: "resp_1",
                currentResponseID: "resp_2",
                createdCountAtLatch: 1,
                createdCountNow: 2
            ),
            "old answer still on the player must drop locally"
        )
        XCTAssertEqual(
            GrokRealtime.latchedInterruptTarget(existing: "resp_1", scheduledResponseID: "resp_2"),
            "resp_1",
            "do not overwrite the barge target with the next created"
        )
        XCTAssertEqual(
            GrokRealtime.latchedInterruptTarget(existing: nil, scheduledResponseID: "resp_1"),
            "resp_1"
        )
        XCTAssertNil(GrokRealtime.latchedInterruptTarget(existing: "  ", scheduledResponseID: nil))
        XCTAssertEqual(GrokRealtime.clearBufferObject()["type"] as? String, "input_audio_buffer.clear")
        XCTAssertEqual(GrokRealtime.commitAudioBufferObject()["type"] as? String, "input_audio_buffer.commit")

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
