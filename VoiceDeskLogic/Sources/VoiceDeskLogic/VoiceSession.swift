import Foundation

public enum VoiceState: String, Hashable, Sendable {
    case idle
    case listening
    case thinking
    case speaking
}

public enum VoiceSessionEvent: Hashable, Sendable {
    case tapTalk
    case listenFinished
    case speakStarted
    case speakFinished
    /// Live Grok finished a turn; stay in `.listening` so the socket stays open.
    case turnFinished
    case cancel
}

/// Tap-to-talk / wake-or-cancel state machine. Pure so Linux tests can run it.
public struct VoiceSession: Hashable, Sendable {
    public var state: VoiceState

    public init(state: VoiceState = .idle) {
        self.state = state
    }

    public mutating func apply(_ event: VoiceSessionEvent) {
        switch (state, event) {
        case (.idle, .tapTalk):
            state = .listening
        case (.listening, .listenFinished):
            state = .thinking
        case (.thinking, .speakStarted), (.idle, .speakStarted), (.listening, .speakStarted):
            state = .speaking
        case (.speaking, .speakFinished):
            state = .idle
        case (.speaking, .turnFinished), (.thinking, .turnFinished), (.listening, .turnFinished):
            state = .listening
        case (.listening, .tapTalk), (.thinking, .tapTalk), (.speaking, .tapTalk):
            state = .idle
        case (_, .cancel):
            state = .idle
        default:
            break
        }
    }
}

public struct WakeWordSession: Hashable, Sendable {
    public var isArmed: Bool

    public init(isArmed: Bool = false) {
        self.isArmed = isArmed
    }

    public mutating func arm() {
        isArmed = true
    }

    public mutating func disarm() {
        isArmed = false
    }
}
