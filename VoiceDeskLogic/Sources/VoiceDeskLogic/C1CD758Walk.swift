import Foundation

/// Last six records of the c1cd758 iPhone walk (16:45:39–16:48:25Z).
/// File: `/workspace/voicedesk-c1cd758.jsonl` when present; else this bake.
/// Earlier lines in that file are older dogfood — not this walk.
public enum C1CD758Walk {
    public static let jsonlPath = "/workspace/voicedesk-c1cd758.jsonl"
    public static let versionAsk = "Hey, good morning. What version are we on?"
    public static let versionIdentityNote = "eve speaks identity"
    public static let versionDogfoodNote = "0.1.0 build 6 sha c1cd758"
    public static let spokenIdentity83a5c6a = "VoiceDesk point 1, build 6."

    public static var lastSix: [VoiceInteractionEntry] {
        if let fromDisk = loadLastSix(from: jsonlPath), fromDisk.count == 6 {
            return fromDisk
        }
        return bakedLastSix
    }

    public static func loadLastSix(from path: String) -> [VoiceInteractionEntry]? {
        guard FileManager.default.fileExists(atPath: path),
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count >= 6 else { return nil }
        let tail = lines.suffix(6)
        var decoded: [VoiceInteractionEntry] = []
        let decoder = VoiceCloudLogCodec.jsonDecoder()
        for line in tail {
            let data = Data(line.utf8)
            if let entry = try? decoder.decode(VoiceInteractionEntry.self, from: data) {
                decoded.append(entry)
                continue
            }
            if let envelope = try? decoder.decode(VoiceCloudLogEnvelope.self, from: data) {
                decoded.append(envelope.entry)
            }
        }
        return decoded.count == 6 ? decoded : nil
    }

    public static func versionTurn(in records: [VoiceInteractionEntry] = lastSix) -> VoiceInteractionEntry? {
        records.first {
            $0.intent != ListenResumeLog.intent
                && ($0.userTranscript.localizedCaseInsensitiveContains("what version")
                    || $0.routingNotes.contains { $0.contains(versionIdentityNote) })
        }
    }

    public static func isEmptyEveSpeaksIdentity(_ entry: VoiceInteractionEntry) -> Bool {
        LiveVADPlayerKeep.isEmptyEveSpeaksIdentityLie(
            routingNotes: entry.routingNotes,
            assistantReply: entry.assistantReply,
            wrotePlayerPCM: false
        )
    }

    public static let bakedLastSix: [VoiceInteractionEntry] = [
        ListenResumeLog.entry(note: "audio.start; VP while stopped; 48k; running=true"),
        VoiceInteractionEntry(
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
            assistantReply: "",
            voicePath: "Eve realtime"
        ),
        VoiceInteractionEntry(
            source: "live voice",
            userTranscript: "Can you hear me?",
            intent: "general",
            routingNotes: [],
            cardsAttached: [],
            assistantReply: "Yeah, I can hear you loud and clear. What's on your mind?",
            voicePath: "Eve realtime"
        ),
        VoiceInteractionEntry(
            source: "live voice",
            userTranscript: "What?",
            intent: "general",
            routingNotes: [],
            cardsAttached: [],
            assistantReply: "Sorry, didn't catch that. Want me to repeat that?",
            voicePath: "Eve realtime"
        ),
        VoiceInteractionEntry(
            source: "live voice",
            userTranscript: "Yeah.",
            intent: "general",
            routingNotes: [],
            cardsAttached: [],
            assistantReply: "Got it, I'll flag anything that comes in from him…",
            voicePath: "Eve realtime"
        ),
        ListenResumeLog.entry(
            note: "session close code=1000 reason= state=idle stayLive=false stayIdle"
        )
    ]
}
