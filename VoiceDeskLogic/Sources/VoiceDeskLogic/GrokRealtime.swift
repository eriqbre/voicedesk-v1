import Foundation

/// xAI Speech-to-Speech (Voice Agent) wire helpers.
/// Ported from docs.x.ai + the xai-cookbook iOS VoiceTesterApp — do not invent a half protocol.
public enum GrokRealtime {
    public static let defaultModel = "grok-voice-latest"
    public static let defaultVoice = "eve"
    public static let sampleRate = 24_000
    public static let realtimeHost = "wss://api.x.ai/v1/realtime"
    public static let clientSecretsPath = "https://api.x.ai/v1/realtime/client_secrets"

    public static func realtimeURLString(model: String = defaultModel) -> String {
        "\(realtimeHost)?model=\(model)"
    }

    /// Disconnected / first-run sample desk. Do not use after Google is connected.
    public static let presenceInstructions = presenceInstructions(for: .disconnected)

    /// Second-person VoiceDesk presence. Cards attach in the iOS app from desk evidence;
    /// this prompt only shapes spoken Grok. No tools are registered this slice.
    public static func presenceInstructions(for context: DeskContext) -> String {
        let deskBlock: String
        if context.isConnected {
            deskBlock = connectedDeskFacts(context.snapshot)
        } else {
            deskBlock = """
            You work with Bridget at Coastal Tampa Bay. Sample desk you already know (not live Gmail yet):
            - Jordan Hale emailed this morning about a Saturday showing at 1842 Beach Drive NE, St. Petersburg.
            - Fla. Stat. § 475.278 covers brokerage-relationship disclosure. Treat legal answers as guidance, not legal advice. Confidence on that sample is 86 percent, firm.
            """
        }

        let deskObjective = context.isConnected
            ? "When the topic is their desk, stay silent. The iOS app owns every Gmail, calendar, and task ask, including full email, body, and summary. You will not handle those turns. The client interrupts you."
            : "When the topic is their desk, stay concrete about the sample evidence. When it is not, just talk. Never pretend a message was sent."

        let deskFlow = context.isConnected
            ? "If they ask about inbox, calendar, tasks, a full email, a body, or a summary, do not answer. Stay silent. The client owns those turns. Do not mention any sample listing or sample inbox as if it were live mail. Do not invent live Gmail, calendar, or MLS data. Do not claim you sent mail. NEVER mention an Email card, Calendar card, or that a message is waiting on a card. NEVER say pull-to-refresh. NEVER paste a full email body, quoted history, or raw URLs into the conversation. NEVER say open it in Gmail. NEVER say they need Gmail for the rest. NEVER say you cannot pull a thread or the full email, that a thread is not in the last sync, that all you have is the latest note, or that you only have a snippet. NEVER say you are searching, will search, can search Gmail, or are looking anything up. NEVER describe mail as snippet-only. NEVER narrate routing. NEVER say you’ll let the app handle that, you’ll look that up in the app, or that you’re handing the turn off."
            : "If they ask about inbox, Beach Drive, a reply, or Florida disclosure, you may refer to the sample desk facts. Do not invent live Gmail, calendar, or MLS data. Do not claim you sent mail. NEVER say open it in Gmail. NEVER say they need Gmail for the rest."

        let googleConnectGuard: String
        if context.isConnected {
            let email = context.auth.email ?? context.snapshot.accountEmail ?? "their Google account"
            googleConnectGuard = """
            Google is ALREADY connected as \(email). There is NO Settings screen, no Account menu, and no Integrations page. If they say “connect Google” or ask how to connect, say exactly: You’re already connected as \(email). Use Disconnect on the card if you need to switch. NEVER say you cannot connect it. NEVER invent Settings, Account, or Integrations menus. NEVER tell them to open app settings or Google sign-in settings. NEVER tell them to do it themselves in Integrations.
            """
        } else {
            googleConnectGuard = """
            There is NO Settings screen for Google. There is no Account menu and no Integrations page. The Connect Google card is how they connect. If they ask to connect Google, or how to connect, say exactly: Tap Connect Google on the card below. NEVER say you cannot connect it. NEVER invent Settings, Account, or Integrations menus. NEVER tell them to open app settings or Google sign-in settings. NEVER tell them to do it themselves in Integrations.
            """
        }

        return """
        ## Role & Persona
        You are VoiceDesk — a person who already knows this realtor’s world. You talk like a colleague sitting next to them, not a command menu. You answer anything they ask, desk or not.

        \(deskBlock)

        ## Objective
        Be someone they can talk to about anything. \(deskObjective)

        ## Conversation Flow
        Listen. Answer in a few spoken sentences. \(deskFlow)

        ## Guardrails & Escalation
        NEVER say an email was sent or a write happened. Confirm-before-act: drafts wait for the person. You have no tools this slice — do not pretend to call functions. You are not a lawyer. If they mention self-harm or a crisis, respond with care and point them to emergency services or 988.
        \(googleConnectGuard)

        ## Voice & Communication Style
        Spoken word only: no markdown, no bullets, no emojis. One or two short sentences unless they want more. Warm, direct, English. Vary phrasing.

        ## CRITICAL INSTRUCTIONS
        NEVER report a send as delivered. NEVER invent live inbox or MLS facts beyond the desk facts above. The iOS app attaches evidence cards separately — you just talk.
        NEVER tell them to open Settings, Account, or Integrations. Those screens do not exist.
        NEVER say you cannot connect Google. NEVER bounce them to Gmail for a message body.
        NEVER mention an Email card or that a full message is waiting on a card. The client attaches cards. NEVER say pull-to-refresh.
        NEVER paste a full email body or quoted thread into the conversation.
        NEVER say you cannot pull a thread or the full email, that a thread is not in the last sync, or that all you have is a snippet. The client fetches full bodies.
        NEVER say you are searching, will search, can search Gmail, or are looking anything up. The client handles all Gmail reads.
        NEVER narrate routing. NEVER say you’ll let the app handle that or that you’ll look that up in the app. Stay silent on desk turns.
        If they ask for a full email, summary, or body, stay silent. Body pulls are client-owned.
        \(context.isConnected
            ? "If they ask to connect Google, say exactly: You’re already connected as \(context.auth.email ?? context.snapshot.accountEmail ?? "their Google account"). Use Disconnect on the card if you need to switch."
            : "How to connect Google — say exactly: Tap Connect Google on the card below.")
        """
    }

    public static func connectedDeskFacts(_ snapshot: DeskSnapshot) -> String {
        var lines: [String] = [
            "Google is connected\(snapshot.accountEmail.map { " as \($0)" } ?? ""). These are last-synced facts: from, subject, and when only. The client handles all Gmail reads, including full body and summary. You do not search. You do not look anything up. Do not invent mail. Do not say a message is not synced or that you only have a snippet. If they ask for a full email, summary, or body, stay silent — the client interrupts you."
        ]
        if let synced = snapshot.lastSyncedAt {
            lines.append("Last synced: \(DeskSnapshot.timeLabel(synced)).")
        }
        if snapshot.emails.isEmpty {
            lines.append("Inbox list is empty. If they ask about mail, stay silent; the client owns the turn.")
        } else {
            lines.append("Inbox (from / subject / when only — no bodies, no snippets):")
            for email in snapshot.emails.prefix(8) {
                lines.append("- \(email.fromName): \(email.subject) (\(email.sentAtLabel)).")
            }
        }
        if snapshot.events.isEmpty {
            lines.append("Calendar: nothing upcoming in the last sync.")
        } else {
            lines.append("Calendar (only these):")
            for event in snapshot.events.prefix(8) {
                lines.append("- \(event.title) — \(event.whenLabel)")
            }
        }
        if snapshot.tasks.isEmpty {
            lines.append("Tasks: no open tasks in the last sync.")
        } else {
            lines.append("Open tasks (only these):")
            for task in snapshot.tasks.prefix(8) {
                lines.append("- \(task.title)")
            }
        }
        lines.append("Fla. Stat. § 475.278 still covers brokerage-relationship disclosure. Treat legal answers as guidance, not legal advice.")
        return lines.joined(separator: "\n")
    }

    public static func sessionUpdateObject(
        voice: String = defaultVoice,
        instructions: String = presenceInstructions,
        interruptResponse: Bool? = nil,
        createResponse: Bool? = nil
    ) -> [String: Any] {
        [
            "type": "session.update",
            "session": [
                "voice": voice,
                "instructions": instructions,
                "turn_detection": turnDetectionObject(
                    interruptResponse: interruptResponse,
                    createResponse: createResponse
                ),
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": sampleRate
                        ] as [String: Any]
                    ] as [String: Any],
                    "output": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": sampleRate
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ]
    }

    /// Default listen / first-tap: server VAD only. Verbatim speak passes
    /// `interruptResponse: false` so her own echo cannot cancel the line.
    public static func turnDetectionObject(
        interruptResponse: Bool? = nil,
        createResponse: Bool? = nil
    ) -> [String: Any] {
        var turn: [String: Any] = ["type": "server_vad"]
        if let interruptResponse {
            turn["interrupt_response"] = interruptResponse
        }
        if let createResponse {
            turn["create_response"] = createResponse
        }
        return turn
    }

    /// Eve reads this line. Mic stays live; server must not barge-in on echo.
    public static func verbatimSpeakSessionUpdateObject(
        voice: String = defaultVoice,
        text: String
    ) -> [String: Any] {
        sessionUpdateObject(
            voice: voice,
            instructions: verbatimSpeakInstructions(text: text),
            interruptResponse: false,
            createResponse: false
        )
    }

    /// Put the socket back in listen mode after a local desk / verbatim line.
    /// Verbatim speak sets `create_response: false`; omitting the flag on the
    /// next `session.update` can leave the server from committing the next ask.
    public static func listenResumeSessionUpdateObject(
        voice: String = defaultVoice,
        instructions: String = presenceInstructions
    ) -> [String: Any] {
        sessionUpdateObject(
            voice: voice,
            instructions: instructions,
            interruptResponse: true,
            createResponse: true
        )
    }

    /// `nil` if this is not a session.update or the flag was omitted.
    public static func createResponse(inSessionUpdate raw: String) -> Bool? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "session.update",
              let session = object["session"] as? [String: Any],
              let turn = session["turn_detection"] as? [String: Any],
              turn["create_response"] != nil
        else { return nil }
        if let flag = turn["create_response"] as? Bool { return flag }
        return (turn["create_response"] as? NSNumber)?.boolValue
    }

    public static func sessionUpdateJSON(
        voice: String = defaultVoice,
        instructions: String = presenceInstructions
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: sessionUpdateObject(voice: voice, instructions: instructions))
    }

    /// Hot-path mic frame. Base64 alphabet is JSON-safe.
    public static func appendAudioJSON(base64: String) -> String {
        #"{"type":"input_audio_buffer.append","audio":"\#(base64)"}"#
    }

    /// Unscoped cancel races the next `response.created` and kills the
    /// interrupt answer — leftover created, pending 0. Barge-in must
    /// pass the playing response's id.
    public static func responseCancelObject(responseID: String? = nil) -> [String: Any] {
        var object: [String: Any] = ["type": "response.cancel"]
        if let responseID, !responseID.isEmpty {
            object["response_id"] = responseID
        }
        return object
    }

    /// Cancel the answer that is on the player. Do not fall back to
    /// `currentResponseID` — that is already the next created.
    public static func responseIDToCancel(playingResponseID: String?) -> String? {
        nonemptyID(playingResponseID)
    }

    /// What barge-in may do to the one-engine player.
    ///
    /// Server VAD often creates the interrupt answer before the user
    /// transcript arrives. `playingResponseID` then becomes that new
    /// created. Cancelling it is leftover created, pending 0.
    public enum BargeInPlayback: Equatable, Sendable {
        case none
        case cancel(responseID: String)
        case dropLocalOnly
        case keepNewAnswer
    }

    public static func bargeInPlayback(
        hasPendingPlayback: Bool,
        playingResponseID: String?,
        interruptTargetID: String?
    ) -> BargeInPlayback {
        guard hasPendingPlayback else { return .none }
        let playing = nonemptyID(playingResponseID)
        let target = nonemptyID(interruptTargetID) ?? playing
        if let playing, let target, playing != target {
            return .keepNewAnswer
        }
        if let target {
            return .cancel(responseID: target)
        }
        return .dropLocalOnly
    }

    /// First `speech_started` / first scheduled buffer latches the
    /// answer that barge-in may cancel. Do not overwrite with the next
    /// created.
    public static func latchedInterruptTarget(
        existing: String?,
        scheduledResponseID: String?
    ) -> String? {
        nonemptyID(existing) ?? nonemptyID(scheduledResponseID)
    }

    public static func nonemptyID(_ id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return nil
        }
        return id
    }

    public static func clearBufferObject() -> [String: Any] {
        ["type": "input_audio_buffer.clear"]
    }

    /// Close a queued utterance after a dead-socket flush. The speaker
    /// already stopped. Server VAD will not see trailing silence.
    public static func commitAudioBufferObject() -> [String: Any] {
        ["type": "input_audio_buffer.commit"]
    }

    public static let speakVerbatimMarker = "SPEAK_VERBATIM"

    /// Desk replies use on-device TTS. Always false — do not inject a fake
    /// user turn + `response.create` so Grok can speak a local line.
    public static func shouldSpeakViaRealtime(
        usesLiveLoop: Bool,
        isConnected: Bool,
        userWantsVoiceOff: Bool
    ) -> Bool {
        _ = usesLiveLoop
        _ = isConnected
        _ = userWantsVoiceOff
        return false
    }

    public static func verbatimSpeakInstructions(text: String) -> String {
        """
        Speak the SPEAK_VERBATIM block word-for-word. No other words. No greeting. No paraphrase.
        Do not say you will let the app handle anything. After you finish, stay silent.

        SPEAK_VERBATIM
        \(text)
        SPEAK_VERBATIM
        """
    }

    public static func verbatimSpeakUserText(text: String) -> String {
        "SPEAK_VERBATIM\n\(text)\nSPEAK_VERBATIM"
    }

    public static func isVerbatimSpeakPrompt(_ raw: String) -> Bool {
        raw.contains(speakVerbatimMarker)
    }

    public static func textItemObject(_ text: String) -> [String: Any] {
        [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": text] as [String: Any]
                ] as [[String: Any]]
            ] as [String: Any]
        ]
    }

    public static func responseCreateObject() -> [String: Any] {
        [
            "type": "response.create",
            "response": [
                "modalities": ["text", "audio"]
            ] as [String: Any]
        ]
    }

    public static func pongObject(timestamp: Int64) -> [String: Any] {
        ["type": "pong", "ping_timestamp": timestamp]
    }

    public enum EventKind: Equatable, Sendable {
        case sessionCreated
        case sessionUpdated
        case speechStarted
        case speechStopped
        case audioCommitted
        case userTranscript(text: String, itemID: String?)
        case responseCreated(id: String)
        case assistantTranscriptDelta(String, source: AssistantTranscriptSource)
        case assistantTranscriptDone
        case outputAudioDelta(String)
        case outputAudioDone
        case responseDone(id: String?)
        case ping(timestamp: Int64)
        case error(code: String, message: String)
        case ignored
    }

    public static func parse(type: String, json: [String: Any]) -> EventKind {
        switch type {
        case "session.created":
            return .sessionCreated
        case "session.updated":
            return .sessionUpdated
        case "input_audio_buffer.speech_started":
            return .speechStarted
        case "input_audio_buffer.speech_stopped":
            return .speechStopped
        case "input_audio_buffer.committed":
            return .audioCommitted
        case "conversation.item.input_audio_transcription.completed",
             "input_audio_transcription.completed":
            let text = userText(in: json) ?? ""
            return .userTranscript(text: text, itemID: itemID(in: json))
        case "conversation.item.created", "conversation.item.added":
            guard let text = userText(in: json), !text.isEmpty else { return .ignored }
            return .userTranscript(text: text, itemID: itemID(in: json))
        case "response.created":
            let id = (json["response"] as? [String: Any])?["id"] as? String ?? ""
            return .responseCreated(id: id)
        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            return .assistantTranscriptDelta((json["delta"] as? String) ?? "", source: .audio)
        case "response.output_text.delta":
            return .assistantTranscriptDelta((json["delta"] as? String) ?? "", source: .outputText)
        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            return .assistantTranscriptDone
        case "response.output_audio.delta", "response.audio.delta":
            let delta = (json["delta"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .outputAudioDelta(delta ?? (json["audio"] as? String) ?? "")
        case "response.output_audio.done", "response.audio.done":
            return .outputAudioDone
        case "response.done":
            return .responseDone(id: responseID(in: json))
        case "ping":
            if let timestamp = int64(json["ping_timestamp"]) {
                return .ping(timestamp: timestamp)
            }
            return .ignored
        case "error":
            return .error(
                code: json["code"] as? String ?? "",
                message: json["message"] as? String ?? "Unknown"
            )
        default:
            return .ignored
        }
    }

    public static func responseID(in json: [String: Any]) -> String? {
        if let id = json["response_id"] as? String, !id.isEmpty { return id }
        if let response = json["response"] as? [String: Any],
           let id = response["id"] as? String, !id.isEmpty {
            return id
        }
        return nil
    }

    public static func itemID(in json: [String: Any]) -> String? {
        if let id = json["item_id"] as? String, !id.isEmpty { return id }
        if let item = json["item"] as? [String: Any], let id = item["id"] as? String, !id.isEmpty {
            return id
        }
        return nil
    }

    public static func userText(in json: [String: Any]) -> String? {
        if let text = nonempty(json["transcript"]) { return text }
        guard let item = json["item"] as? [String: Any],
              (item["role"] as? String) == "user"
        else { return nil }
        if let text = nonempty(item["transcript"]) { return text }
        guard let content = item["content"] as? [[String: Any]] else { return nil }
        for part in content {
            if let text = nonempty(part["transcript"]) { return text }
            if let text = nonempty(part["text"]) { return text }
        }
        return nil
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }
}
