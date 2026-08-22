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
            "You talk, I answer, and I put the evidence on cards.",
            cards: graphCards()
        )
        document.appendAssistant(
            "Writes always wait for your confirm.",
            cards: [draftCard()]
        )
        document.appendAssistant(
            "Legal answers show confidence and the citation.",
            cards: [statuteCard()]
        )
        document.appendAssistant(
            "Connect Google for your real inbox, calendar, and tasks.",
            cards: [connectGoogleCard()]
        )
    }

    public static var requiredKinds: [ContentCardKind] {
        [.email, .listing, .person, .draftConfirm, .statute, .connectGoogle]
    }
}
