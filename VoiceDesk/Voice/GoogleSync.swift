import Foundation
import VoiceDeskLogic

protocol GoogleSyncing: AnyObject {
    func sync(token: String, accountEmail: String, now: Date) async throws -> DeskSnapshot
}

/// Gmail / Calendar / Tasks reads. Mapping stays in VoiceDeskLogic.
final class LiveGoogleSync: GoogleSyncing, @unchecked Sendable {
    var session: URLSession
    var recentMessageLimit: Int

    init(session: URLSession = .shared, recentMessageLimit: Int = 8) {
        self.session = session
        self.recentMessageLimit = recentMessageLimit
    }

    func sync(token: String, accountEmail: String, now: Date) async throws -> DeskSnapshot {
        async let emails = recentEmails(token: token, now: now)
        async let events = upcomingEvents(token: token, now: now)
        async let tasks = openTasks(token: token)
        return DeskSnapshot(
            accountEmail: accountEmail,
            lastSyncedAt: now,
            emails: try await emails,
            events: try await events,
            tasks: try await tasks
        )
    }

    private func recentEmails(token: String, now: Date) async throws -> [EmailItem] {
        let list = try await get(
            url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=\(recentMessageLimit)&q=in:inbox")!,
            token: token
        )
        let ids = (list["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        var messages: [[String: Any]] = []
        for id in ids.prefix(recentMessageLimit) {
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(encoded)?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date")!
            messages.append(try await get(url: url, token: token))
        }
        let data = try JSONSerialization.data(withJSONObject: ["messages": messages])
        return try GoogleJSONMapping.emails(fromMessagesJSON: data, now: now)
    }

    private func upcomingEvents(token: String, now: Date) async throws -> [CalendarItem] {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "timeMin", value: ISO8601DateFormatter().string(from: now))
        ]
        let object = try await get(url: components.url!, token: token)
        let data = try JSONSerialization.data(withJSONObject: object)
        return try GoogleJSONMapping.events(fromCalendarJSON: data, now: now)
    }

    private func openTasks(token: String) async throws -> [TaskItem] {
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks?showCompleted=false&maxResults=20")!
        let object = try await get(url: url, token: token)
        let data = try JSONSerialization.data(withJSONObject: object)
        return try GoogleJSONMapping.tasks(fromTasksJSON: data)
    }

    private func get(url: URL, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleSignInError.failed("Google API HTTP \(status) \(body.prefix(120))")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleJSONMapping.MappingError.invalidJSON
        }
        return object
    }
}

final class MockGoogleSync: GoogleSyncing, @unchecked Sendable {
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
