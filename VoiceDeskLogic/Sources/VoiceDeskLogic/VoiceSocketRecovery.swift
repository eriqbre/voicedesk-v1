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
            || lower.contains("websocket timeout")
            || lower.contains("disconnected")
            || lower.contains("closed")
    }

    public static func shouldReconnect(error: String, alreadyTried: Bool) -> Bool {
        !alreadyTried && isSocketDrop(error)
    }
}
