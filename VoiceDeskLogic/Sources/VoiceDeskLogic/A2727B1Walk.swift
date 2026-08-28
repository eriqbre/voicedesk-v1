import Foundation

/// a2727b1 restore-walk L417–L424, 19:01:20Z–19:04:52Z (3:01–3:05pm ET).
/// Phone SHA L421: 0.1.0 build 6 sha a2727b1
/// (full a2727b1d5ca498c16f3b22d0ca5c4d010c32242c).
/// File: `/workspace/voicedesk-a2727b1-walk.jsonl` when present; else bake.
/// Bake is only tokens in that window. No firstAudio / dropAssistantOutput /
/// clientTTSInFlight / unmute. L418/L419/L422 live-Grok text is not in
/// the facts — not invented. Sue/Murray/named-read are not this slice.
public enum A2727B1Walk {
    public static let jsonlPath = "/workspace/voicedesk-a2727b1-walk.jsonl"
    public static let fullSHA = "a2727b1d5ca498c16f3b22d0ca5c4d010c32242c"
    public static let versionAsk = "What version are we on?"
    public static let spokenIdentity = "VoiceDesk point 1, build 6."
    public static let versionIdentityNote = "local build identity"
    public static let versionDogfoodNote = "0.1.0 build 6 sha a2727b1"
    public static let eveRealtime = "Eve realtime"
    public static let lastUserAsk = "Can you read the one from Rob Clark?"
    public static let drainNote =
        "after desk tts drain listenArmed=true stayLive=true reconnect startAgain=false state=listening"
    public static let closeNote =
        "session close code=1000 reason= state=idle stayLive=false stayIdle"
    /// L417 token only. Exact VP/48k line is not in the restore-walk facts.
    public static let audioStartNote = "audio.start"

    public static var window: [VoiceInteractionEntry] {
        if let fromDisk = loadRestoreWindow(from: jsonlPath), matchesRestoreWalk(fromDisk) {
            return fromDisk
        }
        return bakedRestoreWalk
    }

    public static func loadRestoreWindow(from path: String) -> [VoiceInteractionEntry]? {
        guard FileManager.default.fileExists(atPath: path),
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let raw: ArraySlice<String>
        if lines.count >= 424 {
            raw = lines[416..<424]
        } else if lines.count >= 8 {
            raw = lines.suffix(8)
        } else {
            raw = ArraySlice(lines)
        }
        let decoded = decodeLines(raw)
        return decoded.isEmpty ? nil : decoded
    }

    public static func matchesRestoreWalk(_ records: [VoiceInteractionEntry]) -> Bool {
        guard let version = versionTurn(in: records) else { return false }
        return version.userTranscript == versionAsk
            && sessionClose(in: records) != nil
            && lastUserTurn(in: records) != nil
    }

    public static func audioStart(in records: [VoiceInteractionEntry] = window) -> VoiceInteractionEntry? {
        records.first {
            $0.intent == ListenResumeLog.intent
                && $0.routingNotes.contains(where: { $0.contains("audio.start") })
        }
    }

    public static func drain(in records: [VoiceInteractionEntry] = window) -> VoiceInteractionEntry? {
        records.first {
            $0.intent == ListenResumeLog.intent
                && $0.routingNotes.contains(where: { $0.contains("after desk tts drain") })
        }
    }

    public static func versionTurn(in records: [VoiceInteractionEntry] = window) -> VoiceInteractionEntry? {
        records.first {
            $0.intent != ListenResumeLog.intent
                && $0.userTranscript.localizedCaseInsensitiveContains("what version")
        }
    }

    public static func lastUserTurn(in records: [VoiceInteractionEntry] = window) -> VoiceInteractionEntry? {
        records.last {
            $0.intent != ListenResumeLog.intent && !$0.userTranscript.isEmpty
        }
    }

    public static func sessionClose(in records: [VoiceInteractionEntry] = window) -> VoiceInteractionEntry? {
        records.first {
            $0.intent == ListenResumeLog.intent
                && $0.routingNotes.contains(where: { $0.contains("session close code=1000") })
        }
    }

    /// L420 drain + L421 identity write + Eve stayLive. No eve-speaks-identity.
    public static func versionIsDualMouth(in records: [VoiceInteractionEntry] = window) -> Bool {
        guard let version = versionTurn(in: records) else { return false }
        let versionBlob = version.routingNotes.joined(separator: "\n")
        let drainBlob = (drain(in: records)?.routingNotes ?? []).joined(separator: "\n")
        let identityWrite = versionBlob.contains(versionIdentityNote)
            && version.assistantReply.localizedCaseInsensitiveContains("VoiceDesk point")
        let drained = drainBlob.contains("after desk tts drain")
            || versionBlob.contains("after desk tts drain")
        let eveRealtimePath = version.voicePath.localizedCaseInsensitiveContains(eveRealtime)
        let silentEveLie = versionBlob.contains("eve speaks identity")
        return identityWrite && drained && eveRealtimePath && !silentEveLie
    }

    /// jsonl has no firstAudio on the version turn. Desk drained. User heard Eve cut.
    public static func versionHasNoFirstAudioWhileDeskDrained(
        in records: [VoiceInteractionEntry] = window
    ) -> Bool {
        guard let version = versionTurn(in: records), drain(in: records) != nil else { return false }
        return !blob(records).localizedCaseInsensitiveContains("firstAudio")
            && !version.routingNotes.contains(where: { $0.localizedCaseInsensitiveContains("firstAudio") })
    }

    /// L424 after L423. No audio.start after the last user turn.
    public static func diedStayIdleAfterLastReply(
        in records: [VoiceInteractionEntry] = window
    ) -> Bool {
        guard let last = lastUserTurn(in: records),
              let close = sessionClose(in: records)
        else { return false }
        let notes = close.routingNotes.joined(separator: "\n")
        guard notes.contains("stayLive=false"), notes.contains("stayIdle") else { return false }
        return !hasAudioStart(after: last, in: records)
    }

    public static func hasAudioStart(
        after entry: VoiceInteractionEntry,
        in records: [VoiceInteractionEntry] = window
    ) -> Bool {
        guard let idx = records.firstIndex(where: { $0.id == entry.id }) else { return false }
        return records[(idx + 1)...].contains {
            $0.routingNotes.contains(where: { $0.contains("audio.start") })
        }
    }

    /// Tokens the restore-walk window does not have. Do not invent them.
    public static func mentionsMuteFlagTokens(in records: [VoiceInteractionEntry] = window) -> Bool {
        let text = blob(records)
        return text.localizedCaseInsensitiveContains("dropAssistantOutput")
            || text.localizedCaseInsensitiveContains("clientTTSInFlight")
            || text.localizedCaseInsensitiveContains("unmute")
    }

    /// L417, L420, L421, L423, L424 — hard facts only.
    public static let bakedRestoreWalk: [VoiceInteractionEntry] = [
        {
            var entry = ListenResumeLog.entry(note: audioStartNote)
            entry.timestamp = ts("2026-08-27T19:01:20Z")
            return entry
        }(),
        {
            var entry = ListenResumeLog.entry(note: drainNote)
            entry.timestamp = ts("2026-08-27T19:02:52Z")
            return entry
        }(),
        VoiceInteractionEntry(
            timestamp: ts("2026-08-27T19:02:52Z"),
            source: "live voice",
            userTranscript: versionAsk,
            intent: "version",
            routingNotes: [
                versionIdentityNote,
                versionDogfoodNote
            ],
            cardsAttached: [],
            assistantReply: spokenIdentity,
            voicePath: eveRealtime
        ),
        VoiceInteractionEntry(
            timestamp: ts("2026-08-27T19:04:44Z"),
            source: "live voice",
            userTranscript: lastUserAsk,
            intent: "general",
            routingNotes: [],
            cardsAttached: [],
            assistantReply: "",
            voicePath: eveRealtime
        ),
        {
            var entry = ListenResumeLog.entry(note: closeNote)
            entry.timestamp = ts("2026-08-27T19:04:52Z")
            return entry
        }()
    ]

    private static func blob(_ records: [VoiceInteractionEntry]) -> String {
        records.flatMap { rec in
            rec.routingNotes + [rec.userTranscript, rec.assistantReply, rec.intent, rec.voicePath]
        }.joined(separator: "\n")
    }

    private static func decodeLines(_ raw: ArraySlice<String>) -> [VoiceInteractionEntry] {
        var decoded: [VoiceInteractionEntry] = []
        let decoder = VoiceCloudLogCodec.jsonDecoder()
        for line in raw {
            let data = Data(line.utf8)
            if let entry = try? decoder.decode(VoiceInteractionEntry.self, from: data) {
                decoded.append(entry)
                continue
            }
            if let envelope = try? decoder.decode(VoiceCloudLogEnvelope.self, from: data) {
                decoded.append(envelope.entry)
            }
        }
        return decoded
    }

    private static func ts(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso) ?? Date()
    }
}
