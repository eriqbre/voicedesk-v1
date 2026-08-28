import Foundation

/// Brief AI / local inbox glance. One short line per email — never a mashed recitation.
///
/// Cards are the on-screen list. `spokenInbox` is a from/subject dump —
/// 677abb9 DD56F6A9 leftover when that string was the live mouth.
/// Live list/show waits for tools; Eve speaks the real answer. Not this
/// dump. Not empty. Not “Here they are.” Never recite the cards.
public enum InboxGlance: Sendable {
    public static let overviewLimit = 5
    public static let snippetLimit = 80
    public static let lineLimit = 90
    /// Allowed on-screen stand-in when cards already list the inbox. Empty is preferred.
    public static let onScreenLeadIn = "Here are the latest."

    public static func spokenInbox(ask: String, emails: [EmailItem]) -> String {
        let window = Array(emails.prefix(overviewLimit))
        guard !window.isEmpty else { return "" }
        return spokenInboxSummary(window)
    }

    /// One short spoken summary — not five recited Name — topic lines.
    public static func spokenInboxSummary(_ emails: [EmailItem]) -> String {
        let window = Array(emails.prefix(overviewLimit))
        guard !window.isEmpty else { return "" }
        let bits = window.prefix(2).map { "\(glanceName($0.fromName)) on \(glanceTopic($0.subject))" }
        if window.count <= 2 {
            return bits.joined(separator: ", ") + "."
        }
        return bits.joined(separator: ", ") + ", and more."
    }

    public static func spokenCalendar(ask: String, events: [CalendarItem]) -> String {
        guard !events.isEmpty else { return "" }
        return spokenCalendarSummary(events)
    }

    public static func spokenCalendarSummary(_ events: [CalendarItem]) -> String {
        guard let first = events.first else { return "" }
        if events.count == 1 {
            return "\(first.title), \(first.whenLabel)."
        }
        return "\(first.title), \(first.whenLabel), and more."
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
    /// spoken overview beat, single-email summary, or calendar titles.
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
            || lower.hasPrefix("here they")
            || lower.hasPrefix("here you")
    }

    /// List/show spoken ack — short, no card reprint.
    public static func isShortSpokenAck(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("\n") { return false }
        if trimmed.contains("—") || trimmed.contains("–") { return false }
        if trimmed.count > 40 { return false }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("here they")
            || lower.hasPrefix("here you")
            || lower.hasPrefix("here we")
            || lower == "here you go"
            || lower == "here they are"
            || lower == "here you go."
            || lower == "here they are."
    }

    /// 677abb9 DD56F6A9 leftover mouth: "from@x on Subject, Bank on Zelle…, and more."
    /// That string is `spokenInbox` / `spokenInboxSummary`. Not Eve's answer.
    public static func isFromSubjectGlanceDump(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if isShortSpokenAck(trimmed) || isShortOnScreenLeadIn(trimmed) { return false }
        let lower = trimmed.lowercased()
        guard lower.contains(" on ") else { return false }
        if lower.contains(", and more") { return true }
        return trimmed.components(separatedBy: " on ").count >= 3
    }

    /// One-sentence overview summary — not a multiline card recitation.
    public static func isShortSpokenSummary(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if isMultiline(trimmed) || repeatsGlanceLines(trimmed) { return false }
        if isShortSpokenAck(trimmed) || isShortOnScreenLeadIn(trimmed) { return false }
        return trimmed.count <= 160
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
