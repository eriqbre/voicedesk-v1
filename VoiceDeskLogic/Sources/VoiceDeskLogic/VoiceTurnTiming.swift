import Foundation

/// Per-turn speak timing for dogfood logs. Dates are wall-clock; `latencyMs`
/// is the primary stall signal (`firstAudioAt - userFinalAt`).
public struct VoiceTurnTiming: Equatable, Sendable {
    public var userFinalAt: Date?
    public var replyReadyAt: Date?
    public var firstAudioAt: Date?
    public var replyDoneAt: Date?
    public var stages: [String]

    public init(
        userFinalAt: Date? = nil,
        replyReadyAt: Date? = nil,
        firstAudioAt: Date? = nil,
        replyDoneAt: Date? = nil,
        stages: [String] = []
    ) {
        self.userFinalAt = userFinalAt
        self.replyReadyAt = replyReadyAt
        self.firstAudioAt = firstAudioAt
        self.replyDoneAt = replyDoneAt
        self.stages = stages
    }

    /// Eve audio start minus final user transcript / desk claim.
    public var latencyMs: Int? {
        Self.milliseconds(from: userFinalAt, to: firstAudioAt)
    }

    public var replyReadyMs: Int? {
        Self.milliseconds(from: userFinalAt, to: replyReadyAt)
    }

    public var hasAnyTimestamp: Bool {
        userFinalAt != nil || replyReadyAt != nil || firstAudioAt != nil || replyDoneAt != nil
    }

    public static func milliseconds(from start: Date?, to end: Date?) -> Int? {
        guard let start, let end else { return nil }
        return Int((end.timeIntervalSince(start) * 1000).rounded())
    }

    public mutating func markUserFinal(at date: Date = Date()) {
        if userFinalAt == nil { userFinalAt = date }
    }

    public mutating func markReplyReady(at date: Date = Date()) {
        if replyReadyAt == nil { replyReadyAt = date }
    }

    public mutating func markFirstAudio(at date: Date = Date()) {
        if firstAudioAt == nil { firstAudioAt = date }
    }

    public mutating func markReplyDone(at date: Date = Date()) {
        if replyDoneAt == nil { replyDoneAt = date }
    }

    public mutating func addStage(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !stages.contains(trimmed) else { return }
        stages.append(trimmed)
    }
}

/// Marks from the live voice engine. AppModel folds these into `VoiceTurnTiming`.
public enum VoiceSpeakTimingMark: Equatable, Sendable {
    case firstAudio
    case replyDone
    case stage(String)
}
