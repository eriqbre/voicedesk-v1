import Foundation

/// Leftover Grok `response.done` tracking. Desk speak no longer uses a
/// SPEAK_VERBATIM turn — this stays so a cancelled Grok handoff cannot
/// mute general conversation.
public struct VerbatimSpeakGate: Equatable, Sendable {
    public var isSpeaking = false
    public var awaitingCreated = false
    public var responseID: String?

    public init() {}

    public mutating func begin() {
        isSpeaking = true
        awaitingCreated = true
        responseID = nil
    }

    @discardableResult
    public mutating func created(_ id: String) -> Bool {
        guard isSpeaking, awaitingCreated else { return false }
        awaitingCreated = false
        responseID = id
        return true
    }

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

    @discardableResult
    public mutating func finishDone(eventID: String? = nil, currentID: String?) -> Bool {
        guard isSpeaking else { return false }
        if shouldIgnoreDone(eventID: eventID, currentID: currentID) { return false }
        isSpeaking = false
        awaitingCreated = false
        responseID = nil
        return true
    }

    public mutating func cancel() {
        isSpeaking = false
        awaitingCreated = false
        responseID = nil
    }
}
