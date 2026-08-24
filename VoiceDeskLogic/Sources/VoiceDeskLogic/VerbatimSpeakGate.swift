import Foundation

/// Tracks one Eve SPEAK_VERBATIM turn so a leftover Grok `response.done`
/// (handoff / cancelled reply) cannot mute audio before the local digest plays.
public struct VerbatimSpeakGate: Equatable, Sendable {
    public var isSpeaking = false
    public var awaitingCreated = false
    public var responseID: String?
    /// Assistant transcript heard on the verbatim response (not shown in UI).
    public var heard = ""

    public init() {}

    public mutating func begin() {
        isSpeaking = true
        awaitingCreated = true
        responseID = nil
        heard = ""
    }

    public mutating func hear(_ delta: String) {
        heard += delta
    }

    /// Play Eve audio only after the heard text is the digest, not a refusal.
    public func allowsAudio(deskClaimed: Bool) -> Bool {
        DeskSpokenPath.allowsLiveGrokAudio(
            deskClaimed: deskClaimed,
            verbatimSpeaking: isSpeaking,
            assistantText: heard
        )
    }

    /// First `response.created` after `begin()` is the verbatim turn.
    /// Audio stays held until `allowsAudio` sees a non-refusal digest.
    @discardableResult
    public mutating func created(_ id: String) -> Bool {
        guard isSpeaking, awaitingCreated else { return false }
        awaitingCreated = false
        responseID = id
        return true
    }

    /// Ignore leftover `response.done` while we still wait for our create,
    /// or when the finished id is not the verbatim response.
    ///
    /// Always prefer `eventID` from the done payload. Slower desk turns
    /// (inbox digest, person follow-up fetch) often receive the cancelled
    /// handoff `response.done` *after* `response.created` already flipped
    /// `currentID` to the verbatim id — matching on `currentID` alone remutes Eve.
    public func shouldIgnoreDone(eventID: String? = nil, currentID: String?) -> Bool {
        guard isSpeaking else { return false }
        if awaitingCreated { return true }
        guard let responseID, !responseID.isEmpty else { return true }
        let doneID = eventID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !doneID.isEmpty {
            return doneID != responseID
        }
        if let currentID, currentID != responseID { return true }
        return false
    }

    /// True when this done belongs to the verbatim speak — restore mute / session.
    @discardableResult
    public mutating func finishDone(eventID: String? = nil, currentID: String?) -> Bool {
        guard isSpeaking else { return false }
        if shouldIgnoreDone(eventID: eventID, currentID: currentID) { return false }
        isSpeaking = false
        awaitingCreated = false
        responseID = nil
        heard = ""
        return true
    }

    public mutating func cancel() {
        isSpeaking = false
        awaitingCreated = false
        responseID = nil
        heard = ""
    }
}
