import Foundation

/// Readable latest-message extraction for Gmail MIME parts.
/// Default view is the newest reply; quoted history is available separately.
public enum EmailBodyFormatting: Sendable {
    public struct Extracted: Equatable, Sendable {
        public var latestPlain: String?
        public var latestHTML: String?
        public var earlierFromQuotes: [EmailThreadMessage]

        public init(
            latestPlain: String? = nil,
            latestHTML: String? = nil,
            earlierFromQuotes: [EmailThreadMessage] = []
        ) {
            self.latestPlain = latestPlain
            self.latestHTML = latestHTML
            self.earlierFromQuotes = earlierFromQuotes
        }
    }

    public static func extracted(
        from message: [String: Any],
        includeQuotedAsEarlier: Bool = true
    ) -> Extracted {
        let payload = message["payload"] as? [String: Any]
        let htmlRaw = payload.flatMap { firstPart($0, mime: "text/html") }
        let plainRaw = payload.flatMap { firstPart($0, mime: "text/plain") }

        let sanitized = htmlRaw.map(sanitizeHTML)
        let htmlSplit = sanitized.map(splitQuotedHTML)
        var latestHTML = htmlSplit?.latest
        let quotedHTML = htmlSplit?.quoted

        let readableFromHTML = latestHTML.flatMap(htmlToReadablePlain)
            ?? sanitized.flatMap(htmlToReadablePlain)
        let readableFromPlain = plainRaw.map(cleanPlainText)

        let latestFromHTML = readableFromHTML.flatMap { splitQuotedReply($0).latest }
        let plainSplit = (readableFromPlain ?? "").isEmpty ? nil : splitQuotedReply(readableFromPlain ?? "")
        var latestPlain = nonempty(latestFromHTML) ?? nonempty(plainSplit?.latest)
        let quotedPlain = nonempty(quotedHTML.flatMap(htmlToReadablePlain))
            ?? nonempty(plainSplit?.quoted)

        if latestHTML != nil, quotedHTML == nil, quotedPlain != nil {
            latestHTML = nil
        }
        if latestPlain == nil, let html = latestHTML {
            latestPlain = htmlToReadablePlain(html)
        }

        var earlier: [EmailThreadMessage] = []
        if includeQuotedAsEarlier, let quotedPlain {
            let messageID = (message["id"] as? String) ?? UUID().uuidString
            earlier.append(
                EmailThreadMessage(
                    id: "quoted-\(messageID)",
                    fromName: "Earlier in the thread",
                    htmlBody: quotedHTML,
                    plainBody: quotedPlain
                )
            )
        }

        return Extracted(
            latestPlain: latestPlain,
            latestHTML: nonempty(latestHTML),
            earlierFromQuotes: earlier
        )
    }

    public static func sanitizeHTML(_ html: String) -> String {
        var text = html
        let blocks = ["script", "iframe", "object", "embed", "style"]
        for tag in blocks {
            if let regex = try? NSRegularExpression(
                pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                options: .caseInsensitive
            ) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: ""
                )
            }
        }
        if let events = try? NSRegularExpression(
            pattern: #"\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
            options: .caseInsensitive
        ) {
            text = events.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        return text
    }

    public static func htmlToReadablePlain(_ html: String) -> String? {
        var text = sanitizeHTML(html)
        let newlines = [
            #"</p>"#, #"</div>"#, #"</tr>"#, #"</h[1-6]>"#, #"<br\s*/?>"#, #"</li>"#, #"</blockquote>"#
        ]
        for pattern in newlines {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: "\n"
                )
            }
        }
        if let tags = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = tags.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        return nonempty(cleanPlainText(text))
    }

    public static func cleanPlainText(_ raw: String) -> String {
        let decoded = GoogleJSONMapping.decodeHTMLEntities(raw)
        let kept = decoded
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !isMIMENoise($0) }
            .joined(separator: "\n")
        return normalizeParagraphs(kept)
    }

    public static func splitQuotedReply(_ plain: String) -> (latest: String?, quoted: String?) {
        let lines = plain.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var cut: Int?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if isQuoteAttribution(trimmed) || isQuotePrefixLine(trimmed) || isOriginalMessageSeparator(trimmed) {
                cut = index
                break
            }
        }
        guard let cut else {
            return (nonempty(normalizeParagraphs(plain)), nil)
        }
        let latest = nonempty(normalizeParagraphs(lines[..<cut].joined(separator: "\n")))
        let quoted = nonempty(
            normalizeParagraphs(
                lines[cut...].map(stripQuotePrefix).joined(separator: "\n")
            )
        )
        if latest == nil {
            return (quoted, nil)
        }
        return (latest, quoted)
    }

    public static func splitQuotedHTML(_ html: String) -> (latest: String, quoted: String?) {
        let markers = [
            #"<(div|blockquote)[^>]*class="[^"]*gmail_quote[^"]*"[^>]*>"#,
            #"<blockquote\b"#,
            #"-----Original Message-----"#
        ]
        var earliest: String.Index?
        for pattern in markers {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }
            let range = NSRange(html.startIndex..., in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  let swiftRange = Range(match.range, in: html)
            else { continue }
            if earliest == nil || swiftRange.lowerBound < earliest! {
                earliest = swiftRange.lowerBound
            }
        }
        guard let cut = earliest, cut > html.startIndex else {
            return (html, nil)
        }
        let latest = String(html[..<cut])
        let quoted = String(html[cut...])
        return (latest, quoted.isEmpty ? nil : quoted)
    }

    public static func spokenSummary(from raw: String?, fallback: String = "") -> String {
        let source = nonempty(raw) ?? fallback
        var text = source
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text = normalizeParagraphs(text)
        guard let first = text.split(whereSeparator: \.isNewline).first else { return "" }
        var sentence = String(first).trimmingCharacters(in: .whitespaces)
        if sentence.count > 140 {
            if let match = sentence.range(of: #"[\.!?]\s"#, options: .regularExpression) {
                sentence = String(sentence[...match.lowerBound])
            }
            if sentence.count > 140 {
                sentence = String(sentence.prefix(140)).trimmingCharacters(in: .whitespaces) + "…"
            }
        }
        return sentence
    }

    public static func looksLikeHTML(_ raw: String) -> Bool {
        raw.range(of: #"</?[a-zA-Z][^>]*>"#, options: .regularExpression) != nil
    }

    static func firstPart(_ part: [String: Any], mime: String) -> String? {
        if let type = string(part["mimeType"])?.lowercased(), type == mime,
           let data = (part["body"] as? [String: Any]).flatMap({ string($0["data"]) }),
           let decoded = GoogleJSONMapping.decodeBase64URL(data),
           let text = String(data: decoded, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        for child in part["parts"] as? [[String: Any]] ?? [] {
            if let text = firstPart(child, mime: mime) {
                return text
            }
        }
        return nil
    }

    private static func normalizeParagraphs(_ raw: String) -> String {
        let lines = raw
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var collapsed: [String] = []
        var blankRun = 0
        for line in lines {
            if line.isEmpty {
                blankRun += 1
                if blankRun <= 1, !collapsed.isEmpty {
                    collapsed.append("")
                }
            } else {
                blankRun = 0
                collapsed.append(line)
            }
        }
        while collapsed.last == "" {
            collapsed.removeLast()
        }
        while collapsed.first == "" {
            collapsed.removeFirst()
        }
        return collapsed.joined(separator: "\n")
    }

    private static func isQuotePrefixLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(">") || trimmed.hasPrefix("&gt;")
    }

    private static func isQuoteAttribution(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.hasPrefix("on ") && lower.contains("wrote")
    }

    private static func isOriginalMessageSeparator(_ line: String) -> Bool {
        line.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespaces).lowercased()
            == "original message"
    }

    private static func stripQuotePrefix(_ line: String) -> String {
        var text = line
        while text.hasPrefix(" ") {
            text.removeFirst()
        }
        while text.hasPrefix(">") || text.hasPrefix("&gt;") {
            if text.hasPrefix("&gt;") {
                text.removeFirst(4)
            } else {
                text.removeFirst()
            }
            if text.hasPrefix(" ") {
                text.removeFirst()
            }
        }
        return text
    }

    private static func isMIMENoise(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("Content-Type:") || trimmed.hasPrefix("Content-Transfer-Encoding:") {
            return true
        }
        if trimmed.count >= 72,
           trimmed.range(of: #"^[A-Za-z0-9+/=]+$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func nonempty(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
