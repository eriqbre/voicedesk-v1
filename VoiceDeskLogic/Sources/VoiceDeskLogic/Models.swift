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
    case calendar
    case task

    public var fixtureID: String { "card.\(rawValue)" }
}

public enum ContentCard: Identifiable, Hashable, Sendable {
    case email(EmailItem)
    case listing(ListingItem)
    case person(PersonItem)
    case draftConfirm(DraftConfirmItem)
    case statute(StatuteItem)
    case connectGoogle(ConnectGoogleItem)
    case calendar(CalendarItem)
    case task(TaskItem)

    public var id: UUID {
        switch self {
        case .email(let item): item.id
        case .listing(let item): item.id
        case .person(let item): item.id
        case .draftConfirm(let item): item.id
        case .statute(let item): item.id
        case .connectGoogle(let item): item.id
        case .calendar(let item): item.id
        case .task(let item): item.id
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
        case .calendar: .calendar
        case .task: .task
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
        case .calendar(let item):
            item.accessibilityLabel
        case .task(let item):
            "Task \(item.title)."
        }
    }
}

public struct EmailThreadMessage: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var fromName: String
    public var fromEmail: String
    public var sentAtLabel: String
    public var htmlBody: String?
    public var plainBody: String?

    public init(
        id: String,
        fromName: String,
        fromEmail: String = "",
        sentAtLabel: String = "",
        htmlBody: String? = nil,
        plainBody: String? = nil
    ) {
        self.id = id
        self.fromName = fromName
        self.fromEmail = fromEmail
        self.sentAtLabel = sentAtLabel
        self.htmlBody = htmlBody
        self.plainBody = plainBody
    }

    public var hasReadableBody: Bool {
        let plain = (plainBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let html = (htmlBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !plain.isEmpty || !html.isEmpty
    }
}

public enum EmailCardPresentation: String, Hashable, Sendable, Codable {
    case full
    case compact
}

public struct EmailItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var providerID: String?
    public var threadID: String?
    public var fromName: String
    public var fromEmail: String
    public var sentAtLabel: String
    public var subject: String
    public var preview: String
    public var body: String?
    public var htmlBody: String?
    public var earlierMessages: [EmailThreadMessage]
    public var filterTag: String
    public var relatedListing: String?
    public var relatedPeople: [String]
    /// Inbox-overview / multi-hit lists use compact rows. Single-thread stays full.
    public var cardPresentation: EmailCardPresentation

    public var hasFullBody: Bool {
        let plain = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let html = (htmlBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !plain.isEmpty || !html.isEmpty
    }

    public var hasEarlierMessages: Bool { !earlierMessages.isEmpty }

    public init(
        id: UUID = UUID(),
        providerID: String? = nil,
        threadID: String? = nil,
        fromName: String,
        fromEmail: String,
        sentAtLabel: String,
        subject: String,
        preview: String,
        body: String? = nil,
        htmlBody: String? = nil,
        earlierMessages: [EmailThreadMessage] = [],
        filterTag: String,
        relatedListing: String? = nil,
        relatedPeople: [String] = [],
        cardPresentation: EmailCardPresentation = .full
    ) {
        self.id = id
        self.providerID = providerID
        self.threadID = threadID
        self.fromName = fromName
        self.fromEmail = fromEmail
        self.sentAtLabel = sentAtLabel
        self.subject = subject
        self.preview = preview
        self.body = body
        self.htmlBody = htmlBody
        self.earlierMessages = earlierMessages
        self.filterTag = filterTag
        self.relatedListing = relatedListing
        self.relatedPeople = relatedPeople
        self.cardPresentation = cardPresentation
    }

    public var isCompactListRow: Bool { cardPresentation == .compact }

    public var compactSnippet: String {
        let gist = EmailBodyFormatting.spokenSummary(from: body, fallback: preview, style: .brief)
        if gist.isEmpty {
            return preview.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return gist
    }

    public func presented(as presentation: EmailCardPresentation) -> EmailItem {
        var copy = self
        copy.cardPresentation = presentation
        return copy
    }

    public static func listCards(_ emails: [EmailItem]) -> [ContentCard] {
        let presentation: EmailCardPresentation = emails.count > 1 ? .compact : .full
        return emails.map { .email($0.presented(as: presentation)) }
    }

    public var initials: String {
        fromName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    enum CodingKeys: String, CodingKey {
        case id, providerID, threadID, fromName, fromEmail, sentAtLabel
        case subject, preview, body, htmlBody, earlierMessages
        case filterTag, relatedListing, relatedPeople, cardPresentation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        fromName = try container.decode(String.self, forKey: .fromName)
        fromEmail = try container.decode(String.self, forKey: .fromEmail)
        sentAtLabel = try container.decode(String.self, forKey: .sentAtLabel)
        subject = try container.decode(String.self, forKey: .subject)
        preview = try container.decode(String.self, forKey: .preview)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        htmlBody = try container.decodeIfPresent(String.self, forKey: .htmlBody)
        earlierMessages = try container.decodeIfPresent([EmailThreadMessage].self, forKey: .earlierMessages) ?? []
        filterTag = try container.decode(String.self, forKey: .filterTag)
        relatedListing = try container.decodeIfPresent(String.self, forKey: .relatedListing)
        relatedPeople = try container.decodeIfPresent([String].self, forKey: .relatedPeople) ?? []
        cardPresentation = try container.decodeIfPresent(EmailCardPresentation.self, forKey: .cardPresentation) ?? .full
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(providerID, forKey: .providerID)
        try container.encodeIfPresent(threadID, forKey: .threadID)
        try container.encode(fromName, forKey: .fromName)
        try container.encode(fromEmail, forKey: .fromEmail)
        try container.encode(sentAtLabel, forKey: .sentAtLabel)
        try container.encode(subject, forKey: .subject)
        try container.encode(preview, forKey: .preview)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(htmlBody, forKey: .htmlBody)
        try container.encode(earlierMessages, forKey: .earlierMessages)
        try container.encode(filterTag, forKey: .filterTag)
        try container.encodeIfPresent(relatedListing, forKey: .relatedListing)
        try container.encode(relatedPeople, forKey: .relatedPeople)
        if cardPresentation != .full {
            try container.encode(cardPresentation, forKey: .cardPresentation)
        }
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

public struct CalendarItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var providerID: String?
    public var title: String
    public var whenLabel: String
    public var location: String?
    public var relatedPeople: [String]
    public var startAt: Date?
    /// Google Calendar `description` — notes shown on the expanded card.
    public var notes: String?

    public init(
        id: UUID = UUID(),
        providerID: String? = nil,
        title: String,
        whenLabel: String,
        location: String? = nil,
        relatedPeople: [String] = [],
        startAt: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.title = title
        self.whenLabel = whenLabel
        self.location = location
        self.relatedPeople = relatedPeople
        self.startAt = startAt
        self.notes = notes
    }

    public var hasDetails: Bool {
        !(location ?? "").isEmpty || !relatedPeople.isEmpty || !(notes ?? "").isEmpty
    }

    public var accessibilityLabel: String {
        var parts = ["Calendar \(title).", whenLabel]
        if let location, !location.isEmpty { parts.append(location) }
        if !relatedPeople.isEmpty { parts.append(relatedPeople.joined(separator: ", ")) }
        if let notes, !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: ". ")
    }
}

public struct TaskItem: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var providerID: String?
    public var title: String
    public var dueLabel: String?
    public var notes: String?
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        providerID: String? = nil,
        title: String,
        dueLabel: String? = nil,
        notes: String? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.providerID = providerID
        self.title = title
        self.dueLabel = dueLabel
        self.notes = notes
        self.isCompleted = isCompleted
    }
}

public struct ConnectGoogleItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var headline: String
    public var body: String
    public var isConnected: Bool
    public var accountEmail: String?
    public var setupNeeded: Bool
    public var statusLine: String

    public init(
        id: UUID = UUID(),
        headline: String = "Connect Google",
        body: String = "Gmail, Calendar, and Tasks — required before VoiceDesk can work your real day.",
        isConnected: Bool = false,
        accountEmail: String? = nil,
        setupNeeded: Bool = false,
        statusLine: String = "Required for a real day"
    ) {
        self.id = id
        self.headline = headline
        self.body = body
        self.isConnected = isConnected
        self.accountEmail = accountEmail
        self.setupNeeded = setupNeeded
        self.statusLine = statusLine
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
