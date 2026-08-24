import Foundation

/// Last-synced Google reads. Cards and Grok presence may only use this — never invent mail.
public struct DeskSnapshot: Equatable, Hashable, Sendable, Codable {
    public var accountEmail: String?
    public var lastSyncedAt: Date?
    public var emails: [EmailItem]
    public var events: [CalendarItem]
    public var tasks: [TaskItem]
    public var lastError: String?

    public init(
        accountEmail: String? = nil,
        lastSyncedAt: Date? = nil,
        emails: [EmailItem] = [],
        events: [CalendarItem] = [],
        tasks: [TaskItem] = [],
        lastError: String? = nil
    ) {
        self.accountEmail = accountEmail
        self.lastSyncedAt = lastSyncedAt
        self.emails = emails
        self.events = events
        self.tasks = tasks
        self.lastError = lastError
    }

    public static let empty = DeskSnapshot()

    public var hasAnyReads: Bool {
        !emails.isEmpty || !events.isEmpty || !tasks.isEmpty
    }

    /// Newest inbox rows for glance / “latest emails”. A view — never the store.
    public var glanceEmails: [EmailItem] {
        Array(emails.prefix(InboxGlance.overviewLimit))
    }

    public var syncLabel: String {
        guard let lastSyncedAt else { return "Not synced yet" }
        return "Last synced \(DeskSnapshot.timeLabel(lastSyncedAt))"
    }

    public static func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

public struct DeskContext: Equatable, Sendable {
    public var isConnected: Bool
    public var clientIDConfigured: Bool
    public var isOnline: Bool
    public var snapshot: DeskSnapshot
    public var auth: GoogleAuthSnapshot

    public init(
        isConnected: Bool = false,
        clientIDConfigured: Bool = true,
        isOnline: Bool = true,
        snapshot: DeskSnapshot = .empty,
        auth: GoogleAuthSnapshot = .signedOut
    ) {
        self.isConnected = isConnected
        self.clientIDConfigured = clientIDConfigured
        self.isOnline = isOnline
        self.snapshot = snapshot
        self.auth = auth
    }

    public static let disconnected = DeskContext()

    public var mailboxOwner: MailboxOwner? {
        MailboxOwner.from(email: auth.email ?? snapshot.accountEmail)
    }

    public var connectItem: ConnectGoogleItem {
        ConnectGoogleItem(
            isConnected: isConnected,
            accountEmail: auth.email ?? snapshot.accountEmail,
            setupNeeded: !clientIDConfigured || auth.setupNeeded,
            statusLine: auth.statusLine
        )
    }
}
