import Foundation

public enum SendAttempt: String, Hashable, Sendable {
    case blockedUnconfirmed
    case queuedNotDelivered
    case delivered
}

public protocol SendClient: AnyObject {
    func send(_ draft: DraftConfirmItem) -> SendAttempt
}

/// Records confirmed drafts only. Slice 1 never reports provider delivery.
public final class RecordingSendClient: SendClient, @unchecked Sendable {
    public private(set) var sentDrafts: [DraftConfirmItem] = []

    public init() {}

    public func send(_ draft: DraftConfirmItem) -> SendAttempt {
        guard draft.status == .confirmed else {
            return .blockedUnconfirmed
        }
        sentDrafts.append(draft)
        return .queuedNotDelivered
    }
}
