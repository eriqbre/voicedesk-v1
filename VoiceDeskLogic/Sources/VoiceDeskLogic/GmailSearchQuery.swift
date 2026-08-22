import Foundation

/// Builds a Gmail `q=` string from a spoken ask. Pure — Linux-testable.
public enum GmailSearchQuery: Sendable {
    public static let stop: Set<String> = [
        "the", "and", "for", "from", "you", "your", "this", "that", "can",
        "email", "emails", "mail", "note", "message", "thread", "with", "about",
        "inbox", "details", "body", "read", "show", "latest", "other", "have",
        "today", "what", "whats", "me", "my", "a", "an", "please", "hey",
        "summarize", "summary", "pull", "open", "full", "entire", "whole",
        "earlier", "messages", "conversation", "it", "to", "do", "does",
        "did", "tell", "more", "looking", "see", "any", "ones"
    ]

    /// `nil` when the ask has no searchable tokens (e.g. “summarize the full thread”).
    public static func query(from raw: String) -> String? {
        let lower = raw.lowercased()
        var clauses: [String] = []
        var seen = Set<String>()

        func addFrom(_ rawName: String) {
            let token = sanitize(rawName)
            guard token.count >= 3, !stop.contains(token) else { return }
            guard !seen.contains(token) else { return }
            seen.insert(token)
            clauses.append("from:\(token)")
        }

        func addWord(_ rawWord: String) {
            let token = sanitize(rawWord)
            guard token.count >= 3, !stop.contains(token) else { return }
            guard !seen.contains(token) else { return }
            seen.insert(token)
            clauses.append(token)
        }

        if let regex = try? NSRegularExpression(pattern: #"from:([^\s]+)"#) {
            for match in regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
                if let range = Range(match.range(at: 1), in: lower) {
                    addFrom(String(lower[range]))
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"\bfrom\s+([A-Za-z][A-Za-z''-]+)"#) {
            for match in regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
                if let range = Range(match.range(at: 1), in: raw) {
                    addFrom(String(raw[range]))
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"\b([A-Za-z]{3,})'s\b"#) {
            let ns = NSRange(raw.startIndex..., in: raw)
            if let match = regex.firstMatch(in: raw, range: ns),
               let possRange = Range(match.range(at: 1), in: raw) {
                let possessive = String(raw[possRange])
                let before = letterTokens(in: String(raw[..<possRange.lowerBound])).last
                if let before, !stop.contains(sanitize(before)) {
                    addFrom(before)
                    addWord(possessive)
                } else {
                    addFrom(possessive)
                }
            }
        }

        for token in letterTokens(in: lower) {
            addWord(token)
        }

        return clauses.isEmpty ? nil : clauses.joined(separator: " ")
    }

    public static func letterTokens(in raw: String) -> [String] {
        raw.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count >= 3 && !stop.contains($0) }
    }

    private static func sanitize(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "’s", with: "")
            .filter(\.isLetter)
    }
}
