import Foundation

/// Whether a local desk reply should go through `voice.speak`.
/// Skip the transient search beat and the same line spoken twice.
public enum DeskReplySpeech: Sendable {
    public static func textToSpeak(_ text: String, lastSpoken: String?) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if ConversationPresence.isStatusBeat(trimmed) { return nil }
        if let lastSpoken, trimmed == lastSpoken { return nil }
        if EmailSummary.isConnectInstruction(trimmed) { return trimmed }
        let cleaned = EmailSummary.scrubUIChrome(trimmed)
        return cleaned.isEmpty ? nil : cleaned
    }
}
