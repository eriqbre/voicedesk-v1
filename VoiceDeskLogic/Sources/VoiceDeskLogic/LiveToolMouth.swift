import Foundation

/// 12:14: one spoken mouth after tools. Not a mute/hold of first PCM.
/// `create_response` is false while tools run; one `response.create` after.
public enum LiveToolMouth: Sendable {
    public struct CreateTrace: Equatable, Sendable {
        public var createResponseOnListen: Bool?
        public var createsBeforeTools: Int
        public var createsAfterTools: Int

        public init(
            createResponseOnListen: Bool?,
            createsBeforeTools: Int,
            createsAfterTools: Int
        ) {
            self.createResponseOnListen = createResponseOnListen
            self.createsBeforeTools = createsBeforeTools
            self.createsAfterTools = createsAfterTools
        }

        /// 83a5c6a noon: VAD created a mouth before tools, then another after.
        public var isNoon1214Leftover: Bool {
            createsBeforeTools >= 1 && createsAfterTools >= 1
        }

        public var isOneMouthAfterTools: Bool {
            createsBeforeTools == 0 && createsAfterTools == 1
        }
    }

    public static func needsClientTools(
        ask: String,
        snapshot: DeskSnapshot,
        isConnected: Bool,
        isOnline: Bool
    ) -> Bool {
        guard isConnected, isOnline else { return false }
        if ConversationPresence.looksLikeMailAsk(ask)
            || ConversationPresence.wantsInboxOverview(ask) {
            return true
        }
        return ConversationPresence.wantsCalendarAsk(ask) && snapshot.events.isEmpty
    }

    public static func shouldSendResponseCreate(toolWait: Bool, alreadyCreated: Bool) -> Bool {
        !toolWait && !alreadyCreated
    }

    /// Production listen-resume wire + VAD auto-create before tools +
    /// a later create after tools. That is the 83a5c6a / 7ef2f6d noon miss.
    public static func sha83a5c6aNoonCreateTrace() -> CreateTrace {
        let flag = createResponse(in: GrokRealtime.listenResumeSessionUpdateObject())
        let before = GrokRealtime.vadCreatesOnSpeechStopped(createResponse: flag) ? 1 : 0
        return CreateTrace(
            createResponseOnListen: flag,
            createsBeforeTools: before,
            createsAfterTools: 1
        )
    }

    /// Production tool-wait wire: `create_response` false, no VAD create,
    /// one `response.create` after tools.
    public static func productToolWaitCreateTrace() -> CreateTrace {
        let flag = createResponse(in: GrokRealtime.toolWaitSessionUpdateObject())
        let before = GrokRealtime.vadCreatesOnSpeechStopped(createResponse: flag) ? 1 : 0
        let after = shouldSendResponseCreate(toolWait: false, alreadyCreated: before > 0) ? 1 : 0
        return CreateTrace(
            createResponseOnListen: flag,
            createsBeforeTools: before,
            createsAfterTools: after
        )
    }

    private static func createResponse(in object: [String: Any]) -> Bool? {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let raw = String(data: data, encoding: .utf8)
        else { return nil }
        return GrokRealtime.createResponse(inSessionUpdate: raw)
    }
}
