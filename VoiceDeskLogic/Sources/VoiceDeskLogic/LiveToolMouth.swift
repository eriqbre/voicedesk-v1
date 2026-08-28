import Foundation

/// 12:14: one spoken mouth after tools. Not a mute/hold of first PCM.
/// `create_response` is false while tools run; one `response.create` after.
public enum LiveToolMouth: Sendable {
    public static func needsClientTools(
        ask: String,
        snapshot: DeskSnapshot,
        isConnected: Bool,
        isOnline: Bool
    ) -> Bool {
        guard isConnected, isOnline else { return false }
        if ConversationPresence.looksLikeMailAsk(ask)
            || ConversationPresence.wantsInboxOverview(ask)
            || ConversationPresence.wantsCalendarAsk(ask)
            || ConversationPresence.matchingCalendar(for: ask, in: snapshot.events) != nil {
            return true
        }
        return false
    }

    /// fd4a772: create with no tool-done payload is empty/IDK then cards.
    /// 59c6d81: begin/end wait then bare create — same hole.
    /// Leftover inbound `response.created` is not alreadyCreated.
    public static func shouldSendResponseCreate(
        toolWait: Bool,
        alreadyCreated: Bool,
        hasToolResult: Bool = false
    ) -> Bool {
        !toolWait && !alreadyCreated && hasToolResult
    }

    /// Cards draw from the same rows as `function_call_output`.
    /// Parking before that report is the 59 start-park leftover.
    public static func shouldParkLiveDeskCards(hasToolResult: Bool) -> Bool {
        hasToolResult
    }

    /// bdbace4 walk 14B69B95: calendar was spoken, prior Authentisign
    /// email cards stayed up. Visible cards after tool-done must be this
    /// turn's rows, not leftover. Empty current still replaces leftover.
    public static func isStickyPriorDeskCards(
        visible: [ContentCard],
        current: [ContentCard]
    ) -> Bool {
        let currentKinds = Set(current.map(\.kind))
        if currentKinds.isEmpty {
            return visible.contains { $0.kind == .email || $0.kind == .calendar }
        }
        return visible.contains { !currentKinds.contains($0.kind) }
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
