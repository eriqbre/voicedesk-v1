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

    public static let deskGlanceToolName = "deskGlance"

    /// Same rows the cards draw. Not `spokenInbox` ("Name on subject, and more.").
    public static func cardPayload(_ cards: [ContentCard]) -> String {
        cards.compactMap { card -> String? in
            switch card {
            case .email(let item):
                return [item.fromName, item.fromEmail, item.subject, item.sentAtLabel]
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
            case .calendar(let item):
                return [item.title, item.whenLabel]
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
            default:
                return nil
            }
        }.joined(separator: "\n")
    }
}
