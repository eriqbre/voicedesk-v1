import Foundation

/// ASR sometimes finalizes a stem before the rest of the utterance.
/// That stem is not a user turn: hold it, wait for a later partial/final
/// inside a short window, then classify the **combined** phrase.
///
/// Do **not** mute the mic. If nothing more arrives, drop the stem — never
/// send a bare “what’s” / “hm” / “give me a summary” to live Grok.
public struct EarlyFinalHold: Equatable, Sendable {
    public var heldPrefix: String?
    public var heldAt: Date?

    /// Later fragment of the same utterance usually lands inside this window.
    public static let defaultWindow: TimeInterval = 6

    public init() {}

    public mutating func reset() {
        heldPrefix = nil
        heldAt = nil
    }

    /// Whole utterance is only an incomplete prefix or desk stem.
    /// Trailing period / “What’s.” still holds. Complete asks do not.
    public static func isIncompletePrefix(_ text: String) -> Bool {
        shouldHold(text)
    }

    public static func shouldHold(_ text: String) -> Bool {
        let tokens = wordTokens(text)
        guard !tokens.isEmpty else { return false }
        let stripped = dropLeadingFillers(tokens)
        if stripped.isEmpty { return true }
        if barePrefixes.contains(stripped.joined(separator: " ")) { return true }
        return isDeskStemWithoutPersonOrTopic(stripped)
    }

    /// Returns the text that should become a user turn, or `nil` when held.
    public mutating func accept(
        _ text: String,
        context: DeskContext = .disconnected,
        at now: Date = Date(),
        window: TimeInterval = defaultWindow
    ) -> String? {
        let trimmed = Self.dropLeadingLeftoverStem(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !trimmed.isEmpty else { return nil }

        if let heldAt, now.timeIntervalSince(heldAt) > window {
            heldPrefix = nil
            self.heldAt = nil
        }

        if Self.shouldHold(trimmed) {
            if let held = heldPrefix {
                let combined = Self.stitch(held, onto: trimmed)
                let stem = Self.dropLeadingFillers(combined)
                if Self.shouldHold(stem) {
                    heldPrefix = stem
                    heldAt = now
                    return nil
                }
                heldPrefix = nil
                self.heldAt = nil
                return Self.dropLeadingLeftoverStem(combined)
            }
            heldPrefix = trimmed
            heldAt = now
            return nil
        }

        guard let held = heldPrefix else { return trimmed }
        heldPrefix = nil
        heldAt = nil

        let combined = Self.dropLeadingLeftoverStem(Self.stitch(held, onto: trimmed))
        if Self.isActionableAsk(combined, context: context) {
            return combined
        }
        if Self.isActionableAsk(trimmed, context: context) {
            return trimmed
        }
        return trimmed
    }

    /// Intent + plan after the hold. Held stems have intent `"held"` and no
    /// desk plan — never `"general"`.
    public mutating func decide(
        _ text: String,
        context: DeskContext = .disconnected,
        at now: Date = Date(),
        window: TimeInterval = defaultWindow
    ) -> EarlyFinalDecision {
        guard let accepted = accept(text, context: context, at: now, window: window) else {
            return EarlyFinalDecision(intent: "held", acceptedText: nil, plan: nil)
        }
        let evidence = ConversationPresence.deskEvidence(for: accepted, context: context)
        let classified = VoiceInteractionLog.classify(utterance: accepted, evidence: evidence)
        return EarlyFinalDecision(
            intent: classified.intent,
            acceptedText: accepted,
            plan: ConversationPresence.plan(for: accepted, context: context)
        )
    }

    /// Join a held stem onto a later fragment (“SHA” → “What's SHA”).
    /// A restated full phrase is left as-is.
    public static func stitch(_ held: String, onto incoming: String) -> String {
        let incomingTrim = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incomingTrim.isEmpty else {
            return held.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if leadsWithQuestionFamily(incomingTrim) || startsWithDeskStem(incomingTrim) {
            return incomingTrim
        }
        let heldTrim = stripTrailingPunctuation(
            held.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !heldTrim.isEmpty else { return incomingTrim }
        return "\(heldTrim) \(incomingTrim)"
    }

    public static func isActionableAsk(
        _ text: String,
        context: DeskContext = .disconnected
    ) -> Bool {
        let evidence = ConversationPresence.deskEvidence(for: text, context: context)
        let intent = VoiceInteractionLog.classify(utterance: text, evidence: evidence).intent
        return intent != "general"
    }

    /// Drop a leftover hold-stem / echo-stem that prefixes a real desk ask
    /// in the same final (“What's, give me a summary of …”). Bare leftovers
    /// still hold. Complete asks that *use* What’s / Zero stay intact.
    public static func dropLeadingLeftoverStem(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard let rest = remainderAfterLeadingLeftover(trimmed) else { return trimmed }
        guard remainderIsRealDeskAsk(rest) else { return trimmed }
        return rest
    }

    /// what's / whats / what / when / how's / hm / um / uh — after punctuation strip.
    private static let barePrefixes: Set<String> = [
        "what",
        "whats",
        "when",
        "whens",
        "hows",
        "how about",
        "hows about",
        "hm",
        "hmm",
        "um",
        "uh"
    ]

    /// Incomplete desk stems. Longest first when matching.
    private static let deskStems: [[String]] = [
        ["can", "you", "give", "me", "a", "summary"],
        ["can", "you", "give", "me"],
        ["can", "you", "summarize"],
        ["give", "me", "a", "summary"],
        ["can", "you"],
        ["give", "me"],
        ["summarize"]
    ]

    /// Words that can trail a stem without making it a complete ask.
    private static let trailingGlue: Set<String> = [
        "of", "on", "about", "from", "the", "a", "an",
        "email", "emails", "mail", "message", "thread",
        "latest", "last", "one", "my", "please"
    ]

    private static let leadingFillers: Set<String> = [
        "hm", "hmm", "um", "uh", "oh", "ah", "hey",
        "okay", "ok", "yeah", "yep", "please"
    ]

    private static func isDeskStemWithoutPersonOrTopic(_ tokens: [String]) -> Bool {
        guard let rest = restAfterDeskStem(tokens) else { return false }
        return rest.isEmpty || rest.allSatisfy { trailingGlue.contains($0) }
    }

    private static func startsWithDeskStem(_ raw: String) -> Bool {
        restAfterDeskStem(dropLeadingFillers(wordTokens(raw))) != nil
    }

    private static func remainderAfterLeadingLeftover(_ raw: String) -> String? {
        guard let regex = leftoverStemPrefixRegex else { return nil }
        let ns = raw as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: raw, options: [], range: range),
              match.range.location == 0,
              match.range.length > 0,
              match.range.length < ns.length
        else { return nil }
        let rest = ns.substring(from: match.range.length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    private static func remainderIsRealDeskAsk(_ rest: String) -> Bool {
        guard !shouldHold(rest) else { return false }
        let tokens = dropLeadingFillers(wordTokens(rest))
        if restAfterDeskStem(tokens) != nil {
            return !isDeskStemWithoutPersonOrTopic(tokens)
        }
        if tokens.starts(with: ["how", "about"]) || tokens.starts(with: ["what", "about"]) {
            return true
        }
        return false
    }

    private static let leftoverStemPrefixRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^(?:what['’`]s|whats|what|voice|hm+|zero|oh)\b[,.\u2026]?\s+"#,
        options: [.caseInsensitive]
    )

    private static func restAfterDeskStem(_ tokens: [String]) -> [String]? {
        for stem in deskStems where tokens.starts(with: stem) {
            return Array(tokens.dropFirst(stem.count))
        }
        return nil
    }

    static func dropLeadingFillers(_ raw: String) -> String {
        dropLeadingFillers(wordTokens(raw)).joined(separator: " ")
    }

    private static func dropLeadingFillers(_ tokens: [String]) -> [String] {
        var result = tokens
        while let first = result.first, leadingFillers.contains(first) {
            result.removeFirst()
        }
        return result
    }

    private static func wordTokens(_ raw: String) -> [String] {
        var prepared = raw.lowercased()
        prepared = prepared.replacingOccurrences(of: "'", with: "")
        prepared = prepared.replacingOccurrences(of: "’", with: "")
        prepared = prepared.replacingOccurrences(of: "`", with: "")
        var tokens: [String] = []
        var current = ""
        for character in prepared {
            if character.isLetter {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func leadsWithQuestionFamily(_ raw: String) -> Bool {
        guard let first = wordTokens(raw).first else { return false }
        return ["what", "whats", "when", "whens", "how", "hows"].contains(first)
    }

    private static func stripTrailingPunctuation(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(trailingPunctuation))
    }

    private static let trailingPunctuation = CharacterSet(charactersIn: ".!?,;:…")
}

public struct EarlyFinalDecision: Equatable, Sendable {
    public var intent: String
    public var acceptedText: String?
    public var plan: ConversationPresence.Plan?

    public var isHeld: Bool { acceptedText == nil }

    public init(intent: String, acceptedText: String?, plan: ConversationPresence.Plan?) {
        self.intent = intent
        self.acceptedText = acceptedText
        self.plan = plan
    }
}
