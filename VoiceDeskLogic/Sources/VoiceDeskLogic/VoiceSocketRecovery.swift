import Foundation

/// When the Grok realtime socket drops mid-conversation, reconnect once
/// instead of leaving a sticky red error and a wedged session.
public enum VoiceSocketRecovery: Sendable {
    public static let maxAutomaticReconnects = 1

    public static func isSocketDrop(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("socket is not connected")
            || lower.contains("socket is not connected.")
            || lower.contains("not connected")
            || lower.contains("broken pipe")
            || lower.contains("connection reset")
            || lower.contains("timed out")
            || lower.contains("timeout")
            || lower.contains("max_duration")
            || lower.contains("websocket timeout")
            || lower.contains("disconnected")
            || lower.contains("closed")
    }

    /// Unexpected WS drop while the user still wants voice on → reconnect once.
    /// User tap-stop / cancel / explicit voice off → never reconnect.
    public static func shouldReconnect(
        error: String,
        alreadyTried: Bool,
        userWantsVoiceOff: Bool = false
    ) -> Bool {
        if userWantsVoiceOff { return false }
        return !alreadyTried && isSocketDrop(error)
    }
}
