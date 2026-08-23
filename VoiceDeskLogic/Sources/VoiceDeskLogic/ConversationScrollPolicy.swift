import Foundation

public enum ConversationScrollAnchor: String, Sendable, Equatable {
    case top
    case center
}

public enum ConversationScrollReason: String, Sendable, Equatable {
    case userUtterance
    case assistantReply
    case cardsPeek
    case expandInPlace
    case none
}

public struct ConversationScrollRequest: Equatable, Sendable {
    public var targetID: UUID
    public var anchor: ConversationScrollAnchor
    public var reason: ConversationScrollReason

    public init(targetID: UUID, anchor: ConversationScrollAnchor, reason: ConversationScrollReason) {
        self.targetID = targetID
        self.anchor = anchor
        self.reason = reason
    }
}

/// Auto-scroll for conversation turns. Never jump to absolute bottom / last card.
public enum ConversationScrollPolicy: Sendable {
    /// User bubble committed — keep that bubble on screen.
    public static func afterUser(turnID: UUID) -> ConversationScrollRequest {
        ConversationScrollRequest(targetID: turnID, anchor: .top, reason: .userUtterance)
    }

    /// Eve reply — pin her text near the top so a following card stack peeks.
    public static func afterAssistant(turnID: UUID, hasCards: Bool) -> ConversationScrollRequest {
        ConversationScrollRequest(
            targetID: turnID,
            anchor: .top,
            reason: hasCards ? .cardsPeek : .assistantReply
        )
    }

    /// Compact-row expand stays in place.
    public static func afterExpand() -> ConversationScrollRequest? { nil }
}
