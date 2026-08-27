import Foundation

/// Production spoken-loop seam. AppModel.handleLiveUser and
/// AppModel.speakDeskReply call these same functions.
///
/// Live Talk: Eve is the mouth. handleLiveUser records a version ask;
/// it does not mute Eve. speakDeskReply refuses desk PCM on live VAD
/// (that write + Eve on the same turn is a2727b1 two-mouth). Offline /
/// typed still writes identity. Mute flags and unmute-after-drain
/// lived here and produced 8927c2d silence — they are gone.
public struct LiveVersionAsk: Equatable, Sendable {
    public var identity: BuildIdentity
    public var liveVADTurn: Bool
    public var lastUserUtterance: String
    public var lastSpokenDeskReply: String?
    public var identityPCM: String?
    public var assistantReply: String
    public var voicePath: String
    public var routingNotes: [String]

    public init(
        identity: BuildIdentity,
        liveVADTurn: Bool,
        lastUserUtterance: String = "",
        lastSpokenDeskReply: String? = nil,
        identityPCM: String? = nil,
        assistantReply: String = "",
        voicePath: String = "Eve realtime",
        routingNotes: [String] = []
    ) {
        self.identity = identity
        self.liveVADTurn = liveVADTurn
        self.lastUserUtterance = lastUserUtterance
        self.lastSpokenDeskReply = lastSpokenDeskReply
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

    /// AppModel.handleLiveUser version detect. Does not mute Eve.
    @discardableResult
    public mutating func handleLiveUser(_ raw: String, itemID: String? = nil) -> Bool {
        _ = itemID
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard ConversationPresence.wantsVersionAsk(text) else { return false }
        lastUserUtterance = text
        let line = ConversationPresence.spokenIdentityLine(for: text, identity: identity)
        assistantReply = line
        routingNotes = ["local build identity", identity.dogfoodLine]
        voicePath = "Eve realtime"
        return true
    }

    /// AppModel.speakDeskReply. Live VAD returns false so Eve stays
    /// the only mouth. Offline / typed writes identity PCM.
    @discardableResult
    public mutating func speakDeskReply(_ text: String) -> Bool {
        guard let spoken = DeskReplySpeech.textToSpeak(text, lastSpoken: lastSpokenDeskReply) else {
            return false
        }
        if !LiveVADPlayerKeep.shouldWriteLiveDeskLineToPlayer(
            liveVADTurn: liveVADTurn,
            spoken: spoken,
            identityLine: ConversationPresence.spokenIdentityLine(
                for: lastUserUtterance,
                identity: identity
            )
        ) {
            return false
        }
        lastSpokenDeskReply = spoken
        identityPCM = spoken
        return true
    }
}
