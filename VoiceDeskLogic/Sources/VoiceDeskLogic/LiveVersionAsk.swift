import Foundation

/// Production first-ask version path. AppModel.handleLiveUser and
/// AppModel.speakDeskReply call these same functions. Eve PCM is
/// `LiveVADPlayerKeep.shouldPlayBargeAudio` — the body
/// GrokVoiceService.shouldPlayBargeAudio wraps. Not flash-ready.
public struct LiveVersionAsk: Equatable, Sendable {
    public var identity: BuildIdentity
    public var liveVADTurn: Bool
    public var lastUserUtterance: String
    public var lastSpokenDeskReply: String?
    public var dropAssistantOutput: Bool
    public var clientTTSInFlight: Bool
    public var identityPCM: String?
    public var assistantReply: String
    public var voicePath: String
    public var routingNotes: [String]

    public init(
        identity: BuildIdentity,
        liveVADTurn: Bool,
        lastUserUtterance: String = "",
        lastSpokenDeskReply: String? = nil,
        dropAssistantOutput: Bool = false,
        clientTTSInFlight: Bool = false,
        identityPCM: String? = nil,
        assistantReply: String = "",
        voicePath: String = "Eve realtime",
        routingNotes: [String] = []
    ) {
        self.identity = identity
        self.liveVADTurn = liveVADTurn
        self.lastUserUtterance = lastUserUtterance
        self.lastSpokenDeskReply = lastSpokenDeskReply
        self.dropAssistantOutput = dropAssistantOutput
        self.clientTTSInFlight = clientTTSInFlight
        self.identityPCM = identityPCM
        self.assistantReply = assistantReply
        self.voicePath = voicePath
        self.routingNotes = routingNotes
    }

    public var spokenIdentityLine: String {
        ConversationPresence.spokenIdentityLine(
            for: lastUserUtterance,
            identity: identity
        )
    }

    public var wroteIdentityPCM: Bool {
        !(identityPCM?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    /// AppModel.handleLiveUser version branch. `true` means claimLocal
    /// — AppModel copies that to GrokVoiceService.suppressAssistantOutput.
    @discardableResult
    public mutating func handleLiveUser(_ raw: String, itemID: String? = nil) -> Bool {
        _ = itemID
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard ConversationPresence.wantsVersionAsk(text) else { return false }
        lastUserUtterance = text
        dropAssistantOutput = true
        let line = ConversationPresence.spokenIdentityLine(for: text, identity: identity)
        assistantReply = line
        routingNotes = ["local build identity", identity.dogfoodLine]
        voicePath = "Eve realtime"
        return true
    }

    /// AppModel.speakDeskReply. Live VAD writes the identity line only.
    @discardableResult
    public mutating func speakDeskReply(_ text: String) -> Bool {
        guard let spoken = DeskReplySpeech.textToSpeak(text, lastSpoken: lastSpokenDeskReply) else {
            return false
        }
        if liveVADTurn {
            let identityLine = ConversationPresence.spokenIdentityLine(
                for: lastUserUtterance,
                identity: identity
            )
            if !LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
                liveVADTurn: true,
                spoken: spoken,
                identityLine: identityLine
            ) {
                return false
            }
        }
        lastSpokenDeskReply = spoken
        clientTTSInFlight = true
        identityPCM = spoken
        return true
    }
}
