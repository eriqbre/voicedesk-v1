import Foundation

public enum SendAttempt: String, Hashable, Sendable {
    case blockedUnconfirmed
    case queuedNotDelivered
    case delivered
}

public protocol SendClient: AnyObject {
    func send(_ draft: DraftConfirmItem) -> SendAttempt
}

/// Records confirmed drafts only. Never reports provider delivery without a success flag.
public final class RecordingSendClient: SendClient, @unchecked Sendable {
    public private(set) var sentDrafts: [DraftConfirmItem] = []
    public private(set) var queue = OfflineQueue()
    public var isOnline: Bool
    /// Only a real Gmail/Calendar/Tasks provider may flip this. Slice 2 leaves it false.
    public var providerDelivered = false

    public init(isOnline: Bool = true) {
        self.isOnline = isOnline
    }

    public func send(_ draft: DraftConfirmItem) -> SendAttempt {
        guard draft.status == .confirmed else {
            return .blockedUnconfirmed
        }
        sentDrafts.append(draft)
        queue.enqueue(
            OfflineAction(
                title: draft.actionTitle,
                payload: "\(draft.channel)|\(draft.toLine)|\(draft.subject)"
            )
        )
        if providerDelivered, isOnline {
            return .delivered
        }
        return .queuedNotDelivered
    }
}
