import Foundation

/// Whether a local desk reply should go through `voice.speak`.
/// Skip the transient search beat and the same line spoken twice.
public enum DeskReplySpeech: Sendable {
    public static func textToSpeak(_ text: String, lastSpoken: String?) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if ConversationPresence.isStatusBeat(trimmed) { return nil }
        if LaunchSyncStatus.isSilent(trimmed) { return nil }
        if let lastSpoken, trimmed == lastSpoken { return nil }
        if EmailSummary.isConnectInstruction(trimmed) { return trimmed }
        let cleaned = EmailSummary.scrubUIChrome(trimmed)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// A desk-thread / desk-person card must never be silent.
    /// Empty, slow, unused, or skipped xAI falls back to the heuristic digest.
    public static func spokenDeskHit(
        _ email: EmailItem,
        xaiSummarize: String? = nil,
        includeEarlier: Bool = false
    ) -> String {
        if let spoken = textToSpeak(xaiSummarize ?? "", lastSpoken: nil) {
            return spoken
        }
        let heuristic = EmailSummary.heuristic(
            EmailSummaryRequest.from(email, includeEarlier: includeEarlier)
        )
        if let spoken = textToSpeak(heuristic, lastSpoken: nil) {
            return spoken
        }
        let who = email.fromName.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = email.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !who.isEmpty, !subject.isEmpty {
            return "\(who) wrote about \(subject)."
        }
        if !who.isEmpty {
            return "\(who) wrote."
        }
        return "I have the email, but I’m not inventing what it says."
    }
}
