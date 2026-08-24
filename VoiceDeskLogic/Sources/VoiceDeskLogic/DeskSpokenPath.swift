import Foundation

/// Live Grok audio/transcript policy for client-owned desk turns.
///
/// Grok often speaks a refusal or handoff (“I can’t help with that”,
/// “I’ll let the app handle that”) before or during Eve’s SPEAK_VERBATIM
/// digest. The user must hear only the local summary.
///
/// Audio suppress is for Grok handoff only. Eve SPEAK_VERBATIM still plays
/// once the heard transcript is the digest — not a refusal prefix.
public enum DeskSpokenPath: Sendable {
    /// Phrases that must never be spoken or shown as Grok’s desk-turn answer.
    public static let forbiddenPhrases = [
        "can't help",
        "cannot help",
        "can’t help",
        "i'm not able to",
        "i am not able to",
        "i’m not able to",
        "i'm unable to",
        "i am unable to",
        "i’m unable to",
        "not able to help",
        "not able to do that",
        "i can't do that",
        "i cannot do that",
        "i can’t do that",
        "i can't assist",
        "i cannot assist",
        "i can’t assist",
        "let the app handle",
        "i'll let the app",
        "i’ll let the app"
    ]

    /// Live Grok text that must not play or stay on a claimed desk turn.
    public static func isForbiddenLiveSpeech(_ raw: String) -> Bool {
        ConversationPresence.isGrokDeskMeta(raw)
    }

    /// Strip leading refusal / handoff sentences. A long Eve digest that
    /// later quotes “can’t help” is kept — only the Grok prefix is removed.
    public static func strippingLeadingRefusal(_ raw: String) -> String {
        var rest = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while !rest.isEmpty {
            let (sentence, tail) = firstSentence(rest)
            if isRefusalSentence(sentence) {
                rest = tail
                continue
            }
            break
        }
        return rest
    }

    /// Whether live Grok assistant audio should play.
    ///
    /// - Desk claimed, not verbatim: never (handoff / refusal stays muted).
    /// - Verbatim, no text yet: hold (audio may be a refusal prefix).
    /// - Verbatim, text is only refusal/meta: keep holding / drop.
    /// - Verbatim, playable remainder (the Eve digest): play.
    public static func allowsLiveGrokAudio(
        deskClaimed: Bool,
        verbatimSpeaking: Bool,
        assistantText: String
    ) -> Bool {
        if verbatimSpeaking {
            let trimmed = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            return !strippingLeadingRefusal(trimmed).isEmpty
        }
        return !deskClaimed
    }

    /// Held refusal audio should be discarded once we know the heard text
    /// is only meta — not flushed into the Eve digest.
    public static func shouldDiscardHeldAudio(assistantText: String) -> Bool {
        let trimmed = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return strippingLeadingRefusal(trimmed).isEmpty
    }

    private static func isRefusalSentence(_ raw: String) -> Bool {
        let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return false }
        if ConversationPresence.isGrokDeskHandoff(sentence) { return true }
        if ConversationPresence.isGrokCapabilityRefusal(sentence) { return true }
        if ConversationPresence.isGrokDeskMeta(sentence), sentence.count <= 160 {
            return true
        }
        return false
    }

    private static func firstSentence(_ text: String) -> (String, String) {
        let separators = CharacterSet(charactersIn: ".!?\n")
        guard let index = text.unicodeScalars.firstIndex(where: { separators.contains($0) }) else {
            return (text, "")
        }
        let end = text.index(after: index)
        let head = String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(text[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (head, tail)
    }
}
