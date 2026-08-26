import Foundation

/// Brief AI / local inbox glance. One short line per email — never a mashed recitation.
///
/// Cards are the on-screen list. Eve speaks one short overview beat — not these
/// lines, a single-email AI summary, or a calendar-overview reprint of the cards.
public enum InboxGlance: Sendable {
    public static let overviewLimit = 5
    public static let snippetLimit = 80
    public static let lineLimit = 90
    /// Allowed on-screen stand-in when cards already list the inbox. Empty is preferred.
    public static let onScreenLeadIn = "Here are the latest."

    /// Spoken inbox-overview beat. Cards stay the list — never recite Name — topic.
    public static func spokenOverviewBeat(count: Int) -> String {
        switch count {
        case 0:
            return ""
        case 1:
            return "Here are your latest."
        default:
            return "Here are your latest \(count)."
        }
    }

    /// Spoken calendar-overview beat. Cards stay the list — never recite titles.
    public static func spokenCalendarOverviewBeat(count: Int) -> String {
        count == 0 ? "" : "Here are your upcoming events."
    }

    public static let systemPrompt = """
        You write a voice-assistant inbox glance. One short line per email, same order.
        Format exactly: Name — action or topic.
        Far shorter than a thread summary. One clause, no greetings, no “please do not reply”, \
        no signatures, no legal footers, no “Hello Bridget”.
        Do not paste subjects or snippets verbatim if they are greetings or do-not-reply chrome.
        Output only the lines, one per email, separated by newlines. No preamble.
        """

    public static func heuristic(_ emails: [EmailItem]) -> String {
        format(lines: Array(emails.prefix(overviewLimit)).map(line(for:)))
    }

    public static func line(for email: EmailItem) -> String {
        let name = glanceName(email.fromName)
        let topic = glanceTopic(email.subject)
        return "\(name) — \(topic)."
    }

    public static func format(lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    public static func userPrompt(for emails: [EmailItem]) -> String {
        Array(emails.prefix(overviewLimit)).enumerated().map { index, email in
            let snippet = shortSnippet(email)
            var parts = [
                "\(index + 1). From: \(email.fromName)",
                "Subject: \(email.subject)"
            ]
            if !snippet.isEmpty {
                parts.append("Snippet: \(snippet)")
            }
            return parts.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    public static func shortSnippet(_ email: EmailItem) -> String {
        sanitizeSnippet(email.preview)
    }

    public static func sanitizeSnippet(_ raw: String) -> String {
        let lines = raw
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isRecitationDump($0) && !isGreetingOnly($0) }
        var text = lines.joined(separator: " ")
        text = text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > snippetLimit {
            text = String(text.prefix(snippetLimit)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return text
    }

    /// Accept AI glance lines, or nil to fall back to the local one-liners.
    public static func acceptedLines(_ raw: String, expectedCount: Int) -> [String]? {
        guard expectedCount > 0 else { return [] }
        var lines = raw
            .split(whereSeparator: \.isNewline)
            .map { stripListPrefix(String($0)) }
            .filter { !$0.isEmpty }
        if lines.count == expectedCount + 1, isGlancePreamble(lines[0]) {
            lines = Array(lines.dropFirst())
        }
        guard lines.count == expectedCount else { return nil }
        var cleaned: [String] = []
        for line in lines {
            let scrubbed = EmailSummary.scrubUIChrome(line)
            if scrubbed.isEmpty || isRecitationDump(scrubbed) || scrubbed.count > lineLimit {
                return nil
            }
            cleaned.append(ensurePeriod(scrubbed))
        }
        return cleaned
    }

    public static func isRecitationDump(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return [
            "please do not reply",
            "please don't reply",
            "do not reply to this",
            "this is an automated",
            "you are receiving this",
            "unsubscribe",
            "view this email in",
            "hello bridget",
            "hi bridget",
            "dear bridget"
        ].contains { lower.contains($0) }
    }

    public static func isMultiline(_ raw: String) -> Bool {
        raw.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2
    }

    /// Chat-bubble copy when email or calendar-overview cards are attached.
    /// Cards **are** the visual. Empty (no bubble) or `onScreenLeadIn` — never the
    /// spoken glance, single-email summary, or calendar “Next up” line.
    /// Clarify / not-found / connect / error / calendar-details replies must still
    /// be passed through as the bubble; they are the message.
    public static func onScreenText(compactCardCount: Int) -> String {
        // Cards already carry the visual. Empty bubble (or `onScreenLeadIn`).
        _ = compactCardCount
        return ""
    }

    /// Same “cards are the visual” rule for one full email card + spoken summary.
    public static func onScreenTextHidingSpokenSummary() -> String {
        onScreenText(compactCardCount: 1)
    }

    /// Inbox glance and calendar overview with event cards: empty bubble.
    /// Details / miss / connect / empty-desk copy stays `evidence.text`.
    public static func onScreenText(for evidence: ConversationPresence.DeskEvidence) -> String {
        if evidence.hidesSpokenSummaryOnScreen {
            return onScreenText(compactCardCount: evidence.cards.count)
        }
        return evidence.text
    }

    /// True for empty / “Here are the latest.” — false if the glance recitation leaked on-screen.
    public static func isShortOnScreenLeadIn(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.contains("\n") { return false }
        if trimmed.contains("—") || trimmed.contains("–") { return false }
        if trimmed.count > 40 { return false }
        let lower = trimmed.lowercased()
        return lower == onScreenLeadIn.lowercased()
            || lower == "here are the latest"
            || lower.hasPrefix("here are")
            || lower.hasPrefix("here's")
    }

    /// Spoken glance leaked into the bubble (two or more Name — topic lines).
    public static func repeatsGlanceLines(_ raw: String) -> Bool {
        let lines = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return false }
        return lines.contains { $0.contains("—") || $0.contains("–") }
    }

    private static func glanceName(_ fromName: String) -> String {
        let name = fromName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Unknown" }
        let lower = name.lowercased()
        let orgHints = [", inc", " inc.", " llc", " ltd", " corp", "properties", "group", "noreply"]
        if name.contains(",") || orgHints.contains(where: { lower.contains($0) }) {
            if let first = name.split(whereSeparator: { $0 == " " || $0 == "," }).first, !first.isEmpty {
                return String(first)
            }
        }
        return name
    }

    private static func glanceTopic(_ subject: String) -> String {
        var topic = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["re:", "fwd:", "fw:"] {
            if topic.lowercased().hasPrefix(prefix) {
                topic = String(topic.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if topic.isEmpty { return "new email" }
        if topic.count > 60 {
            topic = String(topic.prefix(57)).trimmingCharacters(in: .whitespaces) + "…"
        }
        if topic.hasSuffix(".") { topic = String(topic.dropLast()) }
        return topic
    }

    private static func stripListPrefix(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: #"^(?:\d+[\.\)]|[a-zA-Z][\.\)]|[-*•])\s+"#) else {
            return trimmed
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isGreetingOnly(_ raw: String) -> Bool {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.hasPrefix("hey ") || lower.hasPrefix("hi ") || lower.hasPrefix("hello ") {
            return !lower.contains("?") && lower.count < 40
        }
        return false
    }

    private static func isGlancePreamble(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("glance") || lower.contains("recent inbox") || lower.hasPrefix("here")
    }

    private static func ensurePeriod(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            return trimmed
        }
        return trimmed + "."
    }
}

public protocol InboxGlancing: Sendable {
    func glance(_ emails: [EmailItem]) async -> String
}

public struct HeuristicInboxGlancer: InboxGlancing {
    public init() {}

    public func glance(_ emails: [EmailItem]) async -> String {
        InboxGlance.heuristic(emails)
    }
}
