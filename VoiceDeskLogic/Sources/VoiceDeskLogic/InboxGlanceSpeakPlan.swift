import Foundation

/// Cache-hot inbox glance: first audio from the local snapshot.
///
/// When the snapshot already has the latest-5, first speak is one short beat.
/// Cards are the list. Do not wait on a Gmail list refresh or a model rewrite.
/// First word does not need the model, so do not call it.
public struct InboxGlanceSpeakPlan: Equatable, Sendable {
    public static let localCacheStage = "localCache"
    public static let heuristicStage = "heuristic"
    public static let gmailListStage = "gmailList"
    public static let xaiGlanceStage = "xaiGlance"
    public static let localHeuristicSource = "local-heuristic"
    public static let eveSpokenSource = "eve"

    public var intent: String
    public var spokenSource: String
    public var spokenText: String
    public var stagesBeforeFirstAudio: [String]
    public var waitsOnGmailList: Bool
    public var waitsOnModel: Bool
    public var cardCount: Int
    public var voiceLogNotes: [String]

    public init(
        intent: String,
        spokenSource: String,
        spokenText: String,
        stagesBeforeFirstAudio: [String],
        waitsOnGmailList: Bool,
        waitsOnModel: Bool,
        cardCount: Int,
        voiceLogNotes: [String]
    ) {
        self.intent = intent
        self.spokenSource = spokenSource
        self.spokenText = spokenText
        self.stagesBeforeFirstAudio = stagesBeforeFirstAudio
        self.waitsOnGmailList = waitsOnGmailList
        self.waitsOnModel = waitsOnModel
        self.cardCount = cardCount
        self.voiceLogNotes = voiceLogNotes
    }

    /// Latest-5 view is already on disk. First word must not wait on Gmail or xAI.
    public static func hasHotLatestFive(_ snapshot: DeskSnapshot) -> Bool {
        !snapshot.glanceEmails.isEmpty
    }

    /// Inbox-overview may still list-refresh when the glance window is empty.
    /// Live VAD: Eve is first audio — do not skip Gmail so she has facts.
    public static func shouldRefreshGmailListBeforeFirstSpeak(
        ask: String,
        snapshot: DeskSnapshot,
        isConnected: Bool,
        isOnline: Bool,
        liveVADTurn: Bool = false
    ) -> Bool {
        guard isConnected, isOnline else { return false }
        if liveVADTurn {
            return ConversationPresence.looksLikeMailAsk(ask)
                || ConversationPresence.wantsInboxOverview(ask)
        }
        guard ConversationPresence.wantsInboxOverview(ask) else { return false }
        return !hasHotLatestFive(snapshot)
    }

    /// 83a5c6a first-audio hole: skipped tools + list stub.
    public static func isSkippedGlanceListStub(_ plan: InboxGlanceSpeakPlan) -> Bool {
        plan.voiceLogNotes.contains("firstAudio skipped xaiGlance")
            && plan.voiceLogNotes.contains("firstAudio skipped gmailList")
            && InboxGlance.isShortSpokenAck(plan.spokenText)
    }

    /// Live VAD: cards from cache, tools run, Eve speaks. No client stub.
    public static func liveVAD(
        ask: String,
        snapshot: DeskSnapshot,
        now: Date = Date()
    ) -> InboxGlanceSpeakPlan {
        let replay = VoiceTurnReplay.play(
            utterance: ask,
            context: DeskContext(isConnected: true, snapshot: snapshot)
        )
        let emails = snapshot.glanceEmails
        var plan = InboxGlanceSpeakPlan(
            intent: replay.intent,
            spokenSource: eveSpokenSource,
            // 677abb9 put spokenInbox here and AppModel spoke it. That
            // from/subject dump was the live mouth. Eve speaks after tools.
            spokenText: "",
            stagesBeforeFirstAudio: [gmailListStage, xaiGlanceStage],
            waitsOnGmailList: true,
            waitsOnModel: true,
            cardCount: min(emails.count, InboxGlance.overviewLimit),
            voiceLogNotes: [
                "firstAudio: eve",
                gmailListStage,
                xaiGlanceStage
            ]
        )
        if let age = GoogleSyncPolicy.cacheAgeNote(lastSyncedAt: snapshot.lastSyncedAt, now: now) {
            plan.voiceLogNotes.append(age)
        }
        return plan
    }

    public static func firstAudioWaitsOnGmailList(_ stages: [String]) -> Bool {
        stages.contains(gmailListStage)
    }

    public static func firstAudioWaitsOnModel(_ stages: [String]) -> Bool {
        stages.contains(xaiGlanceStage)
    }

    /// First audio from the ask + snapshot. Sync — no glancer, no list.
    public static func fromCachedEmails(
        _ emails: [EmailItem],
        ask: String = "",
        fallbackText: String
    ) -> InboxGlanceSpeakPlan {
        let window = Array(emails.prefix(InboxGlance.overviewLimit))
        if window.isEmpty {
            return InboxGlanceSpeakPlan(
                intent: "inbox-overview",
                spokenSource: localHeuristicSource,
                spokenText: fallbackText,
                stagesBeforeFirstAudio: [],
                waitsOnGmailList: false,
                waitsOnModel: false,
                cardCount: 0,
                voiceLogNotes: [
                    "firstAudio: local-heuristic",
                    "firstAudio skipped xaiGlance",
                    "firstAudio skipped gmailList"
                ]
            )
        }
        let spoken = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? InboxGlance.spokenInbox(ask: ask, emails: window)
            : fallbackText
        return InboxGlanceSpeakPlan(
            intent: "inbox-overview",
            spokenSource: localHeuristicSource,
            spokenText: spoken,
            stagesBeforeFirstAudio: [localCacheStage, heuristicStage],
            waitsOnGmailList: false,
            waitsOnModel: false,
            cardCount: window.count,
            voiceLogNotes: [
                "firstAudio: localCache+heuristic",
                "firstAudio skipped xaiGlance",
                "firstAudio skipped gmailList"
            ]
        )
    }

    /// Cache-hot glance walk. Assert intent / timing / source — not Eve’s wording.
    public static func cacheHot(
        ask: String,
        snapshot: DeskSnapshot,
        now: Date = Date()
    ) -> InboxGlanceSpeakPlan {
        let replay = VoiceTurnReplay.play(
            utterance: ask,
            context: DeskContext(isConnected: true, snapshot: snapshot)
        )
        let emails = snapshot.glanceEmails
        var plan = fromCachedEmails(emails, ask: ask, fallbackText: replay.reply)
        plan.intent = replay.intent
        if let age = GoogleSyncPolicy.cacheAgeNote(lastSyncedAt: snapshot.lastSyncedAt, now: now) {
            plan.voiceLogNotes.append(age)
        }
        return plan
    }
}
