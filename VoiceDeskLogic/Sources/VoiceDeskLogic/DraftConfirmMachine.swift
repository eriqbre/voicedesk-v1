import Foundation

public enum DraftConfirmAction: Hashable, Sendable {
    case beginEdit
    case saveBody
    case confirm
    case cancel
}

public enum DraftConfirmMachine: Sendable {
    public static func apply(_ status: DraftStatus, _ action: DraftConfirmAction) -> DraftStatus {
        switch (status, action) {
        case (.pending, .beginEdit):
            return .editing
        case (.editing, .saveBody):
            return .pending
        case (.pending, .confirm), (.editing, .confirm):
            return .confirmed
        case (.pending, .cancel), (.editing, .cancel):
            return .cancelled
        default:
            return status
        }
    }

    public static func mayCallSendClient(after status: DraftStatus) -> Bool {
        status == .confirmed
    }
}
