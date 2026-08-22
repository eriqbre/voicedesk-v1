import Foundation

public protocol PlaybookStoring: AnyObject {
    var hasCompleted: Bool { get set }
    var hasSeenConnectOffer: Bool { get set }
    var lastConnectSoftPromptAt: Date? { get set }
}

public final class InMemoryPlaybookStore: PlaybookStoring {
    public var hasCompleted: Bool
    public var hasSeenConnectOffer: Bool
    public var lastConnectSoftPromptAt: Date?

    public init(
        completed: Bool = false,
        seenConnectOffer: Bool = false,
        lastConnectSoftPromptAt: Date? = nil
    ) {
        self.hasCompleted = completed
        self.hasSeenConnectOffer = seenConnectOffer
        self.lastConnectSoftPromptAt = lastConnectSoftPromptAt
    }
}

public enum VoicePlaybook {
    public static let defaultsKey = "hasCompletedVoicePlaybook"
    public static let seenConnectOfferKey = "hasSeenConnectGoogleOffer"
    public static let lastSoftPromptKey = "lastConnectGoogleSoftPromptAt"
}
