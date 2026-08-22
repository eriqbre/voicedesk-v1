import Foundation

/// One spoken/typed user turn must produce one bubble.
/// Prefer realtime `item_id`; also drop consecutive identical finals in a short window.
public struct TranscriptDedupe: Equatable, Sendable {
    public var lastItemID: String?
    public var lastNormalizedText: String
    public var lastAcceptedAt: Date

    public static let defaultWindow: TimeInterval = 2.0

    public init(
        lastItemID: String? = nil,
        lastNormalizedText: String = "",
        lastAcceptedAt: Date = .distantPast
    ) {
        self.lastItemID = lastItemID
        self.lastNormalizedText = lastNormalizedText
        self.lastAcceptedAt = lastAcceptedAt
    }

    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Returns the trimmed text to append, or `nil` if this is a duplicate.
    public mutating func accept(
        text: String,
        itemID: String? = nil,
        at now: Date = Date(),
        window: TimeInterval = defaultWindow
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let itemID, let lastItemID, itemID == lastItemID {
            return nil
        }

        let normalized = Self.normalized(trimmed)
        if !lastNormalizedText.isEmpty,
           normalized == lastNormalizedText,
           now.timeIntervalSince(lastAcceptedAt) < window {
            return nil
        }

        if let itemID { lastItemID = itemID }
        lastNormalizedText = normalized
        lastAcceptedAt = now
        return trimmed
    }
}

public enum AssistantTranscriptSource: String, Sendable, Equatable {
    case audio
    case outputText
}

/// Prefer audio transcript when both `output_audio_transcript.delta` and `output_text.delta` fire.
public struct AssistantTranscriptGate: Equatable, Sendable {
    public var preferred: AssistantTranscriptSource?

    public init(preferred: AssistantTranscriptSource? = nil) {
        self.preferred = preferred
    }

    public mutating func reset() {
        preferred = nil
    }

    public mutating func shouldAccept(_ source: AssistantTranscriptSource) -> Bool {
        if preferred == nil {
            preferred = source
            return true
        }
        return preferred == source
    }
}
