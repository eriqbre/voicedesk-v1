import Foundation

/// Production first-ask version path. AppModel.handleLiveUser and
/// AppModel.speakDeskReply call these same functions. Linux cannot
/// instantiate iOS AppModel; this is the reachable seam.
///
/// a2727b1: handleLiveUser claimLocal + speakDeskReply wrote identity
/// while Eve realtime deltas still scheduled (shouldPlayBargeAudio
/// had no mute). L402: local build identity + “VoiceDesk point 1,
/// build 6.” + voicePath Eve realtime.
public struct LiveVersionAsk: Equatable, Sendable {
    public var identity: BuildIdentity
    public var liveVADTurn: Bool
    public var lastUserUtterance: String
    public var lastSpokenDeskReply: String?
    public var dropAssistantOutput: Bool
    public var clientTTSInFlight: Bool
    public var identityPCM: String?
    public var eveRealtimeChunks: Int
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
        eveRealtimeChunks: Int = 0,
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
        self.eveRealtimeChunks = eveRealtimeChunks
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

    public var eveRealtimeReachedPlayer: Bool { eveRealtimeChunks > 0 }

    public var isDualMouth: Bool { wroteIdentityPCM && eveRealtimeReachedPlayer }

    /// AppModel.handleLiveUser version branch: claimLocal only.
    /// speakDeskReply is a separate call, same as production.
    public mutating func handleLiveUser(_ raw: String, itemID: String? = nil) {
        _ = itemID
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard ConversationPresence.wantsVersionAsk(text) else { return }
        lastUserUtterance = text
        dropAssistantOutput = true
        let line = ConversationPresence.spokenIdentityLine(for: text, identity: identity)
        assistantReply = line
        routingNotes = ["local build identity", identity.dogfoodLine]
        voicePath = "Eve realtime"
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

    /// Production shouldPlayBargeAudio after handleLiveUser + speakDeskReply.
    public mutating func ingestEveRealtimeDelta() {
        guard LiveVADPlayerKeep.shouldPlayEveAudio(
            dropAssistantOutput: dropAssistantOutput,
            clientTTSInFlight: clientTTSInFlight
        ) else { return }
        eveRealtimeChunks += 1
    }

    /// a2727b1 GrokVoiceService.shouldPlayBargeAudio: leftover barge
    /// only. No identity mute. Eve realtime still reaches the player.
    public mutating func ingestEveRealtimeDeltaA2727B1() {
        let allow = GrokRealtime.shouldScheduleAfterBarge(
            bargeConsumed: false,
            deltaResponseID: "eve",
            cancelledResponseID: nil
        )
        if allow { eveRealtimeChunks += 1 }
    }
}
