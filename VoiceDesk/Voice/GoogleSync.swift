import Foundation
import VoiceDeskLogic

/// Isolated with `AppModel` so `any GoogleSyncing` never leaves the main actor.
/// `Sendable` is valid because every implementation is `@MainActor`.
@MainActor
protocol GoogleSyncing: AnyObject, Sendable {
    func sync(
        token: String,
        accountEmail: String,
        now: Date,
        onInboxMessageIDs: (@Sendable ([String]) -> Void)?
    ) async throws -> DeskSnapshot
    func fetchMessage(token: String, messageID: String, now: Date) async throws -> EmailItem
    func searchMessages(token: String, query: String, now: Date) async throws -> [EmailItem]
}

/// Gmail / Calendar / Tasks reads. Mapping stays in VoiceDeskLogic.
@MainActor
final class LiveGoogleSync: GoogleSyncing {
    let session: URLSession
    let recentMessageLimit: Int

    init(session: URLSession = .shared, recentMessageLimit: Int = GoogleSyncPolicy.recentInboxLimit) {
        self.session = session
        self.recentMessageLimit = recentMessageLimit
    }

    func sync(
        token: String,
        accountEmail: String,
        now: Date,
        onInboxMessageIDs: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> DeskSnapshot {
        let session = self.session
        let limit = self.recentMessageLimit
        async let emails = Self.recentEmails(
            session: session,
            token: token,
            now: now,
            limit: limit,
            onInboxMessageIDs: onInboxMessageIDs
        )
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

    func fetchMessage(token: String, messageID: String, now: Date) async throws -> EmailItem {
        do {
            return try await Self.message(
                session: session,
                token: token,
                messageID: messageID,
                now: now
            )
        } catch {
            return try await Self.message(
                session: session,
                token: token,
                messageID: messageID,
                now: now
            )
        }
    }

    func searchMessages(token: String, query: String, now: Date) async throws -> [EmailItem] {
        let session = self.session
        return try await Self.search(session: session, token: token, query: query, now: now)
    }

    private nonisolated static func message(
        session: URLSession,
        token: String,
        messageID: String,
        now: Date
    ) async throws -> EmailItem {
        let encoded = messageID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? messageID
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(encoded)?format=full")!
        let payload = try await Self.object(try await getData(session: session, url: url, token: token))
        if let threadID = payload["threadId"] as? String, !threadID.isEmpty {
            let threadEncoded = threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? threadID
            let threadURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/threads/\(threadEncoded)?format=full")!
            do {
                let thread = try await Self.object(try await getData(session: session, url: threadURL, token: token))
                if let email = GoogleJSONMapping.email(fromThread: thread, now: now) {
                    return email
                }
            } catch {
                // Fall back to the single full message so the reader is not blank.
            }
        }
        guard let email = GoogleJSONMapping.email(from: payload, now: now) else {
            throw GoogleJSONMapping.MappingError.invalidJSON
        }
        return email
    }

    private nonisolated static func search(
        session: URLSession,
        token: String,
        query: String,
        now: Date
    ) async throws -> [EmailItem] {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "5")
        ]
        guard let url = components.url else {
            throw GoogleJSONMapping.MappingError.invalidJSON
        }
        let list = try object(try await getData(session: session, url: url, token: token))
        let ids = (list["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        var emails: [EmailItem] = []
        for id in ids.prefix(5) {
            emails.append(try await message(session: session, token: token, messageID: id, now: now))
        }
        return GoogleItemDedupe.emails(emails)
    }

    private nonisolated static func recentEmails(
        session: URLSession,
        token: String,
        now: Date,
        limit: Int,
        onInboxMessageIDs: (@Sendable ([String]) -> Void)?
    ) async throws -> [EmailItem] {
        let listData = try await getData(
            session: session,
            url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=\(limit)&q=in:inbox")!,
            token: token
        )
        let list = try Self.object(listData)
        let ids = (list["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        onInboxMessageIDs?(Array(ids.prefix(limit)))
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

    var bodies: [String: String] = [:]
    var htmlBodies: [String: String] = [:]
    var earlierMessages: [String: [EmailThreadMessage]] = [:]
    var searchable: [EmailItem] = []
    var searchQueries: [String] = []
    var fetchCalls = 0
    var syncCalls = 0
    var failuresRemaining = 0

    func sync(
        token: String,
        accountEmail: String,
        now: Date,
        onInboxMessageIDs: (@Sendable ([String]) -> Void)? = nil
    ) async throws -> DeskSnapshot {
        _ = token
        syncCalls += 1
        if let error { throw GoogleSignInError.failed(error) }
        onInboxMessageIDs?(result.emails.compactMap(\.providerID))
        var next = result
        next.accountEmail = accountEmail
        next.lastSyncedAt = now
        return next
    }

    func fetchMessage(token: String, messageID: String, now: Date) async throws -> EmailItem {
        do {
            return try fetchOnce(token: token, messageID: messageID, now: now)
        } catch {
            return try fetchOnce(token: token, messageID: messageID, now: now)
        }
    }

    func searchMessages(token: String, query: String, now: Date) async throws -> [EmailItem] {
        _ = token
        _ = now
        searchQueries.append(query)
        if let error { throw GoogleSignInError.failed(error) }
        let pool = searchable.isEmpty ? result.emails : searchable
        return pool.filter { GmailSearchQuery.matches($0, gmailQuery: query) }
    }

    private func fetchOnce(token: String, messageID: String, now: Date) throws -> EmailItem {
        _ = token
        _ = now
        fetchCalls += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw GoogleSignInError.failed(error ?? "transient fetch failure")
        }
        if let error { throw GoogleSignInError.failed(error) }
        guard var email = result.emails.first(where: { $0.providerID == messageID })
                ?? searchable.first(where: { $0.providerID == messageID }) else {
            throw GoogleSignInError.failed("No synced message \(messageID).")
        }
        if let body = bodies[messageID] {
            email.body = body
        }
        if let html = htmlBodies[messageID] {
            email.htmlBody = html
        }
        if let earlier = earlierMessages[messageID] {
            email.earlierMessages = earlier
        }
        guard email.hasFullBody else {
            throw GoogleSignInError.failed("No body for \(messageID).")
        }
        return email
    }
}
