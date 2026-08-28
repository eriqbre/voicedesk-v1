import Foundation

/// Compact first-hear dogfood tape. CoS mined 168 unique live
/// userTranscripts / 319 spoken turns. VoiceTapeGate decide on those 168
/// was 168 accept / 0 drop — that is not this gate. replay-voice-tape.py
/// on fa72e1c exited 2 with no minted WAVs (died before socket).
/// Do not expand VoiceTape.catalog. Eve interprets; no phrase table.
public enum EriqSpokenTape: Sendable {
    /// Newest spoken userTranscripts.
    public static let spoken: [String] = [
        "Murray",
        "Tell me Murray's latest email.",
        "Show me today's emails.",
        "What version are we on?",
        "Read that recent email from Eric.",
        "Show me my newest emails.",
        "Hey, what version are we on now?",
        "What's on my calendar?",
        "Summarize my latest email from Murray.",
        "Show me my latest emails.",
        "What version are we on now?",
        "Can you hear me?",
        "Show me the latest email from Murray.",
        "give me a summary on the email from lauren about fleeman rd",
        "what's the latest email from Lauren",
        "What's, give me a summary of the latest email from Murray."
    ]

    /// Intended lines that never landed as userTranscript. Same gate.
    public static let intended: [String] = [
        "Read me the one from eriq",
        "Read me the one from Eric",
        "last 10",
        "next 5",
        "everything new since we last talked",
        "everything from today",
        "Just show me everything.",
        "Show me all my emails from today."
    ]

    public static var lines: [String] { spoken + intended }
}
