import Foundation

/// `.thinking` is entered on `input_audio_buffer.speech_stopped` and only left
/// again when a response arrives. The presence prompt deliberately tells Grok
/// to stay silent on desk turns, and a cancelled or empty response produces no
/// `response.created` either — so the session parks in `.thinking`, the UI
/// keeps saying "Thinking…", and the next tap reads as a stop instead of a
/// resume. Fall back to `.listening` once the budget is spent.
public struct VoiceTurnTimeout: Equatable, Sendable {
    /// Long enough for a real reply to start streaming, short enough that a
    /// silent turn does not read as a hang.
    public static let defaultThinkingBudget: TimeInterval = 4

    public private(set) var thinkingSince: Date?

    public init(thinkingSince: Date? = nil) {
        self.thinkingSince = thinkingSince
    }

    public mutating func stateChanged(to state: VoiceState, at now: Date = Date()) {
        guard state == .thinking else {
            thinkingSince = nil
            return
        }
        // Keep the original entry time so repeated `.thinking` updates cannot
        // push the deadline out forever.
        if thinkingSince == nil { thinkingSince = now }
    }

    public func hasStalled(
        now: Date = Date(),
        budget: TimeInterval = defaultThinkingBudget
    ) -> Bool {
        guard let thinkingSince else { return false }
        return now.timeIntervalSince(thinkingSince) > budget
    }
}
