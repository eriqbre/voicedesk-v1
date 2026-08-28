import Foundation

/// 12:14: one spoken mouth after tools. Not a mute/hold of first PCM.
/// `create_response` is false while tools run; one `response.create` after.
public enum LiveToolMouth: Sendable {
    public static func needsClientTools(
        ask: String,
        snapshot _: DeskSnapshot,
        isConnected: Bool,
        isOnline: Bool
    ) -> Bool {
        guard isConnected, isOnline else { return false }
        if ConversationPresence.looksLikeMailAsk(ask)
            || ConversationPresence.wantsInboxOverview(ask)
            || ConversationPresence.wantsCalendarAsk(ask) {
            return true
        }
        return false
    }

    public static func shouldSendResponseCreate(toolWait: Bool, alreadyCreated: Bool) -> Bool {
        !toolWait && !alreadyCreated
    }
}
