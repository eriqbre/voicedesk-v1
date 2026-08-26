import Foundation

/// Eriq 2026-08-26 live userTranscripts. Dogfood tape, not a parser.
/// Each line must land as one turn after client TTS. Eve interprets.
public enum EriqSpokenTape: Sendable {
    public static let walkLines: [String] = [
        "Hey, what version are we on now?",
        "What version are we on?",
        "Show me my newest emails.",
        "Show me today's emails.",
        "Show me all my emails from today.",
        "Just show me everything.",
        "Read that recent email from Eric.",
        "Read me the one from eriq",
        "Tell me Murray's latest email.",
        "Show me the latest email from Murray.",
        "Can you hear me?",
        "What's, give me a summary of the latest email from Murray."
    ]

    /// Same first-hear gate. Not an exact-phrase table.
    public static let coverLines: [String] = [
        "Give me a summary of the email from Lauren about Fleeman Road.",
        "last 10",
        "next 5",
        "everything new since we last talked",
        "everything from today"
    ]

    public static var lines: [String] { walkLines + coverLines }
}
