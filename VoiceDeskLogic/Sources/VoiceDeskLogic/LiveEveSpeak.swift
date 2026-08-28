import Foundation

/// One speak contract. Live socket up = Eve mouth. Socket down =
/// ClientVoiceSpeech. 83a5c6a `deskSpeakUsesClientTTS()` was hard-true
/// while `speak()` used Eve — two contracts. A later guard-return
/// swallowed audio (6m silence). Foreign `response.done` cleared
/// verbatim mode (stayIdle after version).
public struct LiveEveSpeak: Equatable, Sendable {
    public enum Mouth: String, Equatable, Sendable {
        case eve
        case clientTTS
    }

    public static let eveWireTypes = [
        "session.update",
        "conversation.item.create",
        "response.create"
    ]

    public var mouth: Mouth
    public var wireTypes: [String]
    public var wroteClientTTS: Bool
    public var swallowed: Bool

    public init(
        mouth: Mouth,
        wireTypes: [String],
        wroteClientTTS: Bool,
        swallowed: Bool = false
    ) {
        self.mouth = mouth
        self.wireTypes = wireTypes
        self.wroteClientTTS = wroteClientTTS
        self.swallowed = swallowed
    }

    public static func mouth(
        usesLiveLoop: Bool,
        socketConnected: Bool,
        liveSessionArmed: Bool,
        userWantsVoiceOff: Bool
    ) -> Mouth {
        if GrokRealtime.shouldSpeakViaRealtime(
            usesLiveLoop: usesLiveLoop,
            isConnected: socketConnected && liveSessionArmed,
            userWantsVoiceOff: userWantsVoiceOff
        ) {
            return .eve
        }
        return .clientTTS
    }

    /// Production `speak("1.2.3")` plan. Socket drop after Eve is chosen
    /// writes ClientVoiceSpeech. Never swallow.
    public static func plan(
        text: String,
        socketConnected: Bool,
        liveSessionArmed: Bool = true,
        usesLiveLoop: Bool = true,
        userWantsVoiceOff: Bool = false
    ) -> LiveEveSpeak {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LiveEveSpeak(mouth: .clientTTS, wireTypes: [], wroteClientTTS: false)
        }
        let chosen = mouth(
            usesLiveLoop: usesLiveLoop,
            socketConnected: socketConnected,
            liveSessionArmed: liveSessionArmed,
            userWantsVoiceOff: userWantsVoiceOff
        )
        if chosen == .eve, socketConnected {
            return LiveEveSpeak(mouth: .eve, wireTypes: eveWireTypes, wroteClientTTS: false)
        }
        return LiveEveSpeak(mouth: .clientTTS, wireTypes: [], wroteClientTTS: true)
    }

    public static func bindVerbatimResponseID(
        existing: String?,
        createdID: String?
    ) -> String? {
        GrokRealtime.nonemptyID(existing) ?? GrokRealtime.nonemptyID(createdID)
    }

    /// Foreign `response.done` must not clear verbatim mode.
    public static func shouldRestorePresence(
        doneResponseID: String?,
        verbatimResponseID: String?
    ) -> Bool {
        guard let done = GrokRealtime.nonemptyID(doneResponseID),
              let verbatim = GrokRealtime.nonemptyID(verbatimResponseID)
        else { return false }
        return done == verbatim
    }
}
