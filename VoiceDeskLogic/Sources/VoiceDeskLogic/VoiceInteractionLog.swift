import Foundation

/// Structured voice-turn record. Persistence and UI are DEBUG-only.
public struct VoiceInteractionEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var source: String
    public var userTranscript: String
    public var intent: String
    public var routingNotes: [String]
    public var cardsAttached: [String]
    public var assistantReply: String
    public var voicePath: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: String,
        userTranscript: String,
        intent: String,
        routingNotes: [String],
        cardsAttached: [String],
        assistantReply: String,
        voicePath: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.userTranscript = userTranscript
        self.intent = intent
        self.routingNotes = routingNotes
        self.cardsAttached = cardsAttached
        self.assistantReply = assistantReply
        self.voicePath = voicePath
    }
}

/// Append-only interaction log. Storage compiles out of Release.
public enum VoiceInteractionLog: Sendable {
    public static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    public static func classify(
        utterance: String,
        evidence: ConversationPresence.DeskEvidence?,
        pendingSearchClarify: Bool = false,
        hadFocusedEmail: Bool = false
    ) -> (intent: String, notes: [String]) {
        var notes: [String] = []
        if pendingSearchClarify { notes.append("pending clarify") }
        if evidence?.resetsFocusedEmail == true {
            notes.append("sticky cleared")
        } else if hadFocusedEmail, let focused = evidence?.focusedEmail, evidence?.resetsFocusedEmail != true {
            notes.append("sticky reused (\(focused.fromName))")
        }
        if let query = evidence?.gmailQuery, !query.isEmpty {
            notes.append("search \(query)")
            notes.append(evidence?.shouldSearchGmail == true ? "cache miss" : "named query")
        } else if evidence != nil, evidence?.shouldSearchGmail != true {
            notes.append("synced cache / list")
        }
        if let sender = evidence?.focusedEmail?.fromName, evidence?.resetsFocusedEmail != true {
            notes.append("sender \(sender)")
        }

        if ConversationPresence.wantsInboxOverview(utterance) || evidence?.resetsFocusedEmail == true {
            return ("inbox-overview", notes)
        }
        if ConversationPresence.wantsCalendarAsk(utterance) { return ("calendar", notes) }
        if ConversationPresence.wantsTaskAsk(utterance) { return ("task", notes) }
        if ConversationPresence.wantsConnectGoogle(utterance) { return ("connect", notes) }
        if ConversationPresence.wantsTour(utterance) { return ("tour", notes) }
        if evidence?.text == ConversationPresence.emailNeedMoreReply {
            return ("need-more", notes)
        }
        if evidence?.expandEarlierMessages == true { return ("desk-thread", notes) }
        if ConversationPresence.wantsEmailFollowUp(utterance) { return ("desk-follow-up", notes) }
        if evidence?.focusedEmail != nil || ConversationPresence.looksLikeMailAsk(utterance) {
            return ("desk-person", notes)
        }
        if ConversationPresence.ownsConnectedDeskTurn(utterance) {
            return ("desk-person", notes)
        }
        return ("general", notes)
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
        #if DEBUG
        lock.lock()
        storage.append(entry)
        if storage.count > 80 {
            storage.removeFirst(storage.count - 80)
        }
        lock.unlock()
        #else
        _ = entry
        #endif
    }

    public static func snapshot() -> [VoiceInteractionEntry] {
        #if DEBUG
        lock.lock()
        let copy = storage
        lock.unlock()
        return copy
        #else
        return []
        #endif
    }

    public static func resetForTests() {
        #if DEBUG
        lock.lock()
        storage = []
        lock.unlock()
        #endif
    }

    public static func exportJSON() -> String {
        #if DEBUG
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(snapshot())) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
        #else
        return "[]"
        #endif
    }

    #if DEBUG
    private static var storage: [VoiceInteractionEntry] = []
    private static let lock = NSLock()
    #endif
}
