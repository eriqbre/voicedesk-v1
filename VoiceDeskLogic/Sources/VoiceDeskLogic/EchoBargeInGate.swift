import Foundation

/// Half-duplex while Eve is talking. Her TTS must not become a user turn.
public struct EchoBargeInGate: Equatable, Sendable {
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

    /// Abort a speak that never played (error, dropped handoff, watchdog).
    /// No cooldown — the next real weather ask must not be eaten.
    public mutating func assistantAborted() {
        assistantSpeaking = false
        cooldownUntil = nil
    }

    public func shouldAcceptUserInput(at now: Date = Date()) -> Bool {
        if assistantSpeaking { return false }
        if let cooldownUntil, now < cooldownUntil { return false }
        return true
    }

    public func shouldSendMicAudio(at now: Date = Date()) -> Bool {
        shouldAcceptUserInput(at: now)
    }
}

/// Thread-safe mute for the live mic tap (engine callback is off the main actor).
public final class MicrophoneCaptureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var muted = false

    public init() {}

    public func setMuted(_ value: Bool) {
        lock.lock()
        muted = value
        lock.unlock()
    }

    public func isMuted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return muted
    }
}
