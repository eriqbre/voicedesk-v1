import Foundation

/// Spoken presence: a person, not a command menu.
/// Cards attach only when the ask maps to desk evidence.
public enum ConversationPresence {
    public static let welcomeText =
        "Hey — I’m here. Talk like you would to someone who already knows your day. Ask me anything. If it’s about your desk, I’ll put the proof on a card."

    public static let tourOffer = "Sure, show me"

    public enum Topic: String, Sendable, Equatable {
        case inbox
        case listing
        case draft
        case statute
        case google
        case general
    }

    public struct Plan: Equatable, Sendable {
        public let topic: Topic
        public let text: String

        public var attachesCards: Bool { topic != .general }

        public init(topic: Topic, text: String) {
            self.topic = topic
            self.text = text
        }
    }

    public static func plan(for raw: String) -> Plan {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        if contains(lower, ["inbox", "my email", "my mail", "jordan hale", "jordan wrote"])
            || (contains(lower, ["email", "mail"]) && contains(lower, ["my", "inbox", "jordan"])) {
            return Plan(
                topic: .inbox,
                text: "Jordan wrote this morning about Saturday at Beach Drive. Here’s the thread — sample desk data, not live Gmail yet."
            )
        }

        if contains(lower, ["beach drive", "1842", "my listing", "the listing", "showing saturday", "the house"])
            || (contains(lower, ["listing", "showing"]) && !contains(lower, ["list the"])) {
            return Plan(
                topic: .listing,
                text: "1842 Beach Drive — I have it as inferred yours from that thread. People on it are on the card."
            )
        }

        if contains(lower, ["draft a reply", "reply to jordan", "send that", "write him back", "write her back"])
            || (contains(lower, ["reply", "draft"]) && contains(lower, ["email", "jordan", "send"])) {
            return Plan(
                topic: .draft,
                text: "Here’s exactly what I’d send. Nothing leaves until you confirm."
            )
        }

        if contains(lower, ["statute", "florida law", "disclosure", "475.278", "brokerage relationship"])
            || (contains(lower, ["legal", "compliance"]) && contains(lower, ["florida", "law", "disclosure"])) {
            return Plan(
                topic: .statute,
                text: "Florida wants the brokerage relationship on the table before you show as a single agent. Confidence is on the card — I’m not your lawyer."
            )
        }

        if contains(lower, ["connect google", "sign in with google", "sign into google"]) {
            return Plan(
                topic: .google,
                text: "Google is how I actually know your inbox, calendar, and tasks. Connect when you’re ready — it’s stubbed here."
            )
        }

        return Plan(topic: .general, text: generalReply(for: text, lower: lower))
    }

    public static func cards(for topic: Topic, googleConnected: Bool) -> [ContentCard] {
        switch topic {
        case .inbox:
            return [.email(SampleData.email()), .person(SampleData.buyer())]
        case .listing:
            return [.listing(SampleData.listing()), .person(SampleData.buyer()), .person(SampleData.partner())]
        case .draft:
            return [.draftConfirm(SampleData.draftReply())]
        case .statute:
            return [.statute(SampleData.statute())]
        case .google:
            return [.connectGoogle(SampleData.connectGoogle(isConnected: googleConnected))]
        case .general:
            return []
        }
    }

    public static func wantsTour(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower == tourOffer.lowercased() { return true }
        return contains(lower, ["show me around", "sure, show me", "give me a tour", "the tour", "start the tour"])
    }

    private static func generalReply(for text: String, lower: String) -> String {
        if contains(lower, ["weather", "rain", "storm"]) {
            return "Tampa Bay this time of year I’d plan on warm, with a late storm always in the mix — glance before you leave for a showing. What else?"
        }
        if contains(lower, ["dinner", "lunch", "eat", "food", "hungry"]) {
            return "After a day in the car I’d keep it simple — something you don’t have to think about. I’m here either way."
        }
        if contains(lower, ["how are you", "how's it going", "how’re you"]) {
            return "I’m good — I’m right here. What’s going on?"
        }
        if contains(lower, ["joke"]) {
            return "Why did the listing go to therapy? Too many attachments. I’m kidding — what’s actually on your mind?"
        }
        if contains(lower, ["calendar", "schedule", "task", "todo"]) {
            return "I don’t have your live calendar yet. Once Google is connected I will — until then I’ll just talk it through with you. What are you trying to fit in?"
        }
        if text.isEmpty {
            return "I’m here. Say anything."
        }
        return "I’m with you. I’ll talk this through like a person — no menu, no mode to pick. If it ties to your desk I’ll pin the evidence; otherwise we can just keep going."
    }

    private static func contains(_ lower: String, _ keys: [String]) -> Bool {
        keys.contains { lower.contains($0) }
    }
}
