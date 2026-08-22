import Foundation

enum Role: String, Hashable {
    case user
    case assistant
}

struct ConversationTurn: Identifiable, Hashable {
    let id: UUID
    let role: Role
    var text: String
    var cards: [ContentCard]
    var suggestions: [String]
    let createdAt: Date

    init(
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

enum ContentCard: Identifiable, Hashable {
    case email(EmailItem)
    case listing(ListingItem)
    case person(PersonItem)
    case draftConfirm(DraftConfirmItem)
    case statute(StatuteItem)
    case connectGoogle(ConnectGoogleItem)

    var id: UUID {
        switch self {
        case .email(let item): item.id
        case .listing(let item): item.id
        case .person(let item): item.id
        case .draftConfirm(let item): item.id
        case .statute(let item): item.id
        case .connectGoogle(let item): item.id
        }
    }
}

struct EmailItem: Identifiable, Hashable {
    let id: UUID
    var fromName: String
    var fromEmail: String
    var sentAtLabel: String
    var subject: String
    var preview: String
    var filterTag: String
    var relatedListing: String?
    var relatedPeople: [String]

    init(
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

    var initials: String {
        fromName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

struct ListingItem: Identifiable, Hashable {
    let id: UUID
    var priceLabel: String
    var addressLine: String
    var cityLine: String
    var beds: Int
    var baths: Int
    var sqft: Int
    var status: String
    var ownership: String
    var relatedPeople: [String]

    init(
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

struct PersonItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var roleLabel: String
    var detail: String
    var phoneLabel: String
    var accentHue: Double

    init(
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

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

enum DraftStatus: String, Hashable {
    case pending
    case editing
    case confirmed
    case cancelled
}

struct DraftConfirmItem: Identifiable, Hashable {
    let id: UUID
    var actionTitle: String
    var channel: String
    var toLine: String
    var subject: String
    var body: String
    var status: DraftStatus

    init(
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

enum ConfidenceBand: String, Hashable {
    case firm
    case options
    case unknown

    var label: String {
        switch self {
        case .firm: "Firm"
        case .options: "Options"
        case .unknown: "Unknown"
        }
    }

    /// Defaults from PRD §13: firm ≥85, options 50–84, refuse/ask <50.
    static func band(for percent: Int) -> ConfidenceBand {
        if percent >= 85 { return .firm }
        if percent >= 50 { return .options }
        return .unknown
    }
}

struct StatuteItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var plainLanguage: String
    var citation: String
    var confidence: Int
    var disclaimer: String

    init(
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

    var band: ConfidenceBand { ConfidenceBand.band(for: confidence) }
}

struct ConnectGoogleItem: Identifiable, Hashable {
    let id: UUID
    var headline: String
    var body: String
    var isConnected: Bool

    init(
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

struct ActivityEntry: Identifiable, Hashable {
    let id: UUID
    let at: Date
    let title: String
    let detail: String
    let outcome: String

    init(id: UUID = UUID(), at: Date = Date(), title: String, detail: String, outcome: String) {
        self.id = id
        self.at = at
        self.title = title
        self.detail = detail
        self.outcome = outcome
    }
}

enum SessionPhase: Hashable {
    case welcome
    case touring
    case ready
}
