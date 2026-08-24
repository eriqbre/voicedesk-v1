import Foundation

/// One promoted DEBUG voice-log line, plus optional replay context.
///
/// Live log fields match `VoiceInteractionEntry`. Extra keys are added when promoting
/// (`hadFocusedEmail`, `assertReply`, …). Extra keys are ignored by the in-app logger.
public struct VoiceRegressionFixture: Codable, Equatable, Sendable {
    public var id: UUID?
    public var timestamp: Date?
    public var source: String
    public var userTranscript: String
    public var intent: String
    public var routingNotes: [String]
    public var cardsAttached: [String]
    public var assistantReply: String
    public var voicePath: String

    /// Prior sticky person/thread (not always present on a raw log line).
    public var hadFocusedEmail: Bool?
    public var stickyFromName: String?
    public var deskPreset: String?
    public var pendingSearchClarify: Bool?
    public var pendingSenderRefine: Bool?
    public var connected: Bool?

    /// When `pendingSearchClarify` is true, replay uses the desk snapshot emails as
    /// multi-match cards so “the last one” / “the latest” stay desk-owned.

    /// Desk-owned turns: assert reply text when `assistantReply` is non-empty.
    /// General / live Grok: leave false — routing only.
    public var assertReply: Bool?
    public var requiredNotes: [String]?
    public var forbiddenSubstrings: [String]?
    public var allowedIntents: [String]?

    public var isGeneralRoute: Bool {
        intent == "general"
    }

    public var intentsThatPass: Set<String> {
        var set = Set(allowedIntents ?? [])
        set.insert(intent)
        return set
    }

    public var shouldAssertReply: Bool {
        if let assertReply { return assertReply }
        return !isGeneralRoute && !assistantReply.isEmpty
    }

    public init(
        id: UUID? = nil,
        timestamp: Date? = nil,
        source: String = "voice",
        userTranscript: String,
        intent: String,
        routingNotes: [String] = [],
        cardsAttached: [String] = [],
        assistantReply: String = "",
        voicePath: String = "Eve realtime",
        hadFocusedEmail: Bool? = nil,
        stickyFromName: String? = nil,
        deskPreset: String? = nil,
        pendingSearchClarify: Bool? = nil,
        pendingSenderRefine: Bool? = nil,
        connected: Bool? = true,
        assertReply: Bool? = nil,
        requiredNotes: [String]? = nil,
        forbiddenSubstrings: [String]? = nil,
        allowedIntents: [String]? = nil
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
        self.hadFocusedEmail = hadFocusedEmail
        self.stickyFromName = stickyFromName
        self.deskPreset = deskPreset
        self.pendingSearchClarify = pendingSearchClarify
        self.pendingSenderRefine = pendingSenderRefine
        self.connected = connected
        self.assertReply = assertReply
        self.requiredNotes = requiredNotes
        self.forbiddenSubstrings = forbiddenSubstrings
        self.allowedIntents = allowedIntents
    }

    public static func decodeJSONL(_ text: String) throws -> [VoiceRegressionFixture] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var fixtures: [VoiceRegressionFixture] = []
        for (index, raw) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            do {
                fixtures.append(try decoder.decode(VoiceRegressionFixture.self, from: Data(line.utf8)))
            } catch {
                throw DecodeError.line(index + 1, error)
            }
        }
        return fixtures
    }

    public static func encodeJSONL(_ fixtures: [VoiceRegressionFixture]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try fixtures.map { fixture in
            let data = try encoder.encode(fixture)
            guard var line = String(data: data, encoding: .utf8) else {
                throw DecodeError.encode
            }
            if line.hasSuffix("\n") { line.removeLast() }
            return line
        }.joined(separator: "\n") + "\n"
    }

    /// Promote a DEBUG `voice-log.jsonl` line. Review / sanitize before committing.
    public static func promote(logLine: String) throws -> VoiceRegressionFixture {
        let decoded = try decodeJSONL(logLine)
        guard let fixture = decoded.first, decoded.count == 1 else {
            throw DecodeError.expectedOneLine
        }
        return fixture
    }

    /// Signals that a fixture still looks like a raw dogfood dump.
    public func piiWarnings() -> [String] {
        Self.piiWarnings(in: userTranscript + "\n" + assistantReply + "\n" + cardsAttached.joined(separator: "\n"))
    }

    public static func piiWarnings(in raw: String) -> [String] {
        var warnings: [String] = []
        let detector = try? NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: .caseInsensitive)
        let ns = raw as NSString
        detector?.enumerateMatches(in: raw, options: [], range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let email = ns.substring(with: match.range).lowercased()
            if !email.hasSuffix("@example.com") {
                warnings.append("non-example email \(email)")
            }
        }
        if raw.range(of: #"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b"#, options: .regularExpression) != nil {
            warnings.append("phone number")
        }
        return warnings
    }

    public enum DecodeError: Error, CustomStringConvertible {
        case line(Int, Error)
        case expectedOneLine
        case encode

        public var description: String {
            switch self {
            case .line(let number, let error):
                return "voice-regression JSONL line \(number): \(error)"
            case .expectedOneLine:
                return "promote expects exactly one JSONL line"
            case .encode:
                return "could not encode fixture JSONL"
            }
        }
    }
}

extension VoiceRegressionFixture {
    enum CodingKeys: String, CodingKey {
        case id, timestamp, source, userTranscript, intent, routingNotes
        case cardsAttached, assistantReply, voicePath
        case hadFocusedEmail, stickyFromName, deskPreset, pendingSearchClarify, pendingSenderRefine, connected
        case assertReply, requiredNotes, forbiddenSubstrings, allowedIntents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id)
        timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "voice"
        userTranscript = try c.decode(String.self, forKey: .userTranscript)
        intent = try c.decode(String.self, forKey: .intent)
        routingNotes = try c.decodeIfPresent([String].self, forKey: .routingNotes) ?? []
        cardsAttached = try c.decodeIfPresent([String].self, forKey: .cardsAttached) ?? []
        assistantReply = try c.decodeIfPresent(String.self, forKey: .assistantReply) ?? ""
        voicePath = try c.decodeIfPresent(String.self, forKey: .voicePath) ?? "Eve realtime"
        hadFocusedEmail = try c.decodeIfPresent(Bool.self, forKey: .hadFocusedEmail)
        stickyFromName = try c.decodeIfPresent(String.self, forKey: .stickyFromName)
        deskPreset = try c.decodeIfPresent(String.self, forKey: .deskPreset)
        pendingSearchClarify = try c.decodeIfPresent(Bool.self, forKey: .pendingSearchClarify)
        pendingSenderRefine = try c.decodeIfPresent(Bool.self, forKey: .pendingSenderRefine)
        connected = try c.decodeIfPresent(Bool.self, forKey: .connected)
        assertReply = try c.decodeIfPresent(Bool.self, forKey: .assertReply)
        requiredNotes = try c.decodeIfPresent([String].self, forKey: .requiredNotes)
        forbiddenSubstrings = try c.decodeIfPresent([String].self, forKey: .forbiddenSubstrings)
        allowedIntents = try c.decodeIfPresent([String].self, forKey: .allowedIntents)
    }
}
