import Foundation

/// Least-privilege Google scopes for slice 2.
/// Read first. Write scopes stay off until a confirmed provider write exists.
public enum GoogleScopes: Sendable {
    public static let gmailReadonly = "https://www.googleapis.com/auth/gmail.readonly"
    public static let calendarReadonly = "https://www.googleapis.com/auth/calendar.readonly"
    public static let tasksReadonly = "https://www.googleapis.com/auth/tasks.readonly"

    public static let readScopes = [gmailReadonly, calendarReadonly, tasksReadonly]

    /// iOS URL scheme: `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`
    public static func reversedClientID(from clientID: String) -> String? {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = ".apps.googleusercontent.com"
        guard trimmed.hasSuffix(suffix) else { return nil }
        let prefix = String(trimmed.dropLast(suffix.count))
        guard !prefix.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(prefix)"
    }
}
