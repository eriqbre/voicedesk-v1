import Foundation

/// Transcript-level half-duplex while Eve is talking.
///
/// Her TTS (and leftover echo after playback) must not become a user turn or
/// desk action. The microphone keeps capturing — this gate only drops
/// transcripts and optional `speech_started` barge-in.
///
/// Do **not** mute the mic tap, `captureGate`, or `beginHalfDuplex`. That stack
/// left `VoiceSession` stuck in `.speaking` and froze the app.
public struct EchoTranscriptGate: Equatable, Sendable {
    /// 200–400ms after playback / turn finished before user input is accepted.
    public static let defaultCooldown: TimeInterval = 0.32

    public var assistantSpeaking = false
    public var cooldownUntil: Date?

    public init() {}

    public mutating func reset() {
        assistantSpeaking = false
        cooldownUntil = nil
    }

    public mutating func assistantStarted(at now: Date = Date()) {
        assistantSpeaking = true
        cooldownUntil = nil
        _ = now
    }

    public mutating func assistantFinished(
        at now: Date = Date(),
        cooldown: TimeInterval = Self.defaultCooldown
    ) {
        assistantSpeaking = false
        cooldownUntil = now.addingTimeInterval(cooldown)
    }

    /// Tap-stop / cancel. No cooldown — the next real ask must not be eaten.
    public mutating func assistantAborted() {
        assistantSpeaking = false
        cooldownUntil = nil
    }

    public func shouldAcceptUserInput(at now: Date = Date()) -> Bool {
        if assistantSpeaking { return false }
        if let cooldownUntil, now < cooldownUntil { return false }
        return true
    }

    /// Drop echo barge-in while Eve is speaking or during the tail cooldown.
    public func shouldAcceptSpeechStarted(at now: Date = Date()) -> Bool {
        shouldAcceptUserInput(at: now)
    }

    /// `voiceState == .speaking` is an equivalent “Eve is talking” flag.
    public func shouldAcceptUserTranscript(
        voiceState: VoiceState,
        at now: Date = Date()
    ) -> Bool {
        if voiceState == .speaking { return false }
        return shouldAcceptUserInput(at: now)
    }

    /// Returns the trimmed transcript, or `nil` when echo should be ignored.
    public func acceptUserTranscript(
        _ text: String,
        voiceState: VoiceState = .listening,
        at now: Date = Date()
    ) -> String? {
        guard shouldAcceptUserTranscript(voiceState: voiceState, at: now) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
