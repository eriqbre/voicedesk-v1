import Foundation

/// Sticky person/thread focus across turns. First-class so agents do not parse notes.
public enum VoiceStickyState: String, Codable, Sendable, Equatable {
    case none
    case cleared
    case reused
}

/// Structured classification of one spoken/typed turn.
public struct VoiceTurnClassification: Equatable, Sendable {
    public var intent: String
    public var notes: [String]
    public var sticky: VoiceStickyState
    public var focusedPerson: String?
    public var searchQuery: String?

    public init(
        intent: String,
        notes: [String] = [],
        sticky: VoiceStickyState = .none,
        focusedPerson: String? = nil,
        searchQuery: String? = nil
    ) {
        self.intent = intent
        self.notes = notes
        self.sticky = sticky
        self.focusedPerson = focusedPerson
        self.searchQuery = searchQuery
    }
}

/// Structured voice-turn record. Persistence and UI are dogfood-only.
///
/// Schema v2 adds first-class `sticky`, `focusedPerson`, `searchQuery`, and `errors`
/// so a cloud pull shows transcript vs intent vs focused person without parsing notes.
public struct VoiceInteractionEntry: Equatable, Sendable, Identifiable {
    public static let currentSchemaVersion = 2

    public var id: UUID
    public var timestamp: Date
    public var schemaVersion: Int
    public var source: String
    public var userTranscript: String
    public var intent: String
    public var sticky: VoiceStickyState
    public var focusedPerson: String?
    public var searchQuery: String?
    public var routingNotes: [String]
    public var cardsAttached: [String]
    public var assistantReply: String
    public var voicePath: String
    public var errors: [String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        schemaVersion: Int = VoiceInteractionEntry.currentSchemaVersion,
        source: String,
        userTranscript: String,
        intent: String,
        sticky: VoiceStickyState = .none,
        focusedPerson: String? = nil,
        searchQuery: String? = nil,
        routingNotes: [String],
        cardsAttached: [String],
        assistantReply: String,
        voicePath: String,
        errors: [String] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.schemaVersion = schemaVersion
        self.source = source
        self.userTranscript = userTranscript
        self.intent = intent
        self.sticky = sticky
        self.focusedPerson = focusedPerson
        self.searchQuery = searchQuery
        self.routingNotes = routingNotes
        self.cardsAttached = cardsAttached
        self.assistantReply = assistantReply
        self.voicePath = voicePath
        self.errors = errors
    }
}

extension VoiceInteractionEntry: Codable {
    enum CodingKeys: String, CodingKey {
        case id, timestamp, schemaVersion, source, userTranscript, intent
        case sticky, focusedPerson, searchQuery
        case routingNotes, cardsAttached, assistantReply, voicePath, errors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "voice"
        userTranscript = try c.decode(String.self, forKey: .userTranscript)
        intent = try c.decode(String.self, forKey: .intent)
        sticky = try c.decodeIfPresent(VoiceStickyState.self, forKey: .sticky) ?? .none
        focusedPerson = try c.decodeIfPresent(String.self, forKey: .focusedPerson)
        searchQuery = try c.decodeIfPresent(String.self, forKey: .searchQuery)
        routingNotes = try c.decodeIfPresent([String].self, forKey: .routingNotes) ?? []
        cardsAttached = try c.decodeIfPresent([String].self, forKey: .cardsAttached) ?? []
        assistantReply = try c.decodeIfPresent(String.self, forKey: .assistantReply) ?? ""
        voicePath = try c.decodeIfPresent(String.self, forKey: .voicePath) ?? ""
        errors = try c.decodeIfPresent([String].self, forKey: .errors) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(source, forKey: .source)
        try c.encode(userTranscript, forKey: .userTranscript)
        try c.encode(intent, forKey: .intent)
        try c.encode(sticky, forKey: .sticky)
        try c.encodeIfPresent(focusedPerson, forKey: .focusedPerson)
        try c.encodeIfPresent(searchQuery, forKey: .searchQuery)
        try c.encode(routingNotes, forKey: .routingNotes)
        try c.encode(cardsAttached, forKey: .cardsAttached)
        try c.encode(assistantReply, forKey: .assistantReply)
        try c.encode(voicePath, forKey: .voicePath)
        try c.encode(errors, forKey: .errors)
    }
}

/// Append-only interaction log. Storage is a no-op unless DEBUG or TestFlight.
public enum VoiceInteractionLog: Sendable {
    /// Tests override the DEBUG/TestFlight gate.
    public static var testEnabledOverride: Bool?

    public static var isEnabled: Bool {
        if let testEnabledOverride { return testEnabledOverride }
        return VoiceDogfoodGate.allowsLogging(
            compileDebug: VoiceDogfoodGate.compileDebug,
            isTestFlight: VoiceDogfoodGate.isTestFlightReceipt()
        )
    }

    public static func classify(
        utterance: String,
        evidence: ConversationPresence.DeskEvidence?,
        pendingSearchClarify: Bool = false,
        hadFocusedEmail: Bool = false,
        hasClarifyMatches: Bool = false
    ) -> VoiceTurnClassification {
        var notes: [String] = []
        var sticky: VoiceStickyState = .none
        var focusedPerson: String?
        var searchQuery: String?

        if pendingSearchClarify { notes.append("pending clarify") }
        let attached = evidence?.focusedEmail
        let namedMismatch = GmailSearchQuery.namedSenderMismatches(attached, ask: utterance)
            || (hadFocusedEmail && evidence?.resetsFocusedEmail == true)
            || (hadFocusedEmail && attached == nil && GmailSearchQuery.hasSenderPattern(utterance))
        if evidence?.resetsFocusedEmail == true || namedMismatch {
            sticky = .cleared
            notes.append("sticky cleared")
        } else if hadFocusedEmail, let focused = attached, evidence?.resetsFocusedEmail != true {
            sticky = .reused
            focusedPerson = focused.fromName
            notes.append("sticky reused (\(focused.fromName))")
        }
        if let query = evidence?.gmailQuery, !query.isEmpty {
            searchQuery = query
            notes.append("search \(query)")
            notes.append(evidence?.shouldSearchGmail == true ? "cache miss" : "named query")
        } else if evidence != nil, evidence?.shouldSearchGmail != true {
            notes.append("synced cache / list")
            // Cache hit still records the planned q= so fixtures can assert from:murray
            // (and dogfood can see “When was Murray's…” did not become from:("was murray")).
            if ConversationPresence.looksLikeMailAsk(utterance)
                || ConversationPresence.hasDeskMailIntent(utterance),
               let planned = GmailSearchQuery.query(from: utterance),
               planned.lowercased().contains("from:") {
                searchQuery = planned
                notes.append("named query \(planned)")
            }
        }
        if let sender = attached?.fromName,
           !GmailSearchQuery.namedSenderMismatches(attached, ask: utterance) {
            focusedPerson = sender
            notes.append("sender \(sender)")
        }

        if pendingSearchClarify, ConversationPresence.isClarifyPick(utterance) {
            notes.append("clarify pick")
        }

        let intent: String
        if ConversationPresence.wantsInboxOverview(utterance) {
            intent = "inbox-overview"
        } else if ConversationPresence.wantsCalendarAsk(utterance) {
            intent = "calendar"
        } else if ConversationPresence.wantsTaskAsk(utterance) {
            intent = "task"
        } else if ConversationPresence.wantsConnectGoogle(utterance) {
            intent = "connect"
        } else if ConversationPresence.wantsTour(utterance) {
            intent = "tour"
        } else if evidence?.text == ConversationPresence.emailNeedMoreReply {
            intent = "need-more"
        } else if evidence?.expandEarlierMessages == true {
            intent = "desk-thread"
        } else if ConversationPresence.wantsEmailFollowUp(utterance) {
            intent = "desk-follow-up"
        } else if pendingSearchClarify, ConversationPresence.isClarifyPick(utterance) {
            intent = "desk-person"
        } else if evidence?.focusedEmail != nil || ConversationPresence.looksLikeMailAsk(utterance) {
            intent = "desk-person"
        } else if ConversationPresence.ownsConnectedDeskTurn(
            utterance,
            pendingSearchClarify: pendingSearchClarify,
            hasClarifyMatches: hasClarifyMatches
        ) {
            intent = "desk-person"
        } else {
            intent = "general"
        }

        return VoiceTurnClassification(
            intent: intent,
            notes: notes,
            sticky: sticky,
            focusedPerson: focusedPerson,
            searchQuery: searchQuery
        )
    }

    public static func cardLabels(_ cards: [ContentCard]) -> [String] {
        cards.map { card in
            switch card {
            case .email(let item):
                return "email:\(item.fromName):\(item.subject)"
            case .calendar(let item):
                return "calendar:\(item.title)"
            case .task(let item):
                return "task:\(item.title)"
            case .connectGoogle:
                return "connectGoogle"
            case .listing(let item):
                return "listing:\(item.addressLine)"
            case .person(let item):
                return "person:\(item.name)"
            case .draftConfirm(let item):
                return "draft:\(item.subject)"
            case .statute(let item):
                return "statute:\(item.citation)"
            }
        }
    }

    public static func record(_ entry: VoiceInteractionEntry) {
        guard isEnabled else {
            return
        }
        lock.lock()
        storage.append(entry)
        if storage.count > 80 {
            storage.removeFirst(storage.count - 80)
        }
        lock.unlock()
    }

    public static func snapshot() -> [VoiceInteractionEntry] {
        guard isEnabled else { return [] }
        lock.lock()
        let copy = storage
        lock.unlock()
        return copy
    }

    public static func resetForTests() {
        lock.lock()
        storage = []
        lock.unlock()
        testEnabledOverride = nil
    }

    public static func exportJSON() -> String {
        guard isEnabled else { return "[]" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(snapshot())) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static var storage: [VoiceInteractionEntry] = []
    private static let lock = NSLock()
}
