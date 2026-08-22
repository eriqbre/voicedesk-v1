import Foundation

/// Inserts content cards into the conversation spine (Style C).
public struct ConversationDocument: Hashable, Sendable {
    public var turns: [ConversationTurn]

    public init(turns: [ConversationTurn] = []) {
        self.turns = turns
    }

    public mutating func appendUser(_ text: String) {
        turns.append(ConversationTurn(role: .user, text: text))
    }

    public mutating func appendAssistant(
        _ text: String,
        cards: [ContentCard] = [],
        suggestions: [String] = []
    ) {
        turns.append(ConversationTurn(role: .assistant, text: text, cards: cards, suggestions: suggestions))
    }

    public var insertedCards: [ContentCard] {
        turns.flatMap(\.cards)
    }

    public func cards(of kind: ContentCardKind) -> [ContentCard] {
        insertedCards.filter { $0.kind == kind }
    }

    public var insertedKinds: [ContentCardKind] {
        insertedCards.map(\.kind)
    }
}

public enum TourScript {
    public static func graphCards() -> [ContentCard] {
        [
            .email(SampleData.email()),
            .listing(SampleData.listing()),
            .person(SampleData.buyer()),
            .person(SampleData.partner())
        ]
    }

    public static func draftCard() -> ContentCard {
        .draftConfirm(SampleData.draftReply())
    }

    public static func statuteCard() -> ContentCard {
        .statute(SampleData.statute())
    }

    public static func connectGoogleCard(isConnected: Bool = false) -> ContentCard {
        .connectGoogle(SampleData.connectGoogle(isConnected: isConnected))
    }

    public static func play(into document: inout ConversationDocument) {
        document.appendAssistant(
            "You talk, I answer. When it’s your desk, I put the proof next to what I say.",
            cards: graphCards()
        )
        document.appendAssistant(
            "If I need to send something, you’ll see the exact words first.",
            cards: [draftCard()]
        )
        document.appendAssistant(
            "Law comes with how sure I am, and the source.",
            cards: [statuteCard()]
        )
        document.appendAssistant(
            "When you want me to know your real day, connect Google. Until then, ask me anything.",
            cards: [connectGoogleCard()]
        )
    }

    public static var requiredKinds: [ContentCardKind] {
        [.email, .listing, .person, .draftConfirm, .statute, .connectGoogle]
    }
}
