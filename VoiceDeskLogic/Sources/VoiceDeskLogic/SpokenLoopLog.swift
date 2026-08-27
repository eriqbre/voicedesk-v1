import Foundation

/// Structured spoken-loop events. Production AppModel / GrokVoiceService
/// emit these so two-mouth, empty firstAudio, and DidClose stayIdle are
/// grepable without a user report. Privacy-safe: intent only, no transcript
/// or email body.
public enum SpokenLoopLog: Sendable {
    public static let source = ListenResumeLog.source
    public static let intent = "spoken-loop"

    public static let turnStartEvent = "spoken_loop.turn.start"
    public static let mouthEvent = "spoken_loop.mouth"
    public static let firstAudioEvent = "spoken_loop.first_audio"
    public static let deskTTSDrainEvent = "spoken_loop.desk_tts.drain"
    public static let sessionCloseEvent = "spoken_loop.session.close"
    public static let liveSpeakStartEvent = "live.speak.start"
    public static let liveSpeakSentEvent = "live.speak.sent"
    public static let liveSpeakDoneEvent = "live.speak.done"
    public static let liveSpeakSkippedEvent = "live.speak.skipped"

    public enum Mouth: String, Equatable, Sendable {
        case desk
        case eve
    }

    public enum FirstAudio: String, Equatable, Sendable {
        case present
        case absent
    }

    public private(set) static var currentSessionID = UUID().uuidString

    @discardableResult
    public static func beginSession() -> String {
        currentSessionID = UUID().uuidString
        return currentSessionID
    }

    public static func turnStart(sessionID: String, intent: String) -> VoiceInteractionEntry {
        entry(fields: [
            "event": turnStartEvent,
            "session": sessionID,
            "intent": sanitizedIntent(intent)
        ])
    }

    public static func mouth(sessionID: String, mouth: Mouth) -> VoiceInteractionEntry {
        entry(fields: [
            "event": mouthEvent,
            "session": sessionID,
            "mouth": mouth.rawValue
        ])
    }

    public static func firstAudio(sessionID: String, status: FirstAudio) -> VoiceInteractionEntry {
        entry(fields: [
            "event": firstAudioEvent,
            "session": sessionID,
            "first_audio": status.rawValue
        ])
    }

    public static func deskTTSDrain(
        sessionID: String,
        listenArmed: Bool,
        stayLive: Bool,
        state: String
    ) -> VoiceInteractionEntry {
        entry(fields: [
            "event": deskTTSDrainEvent,
            "session": sessionID,
            "listenArmed": bool(listenArmed),
            "stayLive": bool(stayLive),
            "state": state
        ])
    }

    public static func liveSpeakStart(sessionID: String) -> VoiceInteractionEntry {
        entry(fields: [
            "event": liveSpeakStartEvent,
            "session": sessionID
        ])
    }

    public static func liveSpeakSent(sessionID: String, responseID: String?) -> VoiceInteractionEntry {
        var fields = [
            "event": liveSpeakSentEvent,
            "session": sessionID
        ]
        if let responseID, !responseID.isEmpty {
            fields["response"] = responseID
        }
        return entry(fields: fields)
    }

    public static func liveSpeakDone(sessionID: String, responseID: String?) -> VoiceInteractionEntry {
        var fields = [
            "event": liveSpeakDoneEvent,
            "session": sessionID
        ]
        if let responseID, !responseID.isEmpty {
            fields["response"] = responseID
        }
        return entry(fields: fields)
    }

    public static func liveSpeakSkipped(sessionID: String, reason: String) -> VoiceInteractionEntry {
        entry(fields: [
            "event": liveSpeakSkippedEvent,
            "session": sessionID,
            "reason": reason
        ])
    }

    public static func sessionClose(
        sessionID: String,
        code: Int,
        stayLive: Bool,
        stayIdle: Bool
    ) -> VoiceInteractionEntry {
        entry(fields: [
            "event": sessionCloseEvent,
            "session": sessionID,
            "code": String(code),
            "stayLive": bool(stayLive),
            "stayIdle": bool(stayIdle)
        ])
    }

    /// Live VAD Eve mouth: present unless she is cut before PCM or desk
    /// also wrote (two-mouth / empty Eve firstAudio).
    public static func firstAudioAfterSpokenReply(
        wroteDeskPCM: Bool,
        evePlays: Bool,
        interruptedWhilePending: Bool
    ) -> FirstAudio {
        if interruptedWhilePending { return .absent }
        if wroteDeskPCM, evePlays { return .absent }
        if evePlays || wroteDeskPCM { return .present }
        return .absent
    }

    public static func mouths(in records: [VoiceInteractionEntry]) -> [Mouth] {
        records.compactMap { rec in
            guard parse(rec)["event"] == mouthEvent,
                  let raw = parse(rec)["mouth"]
            else { return nil }
            return Mouth(rawValue: raw)
        }
    }

    public static func firstAudioStatus(in records: [VoiceInteractionEntry]) -> FirstAudio? {
        records.reversed().compactMap { rec -> FirstAudio? in
            let fields = parse(rec)
            guard fields["event"] == firstAudioEvent,
                  let raw = fields["first_audio"]
            else { return nil }
            return FirstAudio(rawValue: raw)
        }.first
    }

    /// Desk drain + Eve stayLive + first_audio absent. a2727b1 version cut.
    public static func isVoiceCut(_ records: [VoiceInteractionEntry]) -> Bool {
        let drained = records.contains { parse($0)["event"] == deskTTSDrainEvent }
        let eve = mouths(in: records).contains(.eve)
        return drained && eve && firstAudioStatus(in: records) == .absent
    }

    public static func closeIsStayIdle(_ records: [VoiceInteractionEntry]) -> Bool {
        records.contains { rec in
            let fields = parse(rec)
            return fields["event"] == sessionCloseEvent
                && fields["stayIdle"] == "true"
                && fields["stayLive"] == "false"
        }
    }

    public static func parse(_ entry: VoiceInteractionEntry) -> [String: String] {
        parseNote(entry.routingNotes.first ?? "")
    }

    public static func parseNote(_ note: String) -> [String: String] {
        var fields: [String: String] = [:]
        for token in note.split(whereSeparator: \.isWhitespace) {
            let parts = token.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1])
        }
        return fields
    }

    public static func containsTranscriptOrBody(_ entry: VoiceInteractionEntry) -> Bool {
        if !entry.userTranscript.isEmpty || !entry.assistantReply.isEmpty { return true }
        let blob = entry.routingNotes.joined(separator: " ").lowercased()
        return blob.contains("what version")
            || blob.contains("rob clark")
            || blob.contains("subject:")
            || blob.contains("body=")
    }

    public static func note(fields: [String: String]) -> String {
        let order = ["event", "session", "intent", "mouth", "first_audio", "listenArmed", "stayLive", "state", "code", "stayIdle", "response", "reason"]
        var seen = Set<String>()
        var parts: [String] = []
        for key in order where fields[key] != nil {
            parts.append("\(key)=\(fields[key]!)")
            seen.insert(key)
        }
        for key in fields.keys.sorted() where !seen.contains(key) {
            parts.append("\(key)=\(fields[key]!)")
        }
        return parts.joined(separator: " ")
    }

    private static func entry(fields: [String: String]) -> VoiceInteractionEntry {
        ListenResumeLog.entry(note: note(fields: fields))
    }

    private static func sanitizedIntent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return "live" }
        if trimmed.contains(" ") { return "live" }
        return trimmed
    }

    private static func bool(_ value: Bool) -> String {
        value ? "true" : "false"
    }
}
