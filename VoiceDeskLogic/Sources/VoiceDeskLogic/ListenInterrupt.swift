import Foundation

/// Playback cancels only when Eve already treats the utterance as a command.
/// Energy / `speech_started` may wake analysis. Radio and other-room speech
/// stay ignored — no leftover-echo list, no energy-only interrupt.
public enum ListenInterrupt: Sendable {
    public static func isCommand(
        _ utterance: String,
        context: DeskContext = .disconnected,
        pendingSearchClarify: Bool = false,
        hasClarifyMatches: Bool = false,
        hasFocusedEmail: Bool = false,
        pendingSenderRefine: Bool = false,
        focusedEmail: EmailItem? = nil,
        priorSearchAsk: String? = nil
    ) -> Bool {
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if ConversationPresence.isJustTalk(text) { return false }
        if ConversationPresence.plan(for: text, context: context).topic != .general {
            return true
        }
        if ConversationPresence.ownsConnectedDeskTurn(
            text,
            pendingSearchClarify: pendingSearchClarify,
            hasClarifyMatches: hasClarifyMatches,
            hasFocusedEmail: hasFocusedEmail,
            pendingSenderRefine: pendingSenderRefine,
            events: context.snapshot.events
        ) {
            return true
        }
        return ConversationPresence.deskEvidence(
            for: text,
            context: context,
            focusedEmail: focusedEmail,
            pendingSearchClarify: pendingSearchClarify,
            priorSearchAsk: priorSearchAsk
        ) != nil
    }
}
