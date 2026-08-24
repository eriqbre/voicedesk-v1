import Foundation

/// Planned Gmail `q=` variants plus tokens used to rank fetched messages.
public struct GmailSearchPlan: Equatable, Sendable {
    public var variants: [String]
    public var senders: [String]
    public var phrases: [String]
    public var subjectTokens: [String]

    public init(
        variants: [String],
        senders: [String] = [],
        phrases: [String] = [],
        subjectTokens: [String] = []
    ) {
        self.variants = variants
        self.senders = senders
        self.phrases = phrases
        self.subjectTokens = subjectTokens
    }

    public var primary: String? { variants.first }
}

public enum GmailSearchPick: Equatable, Sendable {
    case none
    case one(EmailItem)
    case several([EmailItem])
}

/// Builds a Gmail `q=` string from a spoken ask. Pure — Linux-testable.
public enum GmailSearchQuery: Sendable {
    public static let stop: Set<String> = [
        "the", "and", "for", "from", "you", "your", "this", "that", "can",
        "email", "emails", "mail", "note", "notes", "message", "thread", "with", "about",
        "inbox", "details", "body", "read", "show", "latest", "other", "have",
        "today", "what", "whats", "me", "my", "a", "an", "please", "hey",
        "summarize", "summary", "pull", "open", "full", "entire", "whole",
        "earlier", "messages", "conversation", "it", "to", "do", "does",
        "did", "tell", "more", "looking", "see", "any", "ones", "find",
        "look", "search", "get", "need", "want", "check", "something",
        "anything", "send", "sent", "wrote", "write", "has", "been",
        "there", "here", "just", "also", "them", "his", "her", "their",
        "seeing", "cards", "card", "where", "last", "first", "give",
        "gave", "got", "asked", "ask", "could", "would", "should",
        "of", "in", "on", "up", "out", "into", "over", "than", "then",
        "most", "recent", "by", "who", "whom",
        // Question / auxiliary words. Never a first name before “X’s last email”.
        "when", "was", "were", "how", "why",
        // Conversational filler before “how about X’s latest email”.
        "okay", "ok", "perfect", "alright",
        // Calendar overview words. “What’s the latest on my calendar?” is not from:calendar.
        "calendar", "schedule", "week", "upcoming", "meetings"
    ]

    /// Sender-name match required before we attach a card for a named ask.
    public static let senderAttachThreshold = 80
    public static let subjectAttachThreshold = 25
    public static let closeScoreGap = 25
    /// One-edit names (Lauren / Laren) still attach when that sender is present.
    public static let senderFuzzyMaxEdits = 1
    public static let senderFuzzyMinLength = 4

    /// `nil` when the ask has no searchable tokens (e.g. “summarize the full thread”).
    public static func query(from raw: String) -> String? {
        plan(from: raw)?.primary
    }

    public static func plan(from raw: String, treatAsBrand: Bool = false) -> GmailSearchPlan? {
        var senders: [String] = []
        var phrases: [String] = []
        var subjects: [String] = []
        var seen = Set<String>()

        func rememberSender(_ rawName: String) {
            let token = sanitize(rawName)
            guard token.count >= 3, !stop.contains(token) else { return }
            guard !seen.contains(token) else { return }
            seen.insert(token)
            senders.append(token)
        }

        func rememberPhrase(_ rawPhrase: String) {
            let words = rawPhrase
                .lowercased()
                .split { !$0.isLetter }
                .map(String.init)
                .filter { $0.count >= 2 && !stop.contains($0) }
            guard !words.isEmpty else { return }
            let phrase = words.joined(separator: " ")
            if !phrases.contains(phrase) {
                phrases.append(phrase)
            }
            rememberSender(words[0])
        }

        func rememberSubject(_ rawWord: String) {
            let token = sanitize(rawWord)
            guard token.count >= 3, !stop.contains(token) else { return }
            guard !seen.contains("sub:\(token)") else { return }
            seen.insert("sub:\(token)")
            subjects.append(token)
        }

        if let regex = try? NSRegularExpression(pattern: #"from:([^\s]+)"#) {
            for match in regex.matches(in: raw.lowercased(), range: NSRange(raw.startIndex..., in: raw.lowercased())) {
                if let range = Range(match.range(at: 1), in: raw.lowercased()) {
                    rememberSender(String(raw.lowercased()[range]))
                }
            }
        }

        if let phrase = fromSpokenPhrase(in: raw) {
            rememberPhrase(phrase)
        }

        if let aboutName = nameAfterHowOrWhatAbout(in: raw) {
            rememberPhrase(aboutName)
        }

        if compactLetters(raw).contains("showingtime") {
            rememberPhrase("showing time")
        }

        if treatAsBrand, let brand = spokenBrandPhrase(in: raw) {
            rememberPhrase(brand)
        }

        // Name + mail verb (“Murray send/email me”). Never bare did|has|have|find|get + Name.
        if let regex = try? NSRegularExpression(
            pattern: #"\b([A-Za-z]{3,})\s+(?:send|sent|sends|wrote|write|email|emailed|mails|mailed)\b"#
        ) {
            let lower = raw.lowercased()
            for match in regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
                if let range = Range(match.range(at: 1), in: lower) {
                    rememberSender(String(lower[range]))
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"\b(?:email|mail|note|message|thread)\s+about\s+(.+)$"#) {
            let lower = raw.lowercased()
            if let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let range = Range(match.range(at: 1), in: lower) {
                for token in letterTokens(in: String(lower[range])) {
                    rememberSubject(token)
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"\bre:\s*([A-Za-z].+)$"#) {
            let lower = raw.lowercased()
            if let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let range = Range(match.range(at: 1), in: lower) {
                for token in letterTokens(in: String(lower[range])) {
                    rememberSubject(token)
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"\b([A-Za-z]{3,})['’]s\b"#) {
            let ns = NSRange(raw.startIndex..., in: raw)
            if let match = regex.firstMatch(in: raw, range: ns),
               let possRange = Range(match.range(at: 1), in: raw) {
                let possessive = String(raw[possRange])
                // Immediate word only — “Steve Brown's” keeps the pair.
                // letterTokens would skip “of”/“was” and glue “quick”/“when”
                // into from:("quick murray") / from:("was murray").
                let before = immediateLetterWord(before: possRange.lowerBound, in: raw)
                if let before, isPossessiveNamePrefix(before) {
                    rememberPhrase("\(before) \(possessive)")
                } else {
                    rememberSender(possessive)
                }
                let after = letterTokens(in: String(raw[possRange.upperBound...]))
                for token in after.prefix(2) {
                    rememberSubject(token)
                }
            }
        }

        let variants = variantQueries(senders: senders, phrases: phrases, subjects: subjects)
        guard !variants.isEmpty else { return nil }
        return GmailSearchPlan(
            variants: variants,
            senders: senders,
            phrases: phrases,
            subjectTokens: subjects
        )
    }

    public static func hasSenderPattern(_ raw: String) -> Bool {
        guard let plan = plan(from: raw) else { return false }
        return !plan.senders.isEmpty || plan.phrases.contains(where: { $0.contains(" ") })
    }

    /// True when the ask names a sender and this email is not that sender.
    public static func namedSenderMismatches(_ email: EmailItem?, ask: String) -> Bool {
        guard hasSenderPattern(ask), let email, let plan = plan(from: ask) else { return false }
        switch pick([email], plan: plan) {
        case .none:
            return true
        case .one, .several:
            return false
        }
    }

    public static func score(_ email: EmailItem, ask: String) -> Int {
        guard let plan = plan(from: ask) else { return 0 }
        return score(email, plan: plan)
    }

    public static func score(_ email: EmailItem, plan: GmailSearchPlan) -> Int {
        var total = 0
        let fromHay = "\(email.fromName) \(email.fromEmail)".lowercased()
        let fromCompact = compactLetters(fromHay)
        let subjectHay = email.subject.lowercased()
        let previewHay = email.preview.lowercased()
        let bodyHay = (email.body ?? "").lowercased()

        for phrase in plan.phrases {
            let compact = compactLetters(phrase)
            if fromHay.contains(phrase) { total += 120 }
            if !compact.isEmpty, fromCompact.contains(compact) { total += 100 }
            if subjectHay.contains(phrase) { total += 50 }
            if !compact.isEmpty, compactLetters(subjectHay).contains(compact) { total += 40 }
        }
        for sender in plan.senders {
            if fromHay.contains(sender) { total += 100 }
            if fromCompact.contains(sender) { total += 80 }
            if email.fromEmail.lowercased().contains(sender) { total += 90 }
            if fuzzySenderHit(sender, in: fromHay, compact: fromCompact) { total += 90 }
        }
        for token in plan.subjectTokens {
            if subjectHay.contains(token) { total += 30 }
            if previewHay.contains(token) { total += 10 }
            if bodyHay.contains(token) { total += 8 }
        }
        return total
    }

    public static func pick(_ emails: [EmailItem], ask: String) -> GmailSearchPick {
        guard let plan = plan(from: ask) else { return emails.isEmpty ? .none : .none }
        return pick(emails, plan: plan)
    }

    public static func pick(_ emails: [EmailItem], plan: GmailSearchPlan) -> GmailSearchPick {
        let threshold = plan.senders.isEmpty && plan.phrases.isEmpty
            ? subjectAttachThreshold
            : senderAttachThreshold
        let needsPhrase = plan.phrases.contains(where: { $0.contains(" ") })
        let ranked = emails
            .map { (email: $0, score: score($0, plan: plan)) }
            .sorted { $0.score > $1.score }
        let strong = ranked.filter { item in
            guard item.score >= threshold else { return false }
            if needsPhrase {
                return phraseHit(item.email, plan: plan)
            }
            return true
        }
        guard let best = strong.first else { return .none }
        let close = strong.filter { best.score - $0.score < closeScoreGap }
        if close.count == 1 {
            return .one(best.email)
        }
        return .several(Array(close.prefix(3).map(\.email)))
    }

    /// Mock / test helper: subset of Gmail `q=` (quoted phrases, `from:`, top-level `OR`).
    public static func matches(_ email: EmailItem, gmailQuery query: String) -> Bool {
        splitTopLevelOR(query).contains { matchesAND(email, clause: $0) }
    }

    public static func bareLetterTokens(in query: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for ch in query.lowercased() {
            if ch == "\"" {
                inQuotes.toggle()
                current = ""
                continue
            }
            if inQuotes { continue }
            if ch.isLetter {
                current.append(ch)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens.filter { $0 != "or" && $0 != "from" }
    }

    public static func letterTokens(in raw: String) -> [String] {
        raw.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count >= 3 && !stop.contains($0) }
    }

    /// Words after spoken `from` / `by`, stopping at filler (`email`, `last`, …).
    public static func fromSpokenPhrase(in raw: String) -> String? {
        phraseAfterPreposition(in: raw, prepositions: ["from", "by"])
    }

    /// Bare brand / name after “Who’s it from?” — no `from`/`email` required.
    public static func spokenBrandPhrase(in raw: String) -> String? {
        if let spoken = fromSpokenPhrase(in: raw) { return spoken }
        if compactLetters(raw).contains("showingtime") { return "showing time" }
        var words: [String] = []
        for piece in raw.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }) {
            let token = sanitize(String(piece))
            guard token.count >= 2, !stop.contains(token) else { continue }
            words.append(token)
            if words.count >= 3 { break }
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    private static func variantQueries(senders: [String], phrases: [String], subjects: [String]) -> [String] {
        var variants: [String] = []
        func add(_ query: String) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !variants.contains(trimmed) else { return }
            variants.append(trimmed)
        }

        for phrase in phrases where phrase.contains(" ") {
            let compact = compactLetters(phrase)
            add("from:(\"\(phrase)\") OR (\"\(phrase)\") OR \(compact)")
            add("from:\(compact) OR subject:(\"\(phrase)\") OR \"\(phrase)\"")
        }

        if let sender = senders.first {
            if !subjects.isEmpty {
                add("from:\(sender) \(subjects.joined(separator: " "))")
            }
            add("from:\(sender)")
            add("from:\(sender) OR \(sender)")
        }

        if senders.isEmpty, phrases.isEmpty, !subjects.isEmpty {
            add(subjects.joined(separator: " "))
        }
        return variants
    }

    /// Word immediately before `end` (no skip-over of “of” / “was”).
    private static func immediateLetterWord(before end: String.Index, in raw: String) -> String? {
        var word = ""
        for ch in raw[..<end].reversed() {
            if ch.isLetter {
                word.insert(ch, at: word.startIndex)
            } else if !word.isEmpty {
                break
            }
        }
        return word.isEmpty ? nil : word
    }

    /// True when the token before “X’s” is a real given name, not “was” / “of” / “about”.
    private static func isPossessiveNamePrefix(_ raw: String) -> Bool {
        let token = sanitize(raw)
        return token.count >= 3 && !stop.contains(token)
    }

    /// “How about Murray’s…” / “what about Steve” — skip filler, take the name.
    private static func nameAfterHowOrWhatAbout(in raw: String) -> String? {
        let lower = raw.lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:how|what)\s+about\s+(.+)$"#),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let range = Range(match.range(at: 1), in: lower)
        else { return nil }
        var words: [String] = []
        for piece in lower[range].split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }) {
            let token = sanitize(String(piece))
            guard token.count >= 2 else { continue }
            if stop.contains(token) {
                if !words.isEmpty { break }
                continue
            }
            words.append(token)
            if words.count >= 2 { break }
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    private static func sanitize(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "’s", with: "")
            .filter(\.isLetter)
    }

    private static func compactLetters(_ raw: String) -> String {
        raw.lowercased().filter(\.isLetter)
    }

    private static func phraseAfterPreposition(in raw: String, prepositions: [String]) -> String? {
        let lower = raw.lowercased()
        for preposition in prepositions {
            guard let regex = try? NSRegularExpression(pattern: "\\b\(preposition)\\s+(.+)$"),
                  let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let range = Range(match.range(at: 1), in: lower)
            else { continue }
            var words: [String] = []
            for piece in lower[range].split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }) {
                let token = sanitize(String(piece))
                guard token.count >= 2 else { continue }
                if stop.contains(token) {
                    if !words.isEmpty { break }
                    continue
                }
                words.append(token)
                if words.count >= 3 { break }
            }
            if !words.isEmpty {
                return words.joined(separator: " ")
            }
        }
        return nil
    }

    /// Lauren↔Laren and similar one-edit first names. Does not match Greenacre for murray/lauren.
    public static func fuzzySenderHit(_ sender: String, in fromHay: String, compact fromCompact: String) -> Bool {
        let needle = compactLetters(sender)
        guard needle.count >= senderFuzzyMinLength else { return false }
        if fromHay.contains(sender) || fromCompact.contains(needle) { return false }
        var words: [String] = []
        var current = ""
        for ch in fromHay.lowercased() {
            if ch.isLetter {
                current.append(ch)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        if let local = fromHay.split(separator: "@").first {
            let localLetters = compactLetters(String(local))
            if !localLetters.isEmpty { words.append(localLetters) }
        }
        return words.contains { word in
            word.count >= senderFuzzyMinLength && editDistance(word, needle) <= senderFuzzyMaxEdits
        }
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let left = Array(a)
        let right = Array(b)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }
        if abs(left.count - right.count) > senderFuzzyMaxEdits { return senderFuzzyMaxEdits + 1 }
        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[right.count]
    }

    private static func phraseHit(_ email: EmailItem, plan: GmailSearchPlan) -> Bool {
        let fromHay = "\(email.fromName) \(email.fromEmail)".lowercased()
        let fromCompact = compactLetters(fromHay)
        let subjectHay = email.subject.lowercased()
        let subjectCompact = compactLetters(subjectHay)
        for phrase in plan.phrases where phrase.contains(" ") {
            let compact = compactLetters(phrase)
            if fromHay.contains(phrase) { return true }
            if !compact.isEmpty, fromCompact.contains(compact) { return true }
            if subjectHay.contains(phrase) { return true }
            if !compact.isEmpty, subjectCompact.contains(compact) { return true }
        }
        return false
    }

    private static func splitTopLevelOR(_ query: String) -> [String] {
        var clauses: [String] = []
        var current = ""
        var inQuotes = false
        var index = query.startIndex
        while index < query.endIndex {
            let ch = query[index]
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
                index = query.index(after: index)
                continue
            }
            if !inQuotes {
                let rest = query[index...]
                if rest.uppercased().hasPrefix(" OR ") {
                    let trimmed = current.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { clauses.append(trimmed) }
                    current = ""
                    index = query.index(index, offsetBy: 4)
                    continue
                }
            }
            current.append(ch)
            index = query.index(after: index)
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { clauses.append(trimmed) }
        return clauses
    }

    private static func matchesAND(_ email: EmailItem, clause: String) -> Bool {
        let fromHay = "\(email.fromName) \(email.fromEmail)".lowercased()
        let hay = "\(fromHay) \(email.subject) \(email.preview) \(email.body ?? "")".lowercased()
        let fromCompact = compactLetters(fromHay)
        let hayCompact = compactLetters(hay)
        var fromNeed: [String] = []
        var anyNeed: [String] = []
        var index = clause.startIndex

        func skipWhitespace() {
            while index < clause.endIndex, clause[index].isWhitespace {
                index = clause.index(after: index)
            }
        }
        func readQuoted() -> String? {
            guard index < clause.endIndex, clause[index] == "\"" else { return nil }
            index = clause.index(after: index)
            var text = ""
            while index < clause.endIndex, clause[index] != "\"" {
                text.append(clause[index])
                index = clause.index(after: index)
            }
            if index < clause.endIndex { index = clause.index(after: index) }
            return text
        }
        func readWord() -> String {
            var text = ""
            while index < clause.endIndex, !clause[index].isWhitespace, clause[index] != ")" {
                text.append(clause[index])
                index = clause.index(after: index)
            }
            return text
        }
        func hits(_ needle: String, haystack: String, compactHay: String) -> Bool {
            let lowered = needle.lowercased()
            if haystack.contains(lowered) { return true }
            let compact = compactLetters(lowered)
            return !compact.isEmpty && compactHay.contains(compact)
        }

        while index < clause.endIndex {
            skipWhitespace()
            guard index < clause.endIndex else { break }
            if clause[index] == "(" || clause[index] == ")" {
                index = clause.index(after: index)
                continue
            }
            let rest = clause[index...]
            if rest.lowercased().hasPrefix("or"),
               rest.count == 2 || rest.dropFirst(2).first?.isWhitespace == true {
                index = clause.index(index, offsetBy: 2)
                continue
            }
            let isFrom = rest.lowercased().hasPrefix("from:")
            if isFrom { index = clause.index(index, offsetBy: 5) }
            if let quoted = readQuoted() {
                if isFrom { fromNeed.append(quoted) } else { anyNeed.append(quoted) }
                continue
            }
            let word = readWord()
            guard !word.isEmpty, word.lowercased() != "or" else { continue }
            if isFrom { fromNeed.append(word) } else { anyNeed.append(word) }
        }

        return fromNeed.allSatisfy { hits($0, haystack: fromHay, compactHay: fromCompact) }
            && anyNeed.allSatisfy { hits($0, haystack: hay, compactHay: hayCompact) }
    }
}
