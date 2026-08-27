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

    /// Second-person VoiceDesk presence. Eve speaks the reply from
    /// last-synced facts. Do not teach leftover desk-routing language
    /// ("the app will take this", "stay silent, the client owns it").
    public static func presenceInstructions(
        for context: DeskContext,
        identity: BuildIdentity = .unknown
    ) -> String {
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
            ? "When the topic is their desk, you speak the answer from the last-synced facts. You own intent and the spoken reply."
            : "When the topic is their desk, stay concrete about the sample evidence. When it is not, just talk. Never pretend a message was sent."

        let deskFlow = context.isConnected
            ? "If they ask about inbox, calendar, tasks, a full email, a body, or a summary, answer from the facts you have. If a body is not in the facts yet, acknowledge that you heard them and that you are checking — in your own words. Do not invent live Gmail, calendar, or MLS data. Do not claim you sent mail. Do not mention any sample listing or sample inbox as if it were live mail. NEVER mention an Email card, Calendar card, or that a message is waiting on a card. NEVER say pull-to-refresh. NEVER paste a full email body, quoted history, or raw URLs into the conversation. NEVER say open it in Gmail. NEVER say they need Gmail for the rest. NEVER say you cannot pull a thread or the full email, that a thread is not in the last sync, that all you have is the latest note, or that you only have a snippet. NEVER describe mail as snippet-only."
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
        \(identityFacts(identity))

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
        NEVER report a send as delivered. NEVER invent live inbox or MLS facts beyond the desk facts above.
        NEVER tell them to open Settings, Account, or Integrations. Those screens do not exist.
        NEVER say you cannot connect Google. NEVER bounce them to Gmail for a message body.
        NEVER mention an Email card or that a full message is waiting on a card. NEVER say pull-to-refresh.
        NEVER paste a full email body or quoted thread into the conversation.
        NEVER say you cannot pull a thread or the full email, that a thread is not in the last sync, or that all you have is a snippet.
        If they ask for a full email, summary, or body, answer from the facts. If the body is not there yet, acknowledge in your own words that you heard them and are checking. Do not invent the body.
        \(context.isConnected
            ? "If they ask to connect Google, say exactly: You’re already connected as \(context.auth.email ?? context.snapshot.accountEmail ?? "their Google account"). Use Disconnect on the card if you need to switch."
            : "How to connect Google — say exactly: Tap Connect Google on the card below.")
        """
    }

    public static func identityFacts(_ identity: BuildIdentity) -> String {
        if identity.spokenLine == BuildIdentity.unknownSpokenLine, identity.shortSHA.isEmpty {
            return "Build identity is unknown."
        }
        let sha = identity.shortSHA.isEmpty ? "unknown" : identity.shortSHA
        return "Build identity: \(identity.spokenLine) SHA \(sha)."
    }

    public static func connectedDeskFacts(_ snapshot: DeskSnapshot) -> String {
        var lines: [String] = [
            "Google is connected\(snapshot.accountEmail.map { " as \($0)" } ?? ""). These are last-synced facts: from, subject, and when, plus a body when it is here. You speak the answer. Do not invent mail. Do not say a message is not synced or that you only have a snippet."
        ]
        if let synced = snapshot.lastSyncedAt {
            lines.append("Last synced: \(DeskSnapshot.timeLabel(synced)).")
        }
        if snapshot.emails.isEmpty {
            lines.append("Inbox list is empty.")
        } else {
            lines.append("Inbox (from / subject / when; body when fetched):")
            for email in snapshot.emails.prefix(8) {
                var line = "- \(email.fromName): \(email.subject) (\(email.sentAtLabel))."
                if email.hasFullBody {
                    let body = (email.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty {
                        let clipped = body.count > 400 ? String(body.prefix(400)).trimmingCharacters(in: .whitespaces) + "…" : body
                        line += " Body: \(clipped)"
                    }
                }
                lines.append(line)
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
    /// transcript arrives. Sending `response.cancel` — even scoped to
    /// the old id — can kill that in-flight created on xAI (leftover
    /// created, pending 0). Local drop is the player. Do not drop if
    /// the interrupt answer is already scheduled.
    public enum BargeInPlayback: Equatable, Sendable {
        case none
        case cancel(responseID: String)
        case dropLocalOnly
    }

    public struct BargeInDecision: Equatable, Sendable {
        public var cancelResponseID: String?
        public var dropLocal: Bool

        public init(cancelResponseID: String?, dropLocal: Bool) {
            self.cancelResponseID = cancelResponseID
            self.dropLocal = dropLocal
        }
    }

    /// `created` / `scheduled` / `cancel` ids plus post-barge deltas.
    /// Leftover created with deltas=0 is a silent / cancelled answer.
    public static func bargeProofLine(
        createdID: String?,
        scheduledID: String?,
        cancelID: String?,
        audioDeltaCount: Int
    ) -> String {
        let created = nonemptyID(createdID) ?? "-"
        let scheduled = nonemptyID(scheduledID) ?? "-"
        let cancel = nonemptyID(cancelID) ?? "-"
        return "created=\(created) scheduled=\(scheduled) cancel=\(cancel) deltas=\(audioDeltaCount)"
    }

    public static func bargeInDecision(
        hasPendingPlayback: Bool,
        alreadyBarged: Bool,
        playingResponseID: String?,
        interruptTargetID: String?,
        currentResponseID: String?,
        createdCountAtLatch: Int,
        createdCountNow: Int
    ) -> BargeInDecision {
        guard hasPendingPlayback, !alreadyBarged else {
            return BargeInDecision(cancelResponseID: nil, dropLocal: false)
        }
        if shouldKeepInterruptAnswerOnPlayer(
            playingResponseID: playingResponseID,
            interruptTargetID: interruptTargetID,
            currentResponseID: currentResponseID,
            createdCountAtLatch: createdCountAtLatch,
            createdCountNow: createdCountNow
        ) {
            return BargeInDecision(cancelResponseID: nil, dropLocal: false)
        }
        return BargeInDecision(cancelResponseID: nil, dropLocal: true)
    }

    /// Client-side latch when Grok omits `response_id` on PCM.
    public static func playbackEpochLatch(_ epoch: Int) -> String {
        "playback-epoch-\(epoch)"
    }

    /// First answer is on the player. Copy `response.created` onto the
    /// schedule latch. If that id is also empty, use the playback epoch.
    /// Never return nil — leftover inject needs this id.
    /// A real first-answer latch must stay. Interrupt `response.created`
    /// after drain-before-transcript must not overwrite it or leftover
    /// inject captures the interrupt id (aa62555 leftover paper).
    public static func latchWhenFirstAnswerPlaying(
        existingScheduledID: String?,
        createdID: String?,
        playbackEpoch: Int
    ) -> String {
        if let existing = nonemptyID(existingScheduledID), !isPlaybackEpochLatch(existing) {
            return existing
        }
        return nonemptyID(createdID)
            ?? nonemptyID(existingScheduledID)
            ?? playbackEpochLatch(playbackEpoch)
    }

    public static func isPlaybackEpochLatch(_ id: String?) -> Bool {
        guard let id = nonemptyID(id) else { return false }
        return id.hasPrefix("playback-epoch-")
    }

    /// No-id leftover leftover fills lastCreated. Do not overwrite a
    /// real first-answer latch with that fill. JSON `response_id` may
    /// replace it — that is the interrupt answer, not leftover leftover.
    public static func shouldOverwriteScheduledLatch(
        existingScheduledID: String?,
        taggedID: String?,
        deltaResponseID: String?,
        cancelledResponseID: String?
    ) -> Bool {
        guard let tagged = nonemptyID(taggedID) else { return false }
        if let cancelled = nonemptyID(cancelledResponseID), tagged == cancelled {
            return false
        }
        let existing = nonemptyID(existingScheduledID)
        if existing == nil { return true }
        if nonemptyID(deltaResponseID) != nil { return true }
        if existing == tagged { return true }
        return isPlaybackEpochLatch(existing)
    }

    /// Leftover reject arms only after an answer actually scheduled
    /// on the player. `lastCreated` alone is the first answer arriving
    /// — claimLocal / speech_started at pending 0 must not stamp that
    /// as cancelled or the first PCM is eaten.
    /// pending > 0: arm (and drop). pending 0 + lastScheduled/playing:
    /// arm leftover, nothing to drop. pending 0 + only lastCreated:
    /// do not arm.
    public static func shouldArmCommandBargeLatch(
        alreadyBarged: Bool,
        hasPendingPlayback: Bool,
        lastScheduledResponseID: String?,
        playingResponseID: String?
    ) -> Bool {
        guard !alreadyBarged else { return false }
        if hasPendingPlayback { return true }
        return nonemptyID(lastScheduledResponseID) != nil
            || nonemptyID(playingResponseID) != nil
    }

    /// Any listen-loop player schedule must leave lastScheduled set.
    /// Write when the latch is empty (binary/JSON `nil != nil` skipped
    /// noteScheduled, or write→player). After barge, do not overwrite
    /// a latch that already names the cancelled first answer.
    public static func shouldWriteScheduledLatchOnPlay(
        existingScheduledID: String?,
        bargeConsumed: Bool
    ) -> Bool {
        nonemptyID(existingScheduledID) == nil || !bargeConsumed
    }

    /// lastScheduled means an answer actually hit the player.
    /// First-answer `response.done` is the leftover window — keep
    /// the id so command barge after drain can arm leftover.
    /// Only a different id in `noteScheduledResponse` (or teardown)
    /// replaces it.
    public static func keepScheduledLatchAfterResponseDone(
        existingScheduledID: String?
    ) -> String? {
        nonemptyID(existingScheduledID)
    }

    /// First-answer id that barge dropped. Leftover deltas with this
    /// id must not raise pending after `interruptPlayback`.
    /// `lastCreated` is the first `response.created` when Grok PCM
    /// omitted `response_id` — scheduled/playing can stay nil.
    public static func cancelledPlaybackResponseID(
        interruptTargetID: String?,
        lastScheduledResponseID: String?,
        playingResponseID: String?,
        lastCreatedResponseID: String? = nil
    ) -> String? {
        nonemptyID(interruptTargetID)
            ?? nonemptyID(lastScheduledResponseID)
            ?? nonemptyID(playingResponseID)
            ?? nonemptyID(lastCreatedResponseID)
    }

    /// Tag a scheduled buffer when the delta omitted `response_id`.
    public static func scheduledResponseID(
        deltaResponseID: String?,
        createdAwaitingAudioID: String?,
        lastCreatedResponseID: String?
    ) -> String? {
        nonemptyID(deltaResponseID)
            ?? nonemptyID(createdAwaitingAudioID)
            ?? nonemptyID(lastCreatedResponseID)
    }

    /// Newer created after barge. Not the cancelled first answer.
    public static func interruptAnswerID(
        createdAwaitingAudioID: String?,
        lastCreatedResponseID: String?,
        cancelledResponseID: String?
    ) -> String? {
        let cancelled = nonemptyID(cancelledResponseID)
        if let awaiting = nonemptyID(createdAwaitingAudioID), awaiting != cancelled {
            return awaiting
        }
        if let created = nonemptyID(lastCreatedResponseID), created != cancelled {
            return created
        }
        return nil
    }

    /// First-answer `response.done` after barge sees pending 0
    /// (`interruptPlayback` just zeroed the player). That done is not
    /// the interrupt answer. Keep the cancelled latch until a
    /// *different* id actually scheduled as the interrupt answer.
    /// A done that still names the cancelled first answer must not
    /// clear the leftover-inject id.
    public static func shouldResetBargeAfterResponseDone(
        bargeConsumed: Bool,
        interruptAnswerScheduled: Bool,
        lastScheduledResponseID: String?,
        cancelledResponseID: String?,
        doneResponseID: String? = nil
    ) -> Bool {
        guard bargeConsumed, interruptAnswerScheduled else { return false }
        let scheduled = nonemptyID(lastScheduledResponseID)
        let cancelled = nonemptyID(cancelledResponseID)
        let done = nonemptyID(doneResponseID)
        guard let scheduled else { return false }
        if let cancelled, scheduled == cancelled { return false }
        if let done, let cancelled, done == cancelled { return false }
        return true
    }

    /// After barge, reject leftover that carries the cancelled
    /// first-answer id. A nil latch or a delta without `response_id`
    /// must still schedule — that is R2. Do not eat the interrupt answer.
    /// Command barge `interruptResponse` may lag drain (Grok
    /// transcribes after pending is 0). Leftover of lastScheduled
    /// after drain must still reject — 1488 can pass on lastScheduled
    /// while cancelled/bargeConsumed are still unset.
    public static func shouldScheduleAfterBarge(
        bargeConsumed: Bool,
        deltaResponseID: String?,
        cancelledResponseID: String?,
        interruptAnswerID: String? = nil,
        playingResponseID: String? = nil,
        lastScheduledResponseID: String? = nil,
        hasPendingPlayback: Bool = true
    ) -> Bool {
        _ = interruptAnswerID
        _ = playingResponseID
        let delta = nonemptyID(deltaResponseID)
        let cancelled = nonemptyID(cancelledResponseID)
        let scheduled = nonemptyID(lastScheduledResponseID)
        if let delta, let cancelled, delta == cancelled {
            return false
        }
        if !hasPendingPlayback, let delta, let scheduled, delta == scheduled {
            return false
        }
        _ = bargeConsumed
        return true
    }

    /// The interrupt created already scheduled. Dropping local wipes
    /// it — leftover created, pending 0.
    public static func shouldKeepInterruptAnswerOnPlayer(
        playingResponseID: String?,
        interruptTargetID: String?,
        currentResponseID: String?,
        createdCountAtLatch: Int,
        createdCountNow: Int
    ) -> Bool {
        let playing = nonemptyID(playingResponseID)
        let current = nonemptyID(currentResponseID)
        let target = nonemptyID(interruptTargetID)
        guard createdCountNow > createdCountAtLatch, let playing, let current else {
            return false
        }
        return playing == current && playing != target
    }

    /// Cancel only the answer that was on the player when barge-in
    /// started. If a newer `response.created` already exists, do not
    /// cancel that id — even when the latch was overwritten to it.
    public static func responseIDToCancelOnBarge(
        interruptTargetID: String?,
        playingResponseID: String?,
        currentResponseID: String?,
        createdCountAtLatch: Int,
        createdCountNow: Int
    ) -> String? {
        let target = nonemptyID(interruptTargetID)
        let playing = nonemptyID(playingResponseID)
        let current = nonemptyID(currentResponseID)
        let newerCreated = createdCountNow > createdCountAtLatch
        if newerCreated {
            return nil
        }
        if let target {
            if let current, target == current {
                return nil
            }
            return target
        }
        return playing
    }

    public static func bargeInPlayback(
        hasPendingPlayback: Bool,
        playingResponseID: String?,
        interruptTargetID: String?,
        currentResponseID: String? = nil,
        createdCountAtLatch: Int = 0,
        createdCountNow: Int = 0,
        alreadyBarged: Bool = false
    ) -> BargeInPlayback {
        let decision = bargeInDecision(
            hasPendingPlayback: hasPendingPlayback,
            alreadyBarged: alreadyBarged,
            playingResponseID: playingResponseID,
            interruptTargetID: interruptTargetID,
            currentResponseID: currentResponseID,
            createdCountAtLatch: createdCountAtLatch,
            createdCountNow: createdCountNow
        )
        if !hasPendingPlayback || alreadyBarged || !decision.dropLocal {
            return .none
        }
        if let id = decision.cancelResponseID {
            return .cancel(responseID: id)
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

    /// Live Talk (socket up): Eve's VAD turn is the mouth.
    /// Do not stack a verbatim `response.create`. ClientVoiceSpeech
    /// stays for a down socket (typed / offline).
    public static func shouldSpeakViaRealtime(
        usesLiveLoop: Bool,
        isConnected: Bool,
        userWantsVoiceOff: Bool
    ) -> Bool {
        usesLiveLoop && isConnected && !userWantsVoiceOff
    }

    /// Live VAD already created one response. A second create is two mouths.
    public static func shouldSendVerbatimCreate(liveVADTurn: Bool) -> Bool {
        !liveVADTurn
    }

    /// 12:54 / 3:27 live-Grok leak. Eve paraphrased routing-narration.
    /// Detector only — not a mute, not a transcript scrub.
    public static func isLeftoverDeskRoutingReply(_ raw: String) -> Bool {
        let lower = raw.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
        if lower.contains("app will take") { return true }
        if lower.contains("let the app handle") { return true }
        if raw.hasPrefix(" "), isLeftoverDeskRoutingReply(
            raw.trimmingCharacters(in: .whitespacesAndNewlines)
        ) {
            return true
        }
        return false
    }

    /// Connected presence must not teach stay-silent / app-owns routing.
    public static func teachesLeftoverDeskRouting(_ instructions: String) -> Bool {
        let lower = instructions.lowercased()
            .replacingOccurrences(of: "’", with: "'")
        if lower.contains("stay silent") { return true }
        if lower.contains("let the app handle") { return true }
        if lower.contains("the ios app owns") { return true }
        if lower.contains("the client owns those turns") { return true }
        if lower.contains("the client handles all gmail") { return true }
        if lower.contains("the client interrupts you") { return true }
        return false
    }

    public static func verbatimSpeakInstructions(text: String) -> String {
        """
        Speak the SPEAK_VERBATIM block word-for-word. No other words. No greeting. No paraphrase.
        After you finish, do not add more.

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
            return .responseCreated(id: responseID(in: json) ?? "")
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
