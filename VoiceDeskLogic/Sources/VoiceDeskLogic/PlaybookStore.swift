import Foundation

public protocol PlaybookStoring: AnyObject {
    var hasCompleted: Bool { get set }
}

public final class InMemoryPlaybookStore: PlaybookStoring {
    public var hasCompleted: Bool

    public init(completed: Bool = false) {
        self.hasCompleted = completed
    }
}

public enum VoicePlaybook {
    public static let defaultsKey = "hasCompletedVoicePlaybook"
}
