import Foundation

/// First-load inbox restore / sync chip. Not a chat turn. Never spoken.
public enum LaunchSyncPhase: Equatable, Sendable {
    case idle
    case restoringGoogle
    case syncingInbox
    /// Real count from the sync API (inbox IDs not already in cache). Never the pull limit.
    case downloadingNewEmails(Int)
    case inboxUpToDate
    case refreshFailed
}

public enum LaunchSyncStatus: Sendable {
    public static let restoringStem = "Restoring Google"
    public static let syncingStem = "Syncing inbox"
    public static let upToDateText = "Inbox up to date"
    public static let failedText = "Couldn’t refresh inbox"

    /// How long “Inbox up to date” / fail copy stays before the chip dismisses.
    public static let holdSeconds: TimeInterval = 0.7

    public static func downloadingStem(count: Int) -> String? {
        guard count > 0 else { return nil }
        if count == 1 { return "Downloading 1 new email" }
        return "Downloading \(count) new emails"
    }

    /// Count is shown only when the list API returned IDs we did not already have.
    /// Unknown / zero → generic “Syncing inbox”. Never use `recentInboxLimit` as a fake count.
    public static func phaseAfterInboxIDs(
        _ ids: [String],
        cachedProviderIDs: Set<String>
    ) -> LaunchSyncPhase {
        let newIDs = ids.filter { !$0.isEmpty && !cachedProviderIDs.contains($0) }
        if newIDs.isEmpty { return .syncingInbox }
        return .downloadingNewEmails(newIDs.count)
    }

    public static func stem(for phase: LaunchSyncPhase) -> String? {
        switch phase {
        case .idle:
            return nil
        case .restoringGoogle:
            return restoringStem
        case .syncingInbox:
            return syncingStem
        case .downloadingNewEmails(let count):
            return downloadingStem(count: count) ?? syncingStem
        case .inboxUpToDate:
            return upToDateText
        case .refreshFailed:
            return failedText
        }
    }

    public static func animatesDots(_ phase: LaunchSyncPhase) -> Bool {
        switch phase {
        case .restoringGoogle, .syncingInbox, .downloadingNewEmails:
            return true
        case .idle, .inboxUpToDate, .refreshFailed:
            return false
        }
    }

    /// These lines must never go through `voice.speak`.
    public static func isSilent(_ raw: String) -> Bool {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "…", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if trimmed.isEmpty { return false }
        if trimmed == restoringStem
            || trimmed == syncingStem
            || trimmed == upToDateText
            || trimmed == failedText {
            return true
        }
        return trimmed.hasPrefix("Downloading ") && trimmed.contains("new email")
    }
}
