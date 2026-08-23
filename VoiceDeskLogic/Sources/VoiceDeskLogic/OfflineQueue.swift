import Foundation

public struct OfflineAction: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var payload: String

    public init(id: UUID = UUID(), title: String, payload: String) {
        self.id = id
        self.title = title
        self.payload = payload
    }
}

/// Confirmed writes wait here until a provider succeeds. Reads use last-synced cards.
public struct OfflineQueue: Hashable, Sendable, Codable {
    public private(set) var pending: [OfflineAction]

    public init(pending: [OfflineAction] = []) {
        self.pending = pending
    }

    public var isEmpty: Bool { pending.isEmpty }

    public mutating func enqueue(_ action: OfflineAction) {
        pending.append(action)
    }

    @discardableResult
    public mutating func flushWhenOnline() -> [OfflineAction] {
        let flushed = pending
        pending = []
        return flushed
    }
}
