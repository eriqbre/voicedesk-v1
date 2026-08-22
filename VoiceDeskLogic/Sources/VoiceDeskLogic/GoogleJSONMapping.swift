import Foundation

/// Maps Gmail / Calendar / Tasks JSON into desk cards. Pure — Linux-testable.
public enum GoogleJSONMapping: Sendable {
    public static func emails(fromMessagesJSON data: Data, now: Date = Date()) throws -> [EmailItem] {
        let root = try object(data)
        let rows = root["messages"] as? [[String: Any]] ?? []
        let items = rows.compactMap { email(from: $0, now: now) }
        return GoogleItemDedupe.emails(items)
    }

    public static func events(fromCalendarJSON data: Data, now: Date = Date()) throws -> [CalendarItem] {
        let root = try object(data)
        let rows = root["items"] as? [[String: Any]] ?? []
        let items = rows.compactMap { event(from: $0, now: now) }
        return GoogleItemDedupe.events(items)
    }

    public static func tasks(fromTasksJSON data: Data) throws -> [TaskItem] {
        let root = try object(data)
        let rows = root["items"] as? [[String: Any]] ?? []
        let items = rows.compactMap { task(from: $0) }.filter { !$0.isCompleted }
        return GoogleItemDedupe.tasks(items)
    }

    public static func email(from message: [String: Any], now: Date = Date()) -> EmailItem? {
        let id = string(message["id"])
        guard let id, !id.isEmpty else { return nil }
        let headers = headerMap(message)
        let fromRaw = headers["from"] ?? ""
        let parsed = parseFrom(fromRaw)
        let subject = decodeHTMLEntities(headers["subject"] ?? "(no subject)")
        let snippet = decodeHTMLEntities(string(message["snippet"]) ?? "")
        let dateLabel = sentLabel(headers["date"], internalDate: string(message["internalDate"]), now: now)
        let body = plainTextBody(from: message)
        return EmailItem(
            providerID: id,
            threadID: string(message["threadId"]) ?? id,
            fromName: decodeHTMLEntities(parsed.name),
            fromEmail: parsed.email,
            sentAtLabel: dateLabel,
            subject: subject,
            preview: snippet,
            body: body,
            filterTag: "Inbox"
        )
    }

    /// Gmail snippets encode quotes as `&quot;`. Decode named + numeric entities.
    public static func decodeHTMLEntities(_ raw: String) -> String {
        var result = raw
        let numeric = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|\d+);"#)
        if let numeric {
            let matches = numeric.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let whole = Range(match.range, in: result),
                      let valueRange = Range(match.range(at: 1), in: result)
                else { continue }
                let token = String(result[valueRange])
                let scalar: UInt32?
                if token.lowercased().hasPrefix("x") {
                    scalar = UInt32(token.dropFirst(), radix: 16)
                } else {
                    scalar = UInt32(token)
                }
                if let scalar, let char = UnicodeScalar(scalar) {
                    result.replaceSubrange(whole, with: String(Character(char)))
                }
            }
        }
        let named: [(String, String)] = [
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " "),
            ("&amp;", "&")
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
            result = result.replacingOccurrences(of: entity.uppercased(), with: replacement)
        }
        return result
    }

    public static func decodeBase64URL(_ raw: String) -> Data? {
        var encoded = raw
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - encoded.count % 4) % 4
        encoded += String(repeating: "=", count: pad)
        return Data(base64Encoded: encoded)
    }

    /// Walk a `users.messages.get` `format=full` payload. Returns nil if no body is present.
    public static func plainTextBody(from message: [String: Any]) -> String? {
        guard let payload = message["payload"] as? [String: Any] else { return nil }
        if let text = firstPart(payload, mime: "text/plain") {
            return decodeHTMLEntities(collapseWhitespace(text))
        }
        if let html = firstPart(payload, mime: "text/html") {
            return decodeHTMLEntities(collapseWhitespace(stripHTMLTags(html)))
        }
        return nil
    }

    public static func event(from item: [String: Any], now: Date = Date()) -> CalendarItem? {
        let id = string(item["id"])
        guard let id, !id.isEmpty else { return nil }
        let title = string(item["summary"]).flatMap { $0.isEmpty ? nil : $0 } ?? "(no title)"
        let start = item["start"] as? [String: Any]
        let startDate = parseGoogleDate(start)
        let attendees = ((item["attendees"] as? [[String: Any]]) ?? []).compactMap { row -> String? in
            if let name = string(row["displayName"]), !name.isEmpty { return name }
            return string(row["email"])
        }
        return CalendarItem(
            providerID: id,
            title: title,
            whenLabel: whenLabel(startDate, raw: start, now: now),
            location: string(item["location"]),
            relatedPeople: attendees,
            startAt: startDate
        )
    }

    public static func task(from item: [String: Any]) -> TaskItem? {
        let id = string(item["id"])
        guard let id, !id.isEmpty else { return nil }
        let title = string(item["title"]).flatMap { $0.isEmpty ? nil : $0 } ?? "(untitled task)"
        let status = string(item["status"]) ?? ""
        return TaskItem(
            providerID: id,
            title: title,
            dueLabel: dueLabel(string(item["due"])),
            notes: string(item["notes"]),
            isCompleted: status == "completed"
        )
    }

    public static func parseFrom(_ raw: String) -> (name: String, email: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "<"), let end = trimmed.firstIndex(of: ">"), start < end {
            let email = String(trimmed[trimmed.index(after: start)..<end]).trimmingCharacters(in: .whitespaces)
            let name = String(trimmed[..<start])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return (name.isEmpty ? email : name, email)
        }
        if trimmed.contains("@") {
            return (trimmed, trimmed)
        }
        return (trimmed.isEmpty ? "Unknown" : trimmed, "")
    }

    public static func draftReply(to email: EmailItem) -> DraftConfirmItem {
        let to = email.fromEmail.isEmpty
            ? email.fromName
            : "\(email.fromName) <\(email.fromEmail)>"
        let subject = email.subject.lowercased().hasPrefix("re:")
            ? email.subject
            : "Re: \(email.subject)"
        return DraftConfirmItem(
            actionTitle: "Send reply",
            channel: "Gmail",
            toLine: to,
            subject: subject,
            body: "Thanks — I’ll follow up shortly."
        )
    }

    public static func draftCalendarCreate(title: String, whenLabel: String) -> DraftConfirmItem {
        DraftConfirmItem(
            actionTitle: "Create calendar event",
            channel: "Calendar",
            toLine: "Primary calendar",
            subject: title,
            body: whenLabel
        )
    }

    public static func draftTaskCreate(title: String) -> DraftConfirmItem {
        DraftConfirmItem(
            actionTitle: "Create task",
            channel: "Tasks",
            toLine: "My Tasks",
            subject: title,
            body: title
        )
    }

    private static func headerMap(_ message: [String: Any]) -> [String: String] {
        let payload = message["payload"] as? [String: Any]
        let headers = payload?["headers"] as? [[String: Any]] ?? []
        var map: [String: String] = [:]
        for header in headers {
            guard let name = string(header["name"])?.lowercased(), let value = string(header["value"]) else {
                continue
            }
            map[name] = value
        }
        return map
    }

    private static func sentLabel(_ dateHeader: String?, internalDate: String?, now: Date) -> String {
        if let millis = internalDate.flatMap({ Double($0) }) {
            let date = Date(timeIntervalSince1970: millis / 1000)
            return relativeDay(date, now: now)
        }
        if let dateHeader, let parsed = rfc2822(dateHeader) {
            return relativeDay(parsed, now: now)
        }
        return dateHeader ?? "Recently"
    }

    private static func relativeDay(_ date: Date, now: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let time = DeskSnapshot.timeLabel(date)
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today \(time)"
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        if calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: date)) \(time)"
    }

    private static func parseGoogleDate(_ start: [String: Any]?) -> Date? {
        guard let start else { return nil }
        if let dateTime = string(start["dateTime"]) {
            return iso8601(dateTime)
        }
        if let date = string(start["date"]) {
            return dayDate(date)
        }
        return nil
    }

    private static func whenLabel(_ date: Date?, raw: [String: Any]?, now: Date) -> String {
        if let date {
            if raw.flatMap({ string($0["date"]) }) != nil {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "EEE MMM d"
                return formatter.string(from: date)
            }
            return relativeDay(date, now: now)
        }
        return string(raw?["dateTime"]) ?? string(raw?["date"]) ?? "Upcoming"
    }

    private static func dueLabel(_ raw: String?) -> String? {
        guard let raw, let date = iso8601(raw) ?? dayDate(raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date)
    }

    private static func iso8601(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func dayDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    private static func rfc2822(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: raw)
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MappingError.invalidJSON
        }
        return object
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstPart(_ part: [String: Any], mime: String) -> String? {
        if let type = string(part["mimeType"])?.lowercased(), type == mime,
           let data = (part["body"] as? [String: Any]).flatMap({ string($0["data"]) }),
           let decoded = decodeBase64URL(data),
           let text = String(data: decoded, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        let children = part["parts"] as? [[String: Any]] ?? []
        for child in children {
            if let text = firstPart(child, mime: mime) {
                return text
            }
        }
        return nil
    }

    private static func stripHTMLTags(_ html: String) -> String {
        var text = html
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        return text
    }

    private static func collapseWhitespace(_ raw: String) -> String {
        raw.split { $0.isNewline || $0.isWhitespace }.joined(separator: " ")
    }

    public enum MappingError: Error, Sendable {
        case invalidJSON
    }
}

public enum GoogleItemDedupe: Sendable {
    public static func emails(_ items: [EmailItem]) -> [EmailItem] {
        unique(items) { $0.threadID ?? $0.providerID ?? $0.id.uuidString }
    }

    public static func events(_ items: [CalendarItem]) -> [CalendarItem] {
        unique(items) { $0.providerID ?? $0.id.uuidString }
    }

    public static func tasks(_ items: [TaskItem]) -> [TaskItem] {
        unique(items) { $0.providerID ?? $0.id.uuidString }
    }

    private static func unique<T>(_ items: [T], key: (T) -> String) -> [T] {
        var seen = Set<String>()
        var result: [T] = []
        for item in items {
            let token = key(item)
            if seen.contains(token) { continue }
            seen.insert(token)
            result.append(item)
        }
        return result
    }
}
