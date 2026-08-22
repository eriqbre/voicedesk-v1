import Foundation

public enum Role: String, Hashable, Sendable {
    case user
    case assistant
}

public struct ConversationTurn: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let role: Role
    public var text: String
    public var cards: [ContentCard]
    public var suggestions: [String]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        cards: [ContentCard] = [],
        suggestions: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.cards = cards
        self.suggestions = suggestions
        self.createdAt = createdAt
    }
}

public enum ContentCardKind: String, Hashable, Sendable, CaseIterable {
    case email
    case listing
    case person
    case draftConfirm
    case statute
    case connectGoogle

    public var fixtureID: String { "card.\(rawValue)" }
}

public enum ContentCard: Identifiable, Hashable, Sendable {
    case email(EmailItem)
    case listing(ListingItem)
    case person(PersonItem)
    case draftConfirm(DraftConfirmItem)
    case statute(StatuteItem)
    case connectGoogle(ConnectGoogleItem)

    public var id: UUID {
        switch self {
        case .email(let item): item.id
        case .listing(let item): item.id
        case .person(let item): item.id
        case .draftConfirm(let item): item.id
        case .statute(let item): item.id
        case .connectGoogle(let item): item.id
        }
    }

    public var kind: ContentCardKind {
        switch self {
        case .email: .email
        case .listing: .listing
        case .person: .person
        case .draftConfirm: .draftConfirm
        case .statute: .statute
        case .connectGoogle: .connectGoogle
        }
    }

    public var fixtureID: String { kind.fixtureID }

    public var accessibilityIdentity: String {
        switch self {
        case .email(let item):
            "Email from \(item.fromName). \(item.subject)."
        case .listing(let item):
            "Listing \(item.addressLine), \(item.priceLabel)."
        case .person(let item):
            "\(item.name), \(item.roleLabel)."
        case .draftConfirm(let item):
            "Draft \(item.actionTitle) to \(item.toLine)."
        case .statute(let item):
            "\(item.title). Confidence \(item.confidence) percent, \(item.band.label). \(item.citation)."
        case .connectGoogle(let item):
            item.headline
        }
    }
}

public struct EmailItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var fromName: String
    public var fromEmail: String
    public var sentAtLabel: String
    public var subject: String
    public var preview: String
    public var filterTag: String
    public var relatedListing: String?
    public var relatedPeople: [String]

    public init(
        id: UUID = UUID(),
        fromName: String,
        fromEmail: String,
        sentAtLabel: String,
        subject: String,
        preview: String,
        filterTag: String,
        relatedListing: String? = nil,
        relatedPeople: [String] = []
    ) {
        self.id = id
        self.fromName = fromName
        self.fromEmail = fromEmail
        self.sentAtLabel = sentAtLabel
        self.subject = subject
        self.preview = preview
        self.filterTag = filterTag
        self.relatedListing = relatedListing
        self.relatedPeople = relatedPeople
    }

    public var initials: String {
        fromName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

public struct ListingItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var priceLabel: String
    public var addressLine: String
    public var cityLine: String
    public var beds: Int
    public var baths: Int
    public var sqft: Int
    public var status: String
    public var ownership: String
    public var relatedPeople: [String]

    public init(
        id: UUID = UUID(),
        priceLabel: String,
        addressLine: String,
        cityLine: String,
        beds: Int,
        baths: Int,
        sqft: Int,
        status: String,
        ownership: String,
        relatedPeople: [String] = []
    ) {
        self.id = id
        self.priceLabel = priceLabel
        self.addressLine = addressLine
        self.cityLine = cityLine
        self.beds = beds
        self.baths = baths
        self.sqft = sqft
        self.status = status
        self.ownership = ownership
        self.relatedPeople = relatedPeople
    }
}

public struct PersonItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var roleLabel: String
    public var detail: String
    public var phoneLabel: String
    public var accentHue: Double

    public init(
        id: UUID = UUID(),
        name: String,
        roleLabel: String,
        detail: String,
        phoneLabel: String,
        accentHue: Double
    ) {
        self.id = id
        self.name = name
        self.roleLabel = roleLabel
        self.detail = detail
        self.phoneLabel = phoneLabel
        self.accentHue = accentHue
    }

    public var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

public enum DraftStatus: String, Hashable, Sendable {
    case pending
    case editing
    case confirmed
    case cancelled
}

public struct DraftConfirmItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var actionTitle: String
    public var channel: String
    public var toLine: String
    public var subject: String
    public var body: String
    public var status: DraftStatus

    public init(
        id: UUID = UUID(),
        actionTitle: String,
        channel: String,
        toLine: String,
        subject: String,
        body: String,
        status: DraftStatus = .pending
    ) {
        self.id = id
        self.actionTitle = actionTitle
        self.channel = channel
        self.toLine = toLine
        self.subject = subject
        self.body = body
        self.status = status
    }
}

public enum ConfidenceBand: String, Hashable, Sendable {
    case firm
    case options
    case unknown

    public var label: String {
        switch self {
        case .firm: "Firm"
        case .options: "Options"
        case .unknown: "Unknown"
        }
    }

    /// Defaults from PRD §13: firm ≥85, options 50–84, refuse/ask <50.
    public static func band(for percent: Int) -> ConfidenceBand {
        if percent >= 85 { return .firm }
        if percent >= 50 { return .options }
        return .unknown
    }
}

public struct StatuteItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var plainLanguage: String
    public var citation: String
    public var confidence: Int
    public var disclaimer: String

    public init(
        id: UUID = UUID(),
        title: String,
        plainLanguage: String,
        citation: String,
        confidence: Int,
        disclaimer: String
    ) {
        self.id = id
        self.title = title
        self.plainLanguage = plainLanguage
        self.citation = citation
        self.confidence = min(100, max(0, confidence))
        self.disclaimer = disclaimer
    }

    public var band: ConfidenceBand { ConfidenceBand.band(for: confidence) }
}

public struct ConnectGoogleItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var headline: String
    public var body: String
    public var isConnected: Bool

    public init(
        id: UUID = UUID(),
        headline: String = "Connect Google",
        body: String = "Gmail, Calendar, and Tasks — required before VoiceDesk can work your real day.",
        isConnected: Bool = false
    ) {
        self.id = id
        self.headline = headline
        self.body = body
        self.isConnected = isConnected
    }
}

public struct ActivityEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let at: Date
    public let title: String
    public let detail: String
    public let outcome: String

    public init(
        id: UUID = UUID(),
        at: Date = Date(),
        title: String,
        detail: String,
        outcome: String
    ) {
        self.id = id
        self.at = at
        self.title = title
        self.detail = detail
        self.outcome = outcome
    }
}

public enum SessionPhase: Hashable, Sendable {
    case welcome
    case touring
    case ready
}
