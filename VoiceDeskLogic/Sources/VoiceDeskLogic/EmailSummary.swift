import Foundation

/// One-email summarize for Eve. Full body only — never snippet-as-summary.
public struct EmailSummaryRequest: Equatable, Sendable {
    public var fromName: String
    public var subject: String
    public var body: String
    public var preview: String
    public var earlier: [String]

    public init(
        fromName: String,
        subject: String,
        body: String,
        preview: String = "",
        earlier: [String] = []
    ) {
        self.fromName = fromName
        self.subject = subject
        self.body = body
        self.preview = preview
        self.earlier = earlier
    }

    public static func from(_ email: EmailItem, includeEarlier: Bool) -> EmailSummaryRequest {
        EmailSummaryRequest(
            fromName: email.fromName,
            subject: email.subject,
            body: {
                if let plain = email.body, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return plain
                }
                if let html = email.htmlBody,
                   let readable = EmailBodyFormatting.htmlToReadablePlain(html) {
                    return readable
                }
                return ""
            }(),
            preview: email.preview,
            earlier: includeEarlier
                ? email.earlierMessages.compactMap { message -> String? in
                    let plain = (message.plainBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return plain.isEmpty ? nil : plain
                }
                : []
        )
    }

    public var sourceText: String {
        let primary = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return primary.isEmpty ? preview : primary
    }
}

public protocol EmailSummarizing: Sendable {
    func summarize(_ request: EmailSummaryRequest) async -> String
    func glanceInbox(_ emails: [EmailItem]) async -> String
}

extension EmailSummarizing {
    public func glanceInbox(_ emails: [EmailItem]) async -> String {
        InboxGlance.heuristic(emails)
    }
}

public struct HeuristicEmailSummarizer: EmailSummarizing {
    public init() {}

    public func summarize(_ request: EmailSummaryRequest) async -> String {
        EmailSummary.heuristic(request)
    }
}

/// Grounded email summary + UI-chrome scrub. Grok text path uses the same prompt/scrub.
public enum EmailSummary: Sendable {
    public static let chatCompletionsURL = "https://api.x.ai/v1/chat/completions"
    public static let defaultTextModel = "grok-3-mini"

    public static let systemPrompt = """
        You summarize one email for a voice assistant named Eve.
        Conversational. 3 to 6 sentences. Cover: who wrote it, their intent, \
        every concrete question/ask/deadline/number, and the implied next action.
        If they listed questions, name each one. Use only facts in the email. Never invent.
        Never mention cards, the app UI, “on the card”, “see below”, or “check the card”.
        Do not paste the whole email.
        """

    public static func userPrompt(_ request: EmailSummaryRequest) -> String {
        var parts = [
            "From: \(request.fromName)",
            "Subject: \(request.subject)",
            "Body:",
            request.sourceText
        ]
        if !request.earlier.isEmpty {
            parts.append("Earlier in the thread:")
            parts.append(contentsOf: request.earlier.prefix(3))
        }
        return parts.joined(separator: "\n")
    }

    public static func heuristic(_ request: EmailSummaryRequest) -> String {
        let raw = EmailBodyFormatting.cleanPlainText(request.sourceText)
        let latest = EmailBodyFormatting.splitQuotedReply(raw).latest ?? raw
        let cleaned = scrubUIChrome(latest)
        if cleaned.isEmpty, request.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "I don’t have the body of that email yet, so I’m not inventing a summary."
        }

        let who = request.fromName.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = request.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !who.isEmpty, !subject.isEmpty {
            parts.append("\(who) wrote about \(subject).")
        } else if !who.isEmpty {
            parts.append("\(who) wrote.")
        }

        let questions = extractQuestions(from: cleaned)
        let items = extractListItems(from: cleaned)
        if !questions.isEmpty {
            if questions.count == 1 {
                parts.append("They ask: \(questions[0])")
            } else {
                parts.append("They have \(questions.count) questions: \(joinAnd(questions)).")
            }
        } else if items.count >= 2 {
            parts.append("They want: \(joinAnd(items)).")
        } else {
            let meat = contentSentences(from: cleaned).prefix(3)
            for sentence in meat where !parts.contains(where: { $0.localizedCaseInsensitiveContains(sentence) }) {
                parts.append(sentence)
            }
        }

        if let deadline = deadlinePhrase(in: cleaned),
           !parts.contains(where: { $0.localizedCaseInsensitiveContains(deadline) }) {
            parts.append(deadline)
        }

        if !request.earlier.isEmpty {
            let earlier = EmailBodyFormatting.spokenSummary(
                from: request.earlier.first,
                fallback: "",
                style: .brief
            )
            if !earlier.isEmpty {
                parts.append("Earlier: \(earlier)")
            }
        }

        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let result = scrubUIChrome(joined)
        if result.isEmpty {
            return who.isEmpty
                ? "I have the email, but I’m not inventing what it says."
                : "\(who) wrote, but I don’t have enough of the body to summarize."
        }
        return result
    }

    public static func scrubUIChrome(_ raw: String) -> String {
        var text = raw
        let phrases = [
            "i've put it on a card",
            "i’ve put it on a card",
            "you can see it below",
            "you can see them below",
            "check the card",
            "see the card",
            "see the cards",
            "waiting on the email card",
            "waiting on the card",
            "they're on the cards — which one?",
            "they’re on the cards — which one?",
            "they're on the cards, which one?",
            "they’re on the cards, which one?",
            "they're on the cards",
            "they’re on the cards",
            "on the cards below",
            "on the card below",
            "is on the card.",
            "is on the card",
            "are on the card.",
            "are on the card",
            "on the card.",
            "on the card",
            "on the cards"
        ]
        for phrase in phrases {
            text = text.replacingOccurrences(of: phrase, with: " ", options: [.caseInsensitive])
        }
        text = text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+([,.!?])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"([.!?])\s*[.!?]+"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func containsUIChrome(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return [
            "on the card", "on the cards", "see the card", "check the card",
            "you can see it below", "i've put it on a card", "i’ve put it on a card",
            "waiting on the"
        ].contains { lower.contains($0) }
    }

    public static func chatCompletionContent(from json: [String: Any]) -> String? {
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : scrubUIChrome(trimmed)
    }

    public static func isConnectInstruction(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("tap connect google") || lower.contains("use disconnect")
    }

    private static func extractQuestions(from text: String) -> [String] {
        var found: [String] = []
        for sentence in splitSentences(text) {
            let trimmed = stripListPrefix(sentence)
            guard trimmed.contains("?") else { continue }
            if isGreeting(trimmed), !trimmed.contains("?") { continue }
            found.append(ensurePeriodOrQuestion(trimmed))
        }
        for line in text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let trimmed = stripListPrefix(line)
            if trimmed.hasSuffix("?"), !found.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) {
                found.append(trimmed)
            }
        }
        return uniqued(found).filter { $0.count > 3 && !isGreeting($0) }
    }

    private static func extractListItems(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                line.range(of: #"^(?:\d+[\.\)]|[a-zA-Z][\.\)]|[-*•])\s+\S+"#, options: .regularExpression) != nil
            }
            .map { stripListPrefix($0) }
            .filter { !$0.isEmpty && !isGreeting($0) }
    }

    private static func contentSentences(from text: String) -> [String] {
        splitSentences(text)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !isGreeting($0) && $0.count > 8 }
    }

    private static func deadlinePhrase(in text: String) -> String? {
        let lower = text.lowercased()
        for marker in ["today", "tomorrow", "thursday", "friday", "monday", "3pm", "3 pm", "by "] {
            if lower.contains(marker) {
                if let sentence = splitSentences(text).first(where: { $0.lowercased().contains(marker) }),
                   !isGreeting(sentence) {
                    return sentence
                }
            }
        }
        return nil
    }

    private static func splitSentences(_ text: String) -> [String] {
        let collapsed = text.replacingOccurrences(of: #"\n+"#, with: " ", options: .regularExpression)
        var sentences: [String] = []
        var current = ""
        for character in collapsed {
            current.append(character)
            if "?.".contains(character), current.trimmingCharacters(in: .whitespaces).count >= 8 {
                let piece = current.trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty { sentences.append(piece) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    private static func stripListPrefix(_ line: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^(?:\d+[\.\)]|[a-zA-Z][\.\)]|[-*•])\s+"#) else {
            return line
        }
        let range = NSRange(line.startIndex..., in: line)
        return regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isGreeting(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower.hasPrefix("hey ") || lower.hasPrefix("hi ") || lower.hasPrefix("hello ") {
            return !lower.contains("?")
        }
        return ["thanks", "thank you", "best,", "cheers"].contains { lower == $0 || lower.hasPrefix($0) }
    }

    private static func ensurePeriodOrQuestion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("?") || trimmed.hasSuffix(".") { return trimmed }
        return trimmed
    }

    private static func joinAnd(_ items: [String]) -> String {
        let cleaned = items.map { $0.hasSuffix(".") || $0.hasSuffix("?") ? $0 : $0 }
        if cleaned.count == 2 { return "\(cleaned[0]) and \(cleaned[1])" }
        if cleaned.count > 2 {
            return cleaned.dropLast().joined(separator: " ") + " and " + cleaned.last!
        }
        return cleaned.joined(separator: " ")
    }

    private static func uniqued(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items {
            let key = item.lowercased()
            if seen.insert(key).inserted { out.append(item) }
        }
        return out
    }
}
