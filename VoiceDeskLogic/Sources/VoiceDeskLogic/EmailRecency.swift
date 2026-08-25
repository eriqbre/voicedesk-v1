import Foundation

/// Recency among compact search / clarify cards. Uses `sentAtLabel` (Today / Yesterday / MMM d).
public enum EmailRecency: Sendable {
    public static func newest(_ emails: [EmailItem], now: Date = Date()) -> EmailItem? {
        newestFirst(emails, now: now).first
    }

    public static func newestFirst(_ emails: [EmailItem], now: Date = Date()) -> [EmailItem] {
        emails.enumerated().sorted { lhs, rhs in
            let left = parsedDate(from: lhs.element.sentAtLabel, now: now)
            let right = parsedDate(from: rhs.element.sentAtLabel, now: now)
            switch (left, right) {
            case let (l?, r?) where l != r:
                return l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// View of today's rows. Never mutates the inbox store.
    public static func fromToday(_ emails: [EmailItem], now: Date = Date()) -> [EmailItem] {
        emails.filter { isFromToday($0, now: now) }
    }

    public static func isFromToday(_ email: EmailItem, now: Date = Date()) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        guard let date = parsedDate(from: email.sentAtLabel, now: now) else { return false }
        return calendar.isDate(date, inSameDayAs: now)
    }

    public static func parsedDate(from label: String, now: Date = Date()) -> Date? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "recently" else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("today") {
            return combine(day: now, timeText: String(trimmed.dropFirst(5)), calendar: calendar)
        }
        if lower.hasPrefix("yesterday") {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return combine(day: yesterday, timeText: String(trimmed.dropFirst(9)), calendar: calendar)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        for format in ["MMM d h:mm a", "MMM d ha", "MMM d"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: trimmed) {
                var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
                parts.year = calendar.component(.year, from: now)
                return calendar.date(from: parts)
            }
        }
        return nil
    }

    private static func combine(day: Date, timeText: String, calendar: Calendar) -> Date {
        let time = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !time.isEmpty else { return day }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        for format in ["h:mm a", "ha", "h a"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: time) {
                var parts = calendar.dateComponents([.year, .month, .day], from: day)
                let clock = calendar.dateComponents([.hour, .minute], from: parsed)
                parts.hour = clock.hour
                parts.minute = clock.minute
                return calendar.date(from: parts) ?? day
            }
        }
        return day
    }
}
