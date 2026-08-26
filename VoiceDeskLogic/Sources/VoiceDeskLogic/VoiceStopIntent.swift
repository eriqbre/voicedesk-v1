import Foundation

/// "Stop" as a command, not the word inside a sentence.
/// Substring match used to call `voice.cancel()` on "stop by the office".
public enum VoiceStopIntent: Sendable {
    public static func matches(_ raw: String) -> Bool {
        let compact = normalize(raw)
        switch compact {
        case "stop", "cancel", "abort", "nevermind", "never mind",
             "stop it", "stop that", "cancel it", "cancel that":
            return true
        default:
            return false
        }
    }

    private static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }
}
