import Foundation

/// a2727b1 iPhone walk 17:20:50–17:23:26Z (jsonl L400–L407).
/// File: `/workspace/voicedesk-a2727b1-walk.jsonl` when present; else bake.
/// First ask is L400–L402. L403–L407 are parked (Sue / Murray) — not this slice.
public enum A2727B1Walk {
    public static let jsonlPath = "/workspace/voicedesk-a2727b1-walk.jsonl"
    public static let versionAsk = "Good morning. What version are we on?"
    public static let spokenIdentity = "VoiceDesk point 1, build 6."
    public static let versionIdentityNote = "local build identity"
    public static let versionDogfoodNote = "0.1.0 build 6 sha a2727b1"
    public static let eveRealtime = "Eve realtime"
    public static let drainNote =
        "after desk tts drain listenArmed=true stayLive=true reconnect startAgain=false state=listening"
    /// L400 walk line. Not the c1cd758 “audio.start; VP while stopped” paraphrase.
    public static let audioStartNote = "audio.start VP-while-stopped 48k running=true"

    public static var window: [VoiceInteractionEntry] {
        if let fromDisk = loadWindow(from: jsonlPath), fromDisk.count >= 3 {
            return fromDisk
        }
        return bakedFirstAsk
    }

    public static func loadWindow(from path: String) -> [VoiceInteractionEntry]? {
        guard FileManager.default.fileExists(atPath: path),
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let raw: ArraySlice<String>
        if lines.count >= 407 {
            raw = lines[399..<min(407, lines.count)]
        } else {
            raw = ArraySlice(lines)
        }
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
        return decoded.count >= 3 ? decoded : nil
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

    /// Desk identity write + Eve realtime on the same version turn.
    public static func firstAskIsDualMouth(in records: [VoiceInteractionEntry] = window) -> Bool {
        guard let version = versionTurn(in: records) else { return false }
        let drainNotes = drain(in: records)?.routingNotes ?? []
        return LiveTalkMouth.versionTurnIsDualMouth(
            versionNotes: version.routingNotes,
            assistantReply: version.assistantReply,
            voicePath: version.voicePath,
            drainNotes: drainNotes
        )
    }

    public static func firstAskMouth(in records: [VoiceInteractionEntry] = window) -> LiveTalkMouth {
        let version = versionTurn(in: records)
        let wroteIdentity = version?.routingNotes.contains(where: { $0.contains(versionIdentityNote) }) == true
            && !(version?.assistantReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return LiveTalkMouth(
            afterDeskTTSDrain: drain(in: records) != nil,
            eveVoicePath: version?.voicePath.localizedCaseInsensitiveContains(eveRealtime) == true,
            skippedGlanceStubFirstAudio: false,
            clientVoiceSpeechWrite: wroteIdentity,
            liveVADResponse: true,
            sentVerbatimCreate: false
        )
    }

    /// L400–L402 only. Parked L403 Sue / L404 duplicate cards / L405+L407
    /// Murray stale version line / L406 1000 stayIdle — not this slice.
    public static let bakedFirstAsk: [VoiceInteractionEntry] = [
        {
            var entry = ListenResumeLog.entry(note: audioStartNote)
            entry.timestamp = ts("2026-08-27T17:20:50Z")
            return entry
        }(),
        {
            var entry = ListenResumeLog.entry(note: drainNote)
            entry.timestamp = ts("2026-08-27T17:21:58Z")
            return entry
        }(),
        VoiceInteractionEntry(
            timestamp: ts("2026-08-27T17:21:58Z"),
            source: "live voice",
            userTranscript: versionAsk,
            intent: "version",
            sticky: .cleared,
            routingNotes: [
                "sticky cleared",
                "synced cache / list",
                versionIdentityNote,
                versionDogfoodNote
            ],
            cardsAttached: [],
            assistantReply: spokenIdentity,
            voicePath: eveRealtime
        )
    ]

    private static func ts(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso) ?? Date()
    }
}
