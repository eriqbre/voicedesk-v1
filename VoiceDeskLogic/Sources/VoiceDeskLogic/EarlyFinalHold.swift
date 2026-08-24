import Foundation

/// ASR sometimes finalizes a lone question-word before the rest of the utterance.
/// That prefix is not a user turn: hold it, wait for the rest, then classify the
/// full phrase. Never send a bare “what’s” to live Grok.
///
/// Do **not** mute the mic. A silent hold is enough; a later partial/final
/// completes the ask. If nothing more arrives, drop the prefix.
public struct EarlyFinalHold: Equatable, Sendable {
    public var heldPrefix: String?

    public init() {}

    public mutating func reset() {
        heldPrefix = nil
    }

    /// Whole utterance is only an incomplete prefix family member.
    /// Trailing period / “What’s.” still holds. Complete asks do not.
    public static func isIncompletePrefix(_ text: String) -> Bool {
        let key = bareKey(text)
        return !key.isEmpty && barePrefixes.contains(key)
    }

    /// Returns the text that should become a user turn, or `nil` when held.
    public mutating func accept(
        _ text: String,
        context: DeskContext = .disconnected
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if Self.isIncompletePrefix(trimmed) {
            heldPrefix = trimmed
            return nil
        }

        guard let held = heldPrefix else { return trimmed }
        heldPrefix = nil

        if Self.isActionableAsk(trimmed, context: context) {
            return trimmed
        }
        let combined = Self.stitch(held, onto: trimmed)
        if Self.isActionableAsk(combined, context: context) {
            return combined
        }
        return trimmed
    }

    /// Intent + plan after the hold. Held prefixes have intent `"held"` and no
    /// desk plan — never `"general"`.
    public mutating func decide(
        _ text: String,
        context: DeskContext = .disconnected
    ) -> EarlyFinalDecision {
        guard let accepted = accept(text, context: context) else {
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

    /// Join a held prefix onto a later fragment (“SHA” → “What's SHA”).
    /// A restated full phrase is left as-is.
    public static func stitch(_ held: String, onto incoming: String) -> String {
        let incomingTrim = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incomingTrim.isEmpty else {
            return held.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if leadsWithQuestionFamily(incomingTrim) {
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

    /// what's / whats / what / when / how's / how about — after punctuation strip.
    private static let barePrefixes: Set<String> = [
        "what",
        "whats",
        "when",
        "whens",
        "hows",
        "how about",
        "hows about"
    ]

    private static func bareKey(_ raw: String) -> String {
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
        return tokens.joined(separator: " ")
    }

    private static func leadsWithQuestionFamily(_ raw: String) -> Bool {
        let key = bareKey(raw)
        guard let first = key.split(separator: " ").first else { return false }
        return ["what", "whats", "when", "whens", "how", "hows"].contains(String(first))
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
