import Foundation

/// Shared Google read limits. Live sync and tests must agree.
public enum GoogleSyncPolicy: Sendable {
    /// Baseline inbox pull on connect / foreground refresh (`q=in:inbox`).
    public static let recentInboxLimit = 25

    /// Connected + online restore always hits Gmail. `0` means ignore `lastSyncedAt`
    /// age — a non-empty cache must not skip network sync. Raise later if we want
    /// a short TTL instead of every restore.
    public static let restoreSyncMaxAge: TimeInterval = 0

    /// Restore / foreground: connected + online must refresh, even when cache
    /// already has `accountEmail`. Offline keeps the last-synced snapshot.
    public static func shouldRefreshOnRestore(
        isConnected: Bool,
        isOnline: Bool,
        lastSyncedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard isConnected, isOnline else { return false }
        guard restoreSyncMaxAge > 0, let lastSyncedAt else { return true }
        return now.timeIntervalSince(lastSyncedAt) >= restoreSyncMaxAge
    }

    /// Seconds since `lastSyncedAt` for DEBUG / dogfood routing notes.
    public static func cacheAgeSeconds(lastSyncedAt: Date?, now: Date = Date()) -> Int? {
        guard let lastSyncedAt else { return nil }
        return max(0, Int(now.timeIntervalSince(lastSyncedAt)))
    }

    public static func cacheAgeNote(lastSyncedAt: Date?, now: Date = Date()) -> String? {
        guard let age = cacheAgeSeconds(lastSyncedAt: lastSyncedAt, now: now) else { return nil }
        return "cacheAgeSec=\(age)"
    }
}
