import Foundation

/// "Stop" as a command to VoiceDesk, not "stop" as a word inside a sentence.
///
/// A substring match here is a mic-killer: `voice.cancel()` sets
/// `userWantsVoiceOff`, which blocks auto-reconnect and auto-listen until the
/// next Tap to talk. "I need to stop by the office" or "cancel the Saturday
/// showing" must never take the session down.
public enum VoiceStopIntent: Sendable {
    /// Openers and politeness that carry no intent on their own.
    static let filler: Set<String> = [
        "hey", "hi", "ok", "okay", "alright", "so", "well", "um", "uh", "er",
        "eve", "voicedesk", "voice", "desk", "assistant", "just", "please",
        "now", "right", "yeah", "yes", "no", "actually", "sorry"
    ]

    /// A verb that, standing alone, means "take the turn down".
    static let stopVerbs: Set<String> = [
        "stop", "cancel", "abort", "quit", "nevermind", "mute", "silence"
    ]

    /// What a stop verb is allowed to be applied to and still mean "stop".
    /// Anything outside this set makes it a sentence about something else.
    static let stopObjects: Set<String> = [
        "it", "that", "this", "there", "everything", "all",
        "listening", "listen", "talking", "talk", "speaking", "speak",
        "yourself", "up", "out"
    ]

    /// Phrases that mean stop but do not start with a stop verb.
    static let stopPhrases: Set<String> = [
        "never mind", "shut up", "be quiet", "quiet", "hush",
        "forget it", "forget that", "enough", "thats enough", "that is enough",
        "hold on", "hang on", "wait a second", "wait a sec"
    ]

    /// Longest phrase we will treat as a bare command. Beyond this the user is
    /// talking, not commanding.
    static let maxCommandTokens = 4

    public static func matches(_ raw: String) -> Bool {
        let tokens = commandTokens(raw)
        guard !tokens.isEmpty, tokens.count <= maxCommandTokens else { return false }

        if stopPhrases.contains(tokens.joined(separator: " ")) { return true }

        guard let verb = tokens.first, stopVerbs.contains(verb) else { return false }
        return tokens.dropFirst().allSatisfy { stopObjects.contains($0) || filler.contains($0) }
    }

    /// Lowercased words with punctuation dropped and framing filler removed.
    /// Apostrophes are deleted rather than split so "that's" reads as "thats".
    static func commandTokens(_ raw: String) -> [String] {
        let deapostrophized = raw.unicodeScalars
            .filter { $0 != "'" && $0 != "\u{2019}" }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
        let tokens = deapostrophized
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        var trimmed = tokens[...]
        while let first = trimmed.first, filler.contains(first), !stopVerbs.contains(first) {
            trimmed = trimmed.dropFirst()
        }
        while let last = trimmed.last, filler.contains(last), !stopVerbs.contains(last) {
            trimmed = trimmed.dropLast()
        }
        return Array(trimmed)
    }
}
