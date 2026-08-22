import Foundation

public enum GoogleConnectionState: String, Hashable, Sendable, Codable {
    case signedOut
    case missingClientID
    case connecting
    case signedIn
    case failed
}

public enum GoogleAuthEvent: Equatable, Sendable {
    case clientIDMissing
    case clientIDReady
    case connectStarted
    case connectSucceeded(email: String)
    case connectFailed(String)
    case disconnect
}

/// Pure OAuth UI state. Never becomes signed-in without a success event.
public struct GoogleAuthSnapshot: Equatable, Sendable, Codable {
    public var state: GoogleConnectionState
    public var email: String?
    public var message: String?

    public init(
        state: GoogleConnectionState = .signedOut,
        email: String? = nil,
        message: String? = nil
    ) {
        self.state = state
        self.email = email
        self.message = message
    }

    public static let signedOut = GoogleAuthSnapshot()

    public static let missingClientIDCopy =
        "Add GOOGLE_CLIENT_ID to Secrets.plist or the VoiceDesk scheme, plus the reversed client ID URL scheme. See README. I will not pretend Google is connected."

    public var isConnected: Bool { state == .signedIn && !(email ?? "").isEmpty }

    public var setupNeeded: Bool { state == .missingClientID }

    public var statusLine: String {
        switch state {
        case .signedOut:
            return "Required for a real day"
        case .missingClientID:
            return "Setup needed — no client ID"
        case .connecting:
            return "Connecting…"
        case .signedIn:
            return email.map { "Connected as \($0)" } ?? "Connected"
        case .failed:
            return message ?? "Sign-in failed"
        }
    }

    public static func reduce(_ current: GoogleAuthSnapshot, _ event: GoogleAuthEvent) -> GoogleAuthSnapshot {
        switch event {
        case .clientIDMissing:
            return GoogleAuthSnapshot(
                state: .missingClientID,
                email: nil,
                message: missingClientIDCopy
            )
        case .clientIDReady:
            if current.state == .signedIn { return current }
            return .signedOut
        case .connectStarted:
            if current.state == .missingClientID {
                return current
            }
            return GoogleAuthSnapshot(state: .connecting, email: current.email, message: nil)
        case .connectSucceeded(let email):
            let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return GoogleAuthSnapshot(state: .failed, email: nil, message: "Google returned no account email.")
            }
            return GoogleAuthSnapshot(state: .signedIn, email: trimmed, message: nil)
        case .connectFailed(let reason):
            if current.state == .missingClientID {
                return current
            }
            return GoogleAuthSnapshot(state: .failed, email: nil, message: reason)
        case .disconnect:
            return .signedOut
        }
    }
}
