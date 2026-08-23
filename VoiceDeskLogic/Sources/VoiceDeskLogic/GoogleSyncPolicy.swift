import Foundation

/// Shared Google read limits. Live sync and tests must agree.
public enum GoogleSyncPolicy: Sendable {
    /// Baseline inbox pull on connect / foreground refresh (`q=in:inbox`).
    public static let recentInboxLimit = 25
}
