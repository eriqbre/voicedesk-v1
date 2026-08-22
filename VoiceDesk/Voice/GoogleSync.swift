import Foundation
import VoiceDeskLogic

/// Isolated with `AppModel` so `any GoogleSyncing` never leaves the main actor.
/// `Sendable` is valid because every implementation is `@MainActor`.
@MainActor
protocol GoogleSyncing: AnyObject, Sendable {
    func sync(token: String, accountEmail: String, now: Date) async throws -> DeskSnapshot
}

/// Gmail / Calendar / Tasks reads. Mapping stays in VoiceDeskLogic.
@MainActor
final class LiveGoogleSync: GoogleSyncing {
    let session: URLSession
    let recentMessageLimit: Int

    init(session: URLSession = .shared, recentMessageLimit: Int = 8) {
        self.session = session
        self.recentMessageLimit = recentMessageLimit
    }

    func sync(token: String, accountEmail: String, now: Date) async throws -> DeskSnapshot {
        let session = self.session
        let limit = self.recentMessageLimit
        async let emails = Self.recentEmails(session: session, token: token, now: now, limit: limit)
        async let events = Self.upcomingEvents(session: session, token: token, now: now)
        async let tasks = Self.openTasks(session: session, token: token)
        return DeskSnapshot(
            accountEmail: accountEmail,
            lastSyncedAt: now,
            emails: try await emails,
            events: try await events,
            tasks: try await tasks
        )
    }

    private nonisolated static func recentEmails(
        session: URLSession,
        token: String,
        now: Date,
        limit: Int
    ) async throws -> [EmailItem] {
        let listData = try await getData(
            session: session,
            url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=\(limit)&q=in:inbox")!,
            token: token
        )
        let list = try Self.object(listData)
        let ids = (list["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        var messages: [[String: Any]] = []
        for id in ids.prefix(limit) {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(encoded)?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date")!
            messages.append(try Self.object(try await getData(session: session, url: url, token: token)))
        }
        let data = try JSONSerialization.data(withJSONObject: ["messages": messages])
        return try GoogleJSONMapping.emails(fromMessagesJSON: data, now: now)
    }

    private nonisolated static func upcomingEvents(
        session: URLSession,
        token: String,
        now: Date
    ) async throws -> [CalendarItem] {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "timeMin", value: ISO8601DateFormatter().string(from: now))
        ]
        let data = try await getData(session: session, url: components.url!, token: token)
        return try GoogleJSONMapping.events(fromCalendarJSON: data, now: now)
    }

    private nonisolated static func openTasks(session: URLSession, token: String) async throws -> [TaskItem] {
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks?showCompleted=false&maxResults=20")!
        let data = try await getData(session: session, url: url, token: token)
        return try GoogleJSONMapping.tasks(fromTasksJSON: data)
    }

    private nonisolated static func getData(session: URLSession, url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleSignInError.failed("Google API HTTP \(status) \(body.prefix(120))")
        }
        return data
    }

    private nonisolated static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleJSONMapping.MappingError.invalidJSON
        }
        return object
    }
}

@MainActor
final class MockGoogleSync: GoogleSyncing {
    var result: DeskSnapshot
    var error: String?

    init(result: DeskSnapshot = DeskSnapshot(emails: [SampleData.syncedEmail()])) {
        self.result = result
    }

    func sync(token: String, accountEmail: String, now: Date) async throws -> DeskSnapshot {
        _ = token
        if let error { throw GoogleSignInError.failed(error) }
        var next = result
        next.accountEmail = accountEmail
        next.lastSyncedAt = now
        return next
    }
}
