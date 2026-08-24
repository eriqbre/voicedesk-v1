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
    /// Desk claim / accepted userFinal: leftover Grok `turnFinished` must not
    /// bounce the orb back to Listening while we wait for first audio.
    public var holdsThinkingUntilAudio: Bool

    public init(state: VoiceState = .idle, holdsThinkingUntilAudio: Bool = false) {
        self.state = state
        self.holdsThinkingUntilAudio = holdsThinkingUntilAudio
    }

    /// Orb/status: Eve heard them and is working. No mic mute, no earcon.
    public mutating func beginThinking(holdUntilAudio: Bool = true) {
        if state == .idle || state == .listening {
            state = .thinking
        }
        if holdUntilAudio, state == .thinking {
            holdsThinkingUntilAudio = true
        }
    }

    public mutating func apply(_ event: VoiceSessionEvent) {
        switch (state, event) {
        case (.idle, .tapTalk):
            state = .listening
        case (.listening, .listenFinished):
            state = .thinking
        case (.thinking, .speakStarted), (.idle, .speakStarted), (.listening, .speakStarted):
            holdsThinkingUntilAudio = false
            state = .speaking
        case (.speaking, .speakFinished):
            holdsThinkingUntilAudio = false
            state = .idle
        case (.speaking, .turnFinished), (.listening, .turnFinished):
            state = .listening
        case (.thinking, .turnFinished):
            if holdsThinkingUntilAudio { break }
            state = .listening
        case (.listening, .tapTalk), (.thinking, .tapTalk), (.speaking, .tapTalk):
            holdsThinkingUntilAudio = false
            state = .idle
        case (_, .cancel):
            holdsThinkingUntilAudio = false
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
