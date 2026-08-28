import Foundation

/// Linux/Mac voice tape catalog. Elon mints WAV on a Mac (`say` + `afconvert`)
/// and replays PCM16 24 kHz through the same Grok realtime loop as the phone.
/// The gate is EchoBargeIn — not a second Python copy.
public enum VoiceTape: Sendable {
    public struct Item: Equatable, Sendable, Codable {
        public var id: String
        public var say: String
        public var intent: String
        public var allowedIntents: [String]
        public var context: String

        public init(
            id: String,
            say: String,
            intent: String,
            allowedIntents: [String] = [],
            context: String = "connected"
        ) {
            self.id = id
            self.say = say
            self.intent = intent
            self.allowedIntents = allowedIntents.isEmpty ? [intent] : allowedIntents
            self.context = context
        }
    }

    public struct Decision: Equatable, Sendable, Codable {
        public var accepted: Bool
        public var intent: String
        public var dropped: Bool
        public var text: String

        public init(accepted: Bool, intent: String, dropped: Bool, text: String) {
            self.accepted = accepted
            self.intent = intent
            self.dropped = dropped
            self.text = text
        }

        public func matches(_ item: Item) -> Bool {
            accepted && !dropped && item.allowedIntents.contains(intent)
        }
    }

    public static let sampleRate = GrokRealtime.sampleRate
    public static let realtimeHost = GrokRealtime.realtimeHost

    /// No key / --dry-run must not fail CI. Live socket is Elon-on-Mac only.
    public static func shouldSkipLive(hasAPIKey: Bool, dryRun: Bool = false) -> Bool {
        dryRun || !hasAPIKey
    }

    /// Latest-emails race first — 2150783. Then version / SHA / calendar / named.
    public static let catalog: [Item] = [
        Item(id: "show-my-latest-emails", say: "show my latest emails", intent: "inbox-overview"),
        Item(id: "my-latest-emails", say: "my latest emails", intent: "inbox-overview"),
        Item(
            id: "okay-show-me-my-latest-emails",
            say: "okay show me my latest emails",
            intent: "inbox-overview"
        ),
        Item(id: "what-version-are-we-on", say: "what version are we on", intent: "version"),
        Item(id: "what-sha-is-this", say: "what SHA is this", intent: "version"),
        Item(
            id: "calendar-for-the-week",
            say: "what's on my calendar for the week",
            intent: "calendar",
            context: "massimoCalendar"
        ),
        Item(
            id: "latest-email-from-lauren",
            say: "latest email from Lauren",
            intent: "desk-person",
            allowedIntents: ["desk-person", "desk-thread"],
            context: "greenacreFirst"
        ),
        Item(
            id: "email-from-katherine",
            say: "email from Katherine",
            intent: "desk-person",
            allowedIntents: ["desk-person", "desk-thread"],
            context: "massimoCalendar"
        )
    ]

    public static let secondAskPair = ("show-my-latest-emails", "my-latest-emails")

    /// Composed live loop: talk, barge-in command, talk-again after the
    /// interrupt answer. Catalog [0], [1], [2].
    public static let composedLoopTriple = (
        secondAskPair.0,
        secondAskPair.1,
        "okay-show-me-my-latest-emails"
    )

    public static func context(named: String) -> DeskContext {
        switch named {
        case "massimoCalendar":
            return VoiceRegressionDesk.massimoCalendar
        case "greenacreFirst":
            return VoiceRegressionDesk.greenacreFirst
        default:
            return VoiceRegressionDesk.connected
        }
    }

    /// Same phone path: empty lastSpokenLine + Grok `.speaking` → EchoBargeIn.
    public static func evaluate(
        text: String,
        voiceState: VoiceState = .speaking,
        lastSpokenLine: String = "",
        contextName: String = "connected"
    ) -> Decision {
        var gate = EchoTranscriptGate()
        let trimmedLine = lastSpokenLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLine.isEmpty {
            gate.beginSpeaking(trimmedLine)
            gate.finishSpeaking()
        }
        let accepted = EchoBargeIn.acceptedUserTranscript(
            text,
            gate: gate,
            voiceState: voiceState
        )
        let decision = gate.decide(text, voiceState: voiceState, context: context(named: contextName))
        return Decision(
            accepted: accepted != nil,
            intent: decision.intent,
            dropped: decision.isDropped || accepted == nil,
            text: accepted ?? ""
        )
    }

    public static func evaluate(_ item: Item, spokenAs: String? = nil) -> Decision {
        evaluate(
            text: spokenAs ?? item.say,
            voiceState: .speaking,
            lastSpokenLine: "",
            contextName: item.context
        )
    }

    public static func sessionUpdateObject(contextName: String = "connected") -> [String: Any] {
        GrokRealtime.sessionUpdateObject(
            instructions: GrokRealtime.presenceInstructions(for: context(named: contextName))
        )
    }

    public static func stayLiveAfterClose1000(
        userWantsVoiceOff: Bool = false,
        audioStarted: Bool = true
    ) -> ListenResumeDecision {
        let stay = ListenResumePolicy.sessionShouldStayLive(
            userWantsVoiceOff: userWantsVoiceOff,
            liveSessionArmed: false,
            audioStarted: audioStarted
        )
        return ListenResumePolicy.afterSocketClose(
            userWantsVoiceOff: userWantsVoiceOff,
            sessionShouldStayLive: stay,
            closeCode: 1000,
            voiceState: .idle
        )
    }

    /// 24 kHz little-endian PCM16 mono WAV. Same as `afconvert -d LEI16@24000 -c 1`.
    public static func pcm16WAV(fromPCM16LE pcm: Data, sampleRate: Int = sampleRate) -> Data {
        var data = Data()
        let channels: UInt16 = 1
        let bits: UInt16 = 16
        let rate = UInt32(sampleRate)
        let byteRate = rate * UInt32(channels) * UInt32(bits / 8)
        let blockAlign = channels * (bits / 8)
        let dataSize = UInt32(pcm.count)
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func le16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func le32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        ascii("RIFF")
        le32(36 + dataSize)
        ascii("WAVE")
        ascii("fmt ")
        le32(16)
        le16(1)
        le16(channels)
        le32(rate)
        le32(byteRate)
        le16(blockAlign)
        le16(bits)
        ascii("data")
        le32(dataSize)
        data.append(pcm)
        return data
    }

    public static func pcm16LE(fromWAV wav: Data) -> Data? {
        guard wav.count >= 44,
              wav.starts(with: Data("RIFF".utf8)),
              wav[8..<12] == Data("WAVE".utf8)
        else { return nil }
        var offset = 12
        while offset + 8 <= wav.count {
            let id = String(data: wav[offset..<offset + 4], encoding: .ascii) ?? ""
            let size = Int(wav[offset + 4])
                | Int(wav[offset + 5]) << 8
                | Int(wav[offset + 6]) << 16
                | Int(wav[offset + 7]) << 24
            offset += 8
            if id == "data" {
                let end = min(offset + size, wav.count)
                return Data(wav[offset..<end])
            }
            offset += size
        }
        return nil
    }
}
