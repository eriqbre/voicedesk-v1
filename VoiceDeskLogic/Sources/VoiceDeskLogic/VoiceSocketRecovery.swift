import Foundation

/// When the Grok realtime socket drops mid-conversation, reconnect with
/// backoff instead of leaving a sticky red error and a wedged session.
public enum VoiceSocketRecovery: Sendable {
    /// A single retry left a real conversation dead on the second blip — a
    /// spotty cell handoff routinely drops twice in a row.
    public static let maxAutomaticReconnects = 5

    public static let baseReconnectDelay: TimeInterval = 0.5
    public static let maxReconnectDelay: TimeInterval = 8

    /// Why the socket went away, which decides whether retrying can ever help.
    public enum FailureKind: String, Sendable, Equatable {
        /// Our own `disconnect()` on the way to a fresh socket. The old task's
        /// completion callback must never tear the new session down.
        case intentionalCancel
        /// Network blip. Retry.
        case transient
        /// Bad or expired credentials. Retrying just burns the budget.
        case authentication
        /// Wrong model, malformed request, refused upgrade. Surface it.
        case fatal
    }

    public static func isSocketDrop(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("socket is not connected")
            || lower.contains("not connected")
            || lower.contains("broken pipe")
            || lower.contains("connection reset")
            || lower.contains("connection lost")
            || lower.contains("network connection was lost")
            || lower.contains("appears to be offline")
            || lower.contains("timed out")
            || lower.contains("websocket timeout")
            || lower.contains("disconnected")
            || lower.contains("closed")
    }

    /// `URLSession` reports our own `cancel()` / `invalidateAndCancel()` as an
    /// error on the *old* task, which arrives after the replacement socket is
    /// already live.
    public static func isIntentionalCancellation(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("cancelled") || lower.contains("canceled")
    }

    public static func classify(error: String, httpStatus: Int? = nil) -> FailureKind {
        if let httpStatus {
            switch httpStatus {
            case 401, 403:
                return .authentication
            case 408, 429:
                return .transient
            case 500...599:
                return .transient
            case 400...499:
                return .fatal
            default:
                break
            }
        }
        if isIntentionalCancellation(error) { return .intentionalCancel }
        if isSocketDrop(error) { return .transient }
        // An unlabelled drop mid-conversation is far more often a blip than a
        // permanent fault, and the attempt budget caps the damage either way.
        return .transient
    }

    public static func shouldReconnect(
        kind: FailureKind,
        attemptsUsed: Int,
        userWantsVoiceOff: Bool = false
    ) -> Bool {
        if userWantsVoiceOff { return false }
        guard kind == .transient else { return false }
        return attemptsUsed < maxAutomaticReconnects
    }

    /// Unexpected WS drop while the user still wants voice on → reconnect.
    /// User tap-stop / cancel / explicit voice off → never reconnect.
    public static func shouldReconnect(
        error: String,
        alreadyTried: Bool,
        userWantsVoiceOff: Bool = false,
        httpStatus: Int? = nil
    ) -> Bool {
        shouldReconnect(
            kind: classify(error: error, httpStatus: httpStatus),
            attemptsUsed: alreadyTried ? maxAutomaticReconnects : 0,
            userWantsVoiceOff: userWantsVoiceOff
        )
    }

    /// Exponential backoff. `attemptsUsed` is how many reconnects already ran,
    /// so the first retry is immediate-ish and the last waits out a real outage.
    public static func reconnectDelay(attemptsUsed: Int) -> TimeInterval {
        guard attemptsUsed > 0 else { return 0 }
        let scaled = baseReconnectDelay * pow(2, Double(attemptsUsed - 1))
        return min(scaled, maxReconnectDelay)
    }
}
