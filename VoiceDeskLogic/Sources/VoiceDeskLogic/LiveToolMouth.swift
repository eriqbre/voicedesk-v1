import Foundation

/// 12:14 leftover: Eve’s first VAD mouth is I-don’t-know / empty
/// before client tools land, then a later mouth with the real answer.
/// Product: wait for tools, then one mouth. Not a mute flag.
public struct LiveToolMouth: Equatable, Sendable {
    public var firstMouth: String
    public var firstMouthBeforeTools: Bool
    public var laterMouth: String
    public var createdCount: Int

    public init(
        firstMouth: String,
        firstMouthBeforeTools: Bool,
        laterMouth: String,
        createdCount: Int
    ) {
        self.firstMouth = firstMouth
        self.firstMouthBeforeTools = firstMouthBeforeTools
        self.laterMouth = laterMouth
        self.createdCount = createdCount
    }

    /// Noon walk on 83a5c6a: I-don’t-know / empty, then the real answer.
    public static func leftover1214() -> LiveToolMouth {
        LiveToolMouth(
            firstMouth: "I don't know",
            firstMouthBeforeTools: true,
            laterMouth: "Murray wrote about the closing package.",
            createdCount: 2
        )
    }

    public static func leftover1214EmptyFirst() -> LiveToolMouth {
        LiveToolMouth(
            firstMouth: "",
            firstMouthBeforeTools: true,
            laterMouth: "Murray wrote about the closing package.",
            createdCount: 2
        )
    }

    /// Tools landed, then one spoken mouth. No later mouth.
    public static func productWaitThenOneMouth(answer: String) -> LiveToolMouth {
        LiveToolMouth(
            firstMouth: answer,
            firstMouthBeforeTools: false,
            laterMouth: "",
            createdCount: 1
        )
    }

    public var isEarlyIDontKnowThenRealAnswer: Bool {
        firstMouthBeforeTools
            && Self.isIDontKnowOrEmpty(firstMouth)
            && !laterMouth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func isIDontKnowOrEmpty(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased().replacingOccurrences(of: "’", with: "'")
        if lower.contains("i don't know") { return true }
        if lower.contains("i do not know") { return true }
        return false
    }

    /// Live mail / empty-calendar asks run client tools. Hold first
    /// audio until those land so VAD cannot speak a placeholder mouth.
    public static func shouldHoldFirstAudioUntilTools(
        ask: String,
        snapshot: DeskSnapshot,
        isConnected: Bool,
        isOnline: Bool
    ) -> Bool {
        guard isConnected, isOnline else { return false }
        if ConversationPresence.looksLikeMailAsk(ask)
            || ConversationPresence.wantsInboxOverview(ask) {
            return true
        }
        return ConversationPresence.wantsCalendarAsk(ask) && snapshot.events.isEmpty
    }

    public static func shouldPlayFirstAudio(
        awaitingIntent: Bool = false,
        needsTools: Bool,
        toolsLanded: Bool
    ) -> Bool {
        if awaitingIntent { return false }
        return !needsTools || toolsLanded
    }

    /// Unheard early create may be cancelled; one `response.create`
    /// after tools is the waited mouth — not a command barge.
    public static func shouldCreateAfterTools(
        needsTools: Bool,
        toolsLanded: Bool,
        playedFirstAudio: Bool
    ) -> Bool {
        needsTools && toolsLanded && !playedFirstAudio
    }
}
