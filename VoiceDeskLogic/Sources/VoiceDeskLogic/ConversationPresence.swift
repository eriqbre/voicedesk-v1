import Foundation

/// Spoken presence: a person, not a command menu.
/// Cards attach only when the ask maps to desk evidence.
public enum ConversationPresence {
    /// First-open coach. Next action is tap Talk.
    public static let firstRunWelcome =
        "I’m a voice assistant. Tap Talk and speak — that’s the whole thing. Want to see how email and listings look once Google is connected? There’s a sample below. Not live Gmail. Not MLS."

    /// Returning presence. Short. No wizard.
    public static let returningWelcome =
        "Hey — I’m here. Tap Talk whenever you want."

    /// Tests and first-run default.
    public static let welcomeText = firstRunWelcome

    public static let justTalk = "Just talk to me"
    public static let deskPreview = "Show me a sample email and listing"
    public static let draftStarter = "Show me a draft confirm"
    public static let justTalkReply = "Tap Talk below and say anything. I’ll answer."
    public static let deskPreviewReply =
        "These are samples — not live Gmail, not MLS. Once Google is connected, your inbox and listings show up like this."
    public static let talkHint = "Tap Talk and speak"

    /// First-run desk preview chip. XCUITest still uses `suggestion.tour`.
    public static let tourOffer = deskPreview
    public static let deskStarter = deskPreview

    public static let starterChips = [justTalk, deskPreview, draftStarter]
    public static let connectGoogleChip = "Connect Google"
    /// Shown with the Connect Google card. Never contradicts the button.
    public static let connectHowToReply = "Tap Connect Google on the card below."
    public static let connectCoach = connectHowToReply
    public static let returningConnectChipHint = "Connect Google when you’re ready — no rush."

    public enum Topic: String, Sendable, Equatable {
        case inbox
        case listing
        case draft
        case statute
        case google
        case calendar
        case task
        case version
        case general
    }

    public struct Plan: Equatable, Sendable {
        public let topic: Topic
        public let text: String

        public var attachesCards: Bool { topic != .general && topic != .version }

        public init(topic: Topic, text: String) {
            self.topic = topic
            self.text = text
        }
    }

    public static func plan(for raw: String) -> Plan {
        plan(for: raw, context: .disconnected)
    }

    public static func plan(for raw: String, context: DeskContext) -> Plan {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        if isJustTalk(text) {
            return Plan(topic: .general, text: justTalkReply)
        }

        if wantsDeskPreview(text) {
            return Plan(topic: .inbox, text: deskPreviewReply)
        }

        if wantsConnectGoogle(text) {
            return Plan(topic: .google, text: googleReply(context: context))
        }

        if wantsVersionAsk(text) {
            return Plan(topic: .version, text: spokenIdentityLine(for: text, identity: .unknown))
        }

        if wantsInbox(text) {
            return Plan(topic: .inbox, text: inboxReply(context: context))
        }

        if contains(lower, ["my calendar", "on my calendar", "what's on my calendar", "whats on my calendar", "schedule today", "what meetings"])
            || (contains(lower, ["calendar", "schedule"]) && contains(lower, ["my", "today", "upcoming"])) {
            return Plan(topic: .calendar, text: calendarReply(context: context))
        }

        if contains(lower, ["my tasks", "what tasks", "to-do", "todo", "open tasks"])
            || (contains(lower, ["task"]) && contains(lower, ["my", "have", "open"])) {
            return Plan(topic: .task, text: taskReply(context: context))
        }

        if contains(lower, ["beach drive", "1842", "my listing", "the listing", "showing saturday", "the house"])
            || (contains(lower, ["listing", "showing"]) && !contains(lower, ["list the"])) {
            return Plan(
                topic: .listing,
                text: "1842 Beach Drive — I have it as inferred yours from that thread."
            )
        }

        if contains(lower, ["draft confirm", "show me a draft", "draft a reply", "reply to jordan", "send that", "write him back", "write her back"])
            || (contains(lower, ["reply", "draft"]) && contains(lower, ["email", "jordan", "send", "confirm"])) {
            return Plan(topic: .draft, text: draftReply(context: context))
        }

        if contains(lower, ["statute", "florida law", "disclosure", "475.278", "brokerage relationship"])
            || (contains(lower, ["legal", "compliance"]) && contains(lower, ["florida", "law", "disclosure"])) {
            return Plan(
                topic: .statute,
                text: "Florida wants the brokerage relationship on the table before you show as a single agent. I’m not your lawyer."
            )
        }

        return Plan(topic: .general, text: generalReply(for: text, lower: lower, context: context))
    }

    public static func cards(for topic: Topic, googleConnected: Bool) -> [ContentCard] {
        cards(for: topic, context: DeskContext(isConnected: googleConnected))
    }

    public static func cards(for topic: Topic, context: DeskContext) -> [ContentCard] {
        switch topic {
        case .inbox:
            if context.isConnected {
                return context.snapshot.emails.prefix(5).map { .email($0) }
            }
            return [.connectGoogle(context.connectItem)]
        case .calendar:
            if context.isConnected {
                return context.snapshot.events.prefix(3).map { .calendar($0) }
            }
            return [.connectGoogle(context.connectItem)]
        case .task:
            if context.isConnected {
                return context.snapshot.tasks.prefix(5).map { .task($0) }
            }
            return [.connectGoogle(context.connectItem)]
        case .listing:
            return [.listing(SampleData.listing()), .person(SampleData.buyer()), .person(SampleData.partner())]
        case .draft:
            if context.isConnected, let email = context.snapshot.emails.first {
                return [.draftConfirm(GoogleJSONMapping.draftReply(to: email))]
            }
            return [.draftConfirm(SampleData.draftReply())]
        case .statute:
            return [.statute(SampleData.statute())]
        case .google:
            return [.connectGoogle(context.connectItem)]
        case .version, .general:
            return []
        }
    }

    public static func inboxReply(context: DeskContext) -> String {
        if !context.clientIDConfigured {
            return GoogleAuthSnapshot.missingClientIDCopy
        }
        if !context.isConnected {
            return "I don’t have your live inbox yet. Tap Connect Google on the card below."
        }
        if context.snapshot.emails.isEmpty {
            if context.isOnline {
                return "Google is connected, but I don’t have any synced threads yet. I’m not inventing mail."
            }
            return "I’m offline and the last-synced inbox is empty. I won’t invent mail."
        }
        if !context.isOnline {
            return "Here’s the last-synced inbox. I’m offline, so this may be stale."
        }
        return inboxOverviewCopy(context.snapshot.emails)
    }

    public static func inboxOverviewCopy(_ emails: [EmailItem]) -> String {
        let recent = Array(emails.prefix(InboxGlance.overviewLimit))
        guard !recent.isEmpty else {
            return "Google is connected, but I don’t have any synced threads yet. I’m not inventing mail."
        }
        return InboxGlance.heuristic(recent)
    }

    public static func calendarReply(context: DeskContext) -> String {
        if !context.isConnected {
            return "I don’t have your live calendar yet. Tap Connect Google on the card below."
        }
        if context.snapshot.events.isEmpty {
            return "Google is connected. Nothing upcoming is in the last sync — I’m not inventing events."
        }
        let first = context.snapshot.events[0]
        return "Next up: \(first.title), \(first.whenLabel). Only synced events."
    }

    public static func taskReply(context: DeskContext) -> String {
        if !context.isConnected {
            return "I don’t have your live tasks yet. Tap Connect Google on the card below."
        }
        if context.snapshot.tasks.isEmpty {
            return "Google is connected. No open tasks in the last sync."
        }
        return "You have \(context.snapshot.tasks.count) open task\(context.snapshot.tasks.count == 1 ? "" : "s") from the last sync."
    }

    public static func draftReply(context: DeskContext) -> String {
        if context.isConnected, context.snapshot.emails.first != nil {
            return "Here’s exactly what I’d send to the latest synced thread. Nothing leaves until you confirm."
        }
        return "Here’s exactly what I’d send. Nothing leaves until you confirm."
    }

    public static func alreadyConnectedReply(email: String) -> String {
        "You’re already connected as \(email). Use Disconnect on the card if you need to switch."
    }

    public static func googleReply(context: DeskContext) -> String {
        if context.isConnected {
            let email = context.auth.email ?? context.snapshot.accountEmail ?? "your Google account"
            return alreadyConnectedReply(email: email)
        }
        if !context.clientIDConfigured {
            return GoogleAuthSnapshot.missingClientIDCopy
        }
        return connectHowToReply
    }

    public struct DeskEvidence: Equatable, Sendable {
        public var topic: Topic
        public var text: String
        public var cards: [ContentCard]
        public var focusedEmail: EmailItem?
        public var shouldFetchBody: Bool
        public var expandEarlierMessages: Bool
        public var shouldSearchGmail: Bool
        public var gmailQuery: String?
        public var gmailPlan: GmailSearchPlan?
        public var searchAsk: String?
        /// Inbox-overview / list intents must not keep a prior person/thread sticky.
        public var resetsFocusedEmail: Bool
        /// Upgrade the fallback glance with one batched AI call; keep compact cards.
        public var shouldGlanceInbox: Bool
        /// After “no / not that one” the next short ack (“Yeah”) stays desk.
        public var keepsSenderRefine: Bool

        public init(
            topic: Topic,
            text: String,
            cards: [ContentCard],
            focusedEmail: EmailItem? = nil,
            shouldFetchBody: Bool = false,
            expandEarlierMessages: Bool = false,
            shouldSearchGmail: Bool = false,
            gmailQuery: String? = nil,
            gmailPlan: GmailSearchPlan? = nil,
            searchAsk: String? = nil,
            resetsFocusedEmail: Bool = false,
            shouldGlanceInbox: Bool = false,
            keepsSenderRefine: Bool = false
        ) {
            self.topic = topic
            self.text = text
            self.cards = cards
            self.focusedEmail = focusedEmail
            self.shouldFetchBody = shouldFetchBody
            self.expandEarlierMessages = expandEarlierMessages
            self.shouldSearchGmail = shouldSearchGmail
            self.gmailQuery = gmailQuery
            self.gmailPlan = gmailPlan
            self.searchAsk = searchAsk
            self.resetsFocusedEmail = resetsFocusedEmail
            self.shouldGlanceInbox = shouldGlanceInbox
            self.keepsSenderRefine = keepsSenderRefine
        }

        public var claimsCardWithoutAttaching: Bool {
            ConversationPresence.replyMentionsCard(text) && cards.isEmpty
        }

        public var awaitsSearchClarify: Bool {
            if text == ConversationPresence.emailNeedMoreReply && cards.isEmpty {
                return true
            }
            return text == ConversationPresence.gmailSearchSeveralReply
        }
    }

    public static func replyMentionsCard(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return contains(lower, ["on the card", "email card", "calendar card", "cards below", "waiting on the"])
    }

    /// Connected Google + desk ask: the client owns the turn. Grok must not speak.
    public static func ownsConnectedDeskTurn(
        _ raw: String,
        pendingSearchClarify: Bool = false,
        hasClarifyMatches: Bool = false,
        hasFocusedEmail: Bool = false,
        pendingSenderRefine: Bool = false
    ) -> Bool {
        let deskFollow = pendingSearchClarify || hasClarifyMatches || hasFocusedEmail || pendingSenderRefine
        if deskFollow, isSenderRejectRefine(raw) {
            return true
        }
        if pendingSenderRefine, isClarifyPick(raw) {
            return true
        }
        if (pendingSearchClarify || hasClarifyMatches), isClarifyPick(raw) {
            return true
        }
        // “Who’s it from?” — next utterance is a brand. Not after multi-match cards.
        if pendingSearchClarify, !hasClarifyMatches,
           GmailSearchQuery.plan(from: raw, treatAsBrand: true) != nil {
            return true
        }
        return looksLikeMailAsk(raw) || wantsCalendarAsk(raw) || wantsTaskAsk(raw) || wantsVersionAsk(raw)
    }

    /// After a named-person card, reject + optional topic stays desk — never Grok.
    ///
    /// Reject family (add the next dogfood phrase here, then add a fixture):
    /// - **reject**: no / nope / not that / not that one / not this one /
    ///   the other one / the other / wrong one / that’s not it / not the one
    /// - **reject + topic**: “No. Not that one. … regarding Fleeman Road.”
    public static func isSenderRejectRefine(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if contains(lower, [
            "not that one", "not this one", "the other one", "the other",
            "not that", "wrong one", "that's not", "thats not",
            "no not that", "not the one", "not this"
        ]) {
            return true
        }
        let compact = lower
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .split { $0.isWhitespace }
            .map(String.init)
            .filter { !$0.isEmpty }
        if compact == ["no"] || compact == ["nope"] || compact == ["no", "no"] {
            return true
        }
        return false
    }

    /// After “I found a few matches. Which one?” — recency / ordinal, not live Grok.
    ///
    /// Selection family (add the next dogfood phrase here, then add a fixture):
    /// - **newest** (`sentAtLabel`): last / the last one / latest / the latest /
    ///   most recent / the most recent one / newest / the newest / that one / that /
    ///   this one / the top one / the last email
    /// - **ordinal** (offered-card order): the first / the second / the third / number one
    /// - **short leftover default** (pending clarify only): filler-only or ≤2 tokens
    ///   with no interrogative — e.g. “mm hmm”, “ok that”, “yeah that” → newest.
    ///   “What’s for dinner?” stays with Grok. Named sender / inbox-overview / calendar
    ///   are never a pick.
    public static func isClarifyPick(_ raw: String) -> Bool {
        clarifyPickKind(raw) != nil
    }

    public enum ClarifyPickKind: Equatable, Sendable {
        case newest
        case ordinal(Int)
    }

    public static func clarifyPickKind(_ raw: String) -> ClarifyPickKind? {
        if GmailSearchQuery.hasSenderPattern(raw) { return nil }
        if wantsInboxOverview(raw) || wantsCalendarAsk(raw) || wantsTaskAsk(raw) || wantsVersionAsk(raw) { return nil }
        let normalized = normalizeClarifyPick(raw)
        switch normalized {
        case "the most recent one", "the most recent", "most recent one", "most recent",
             "the latest one", "the latest", "latest one", "latest",
             "the newest one", "the newest", "newest one", "newest",
             "the last one", "last one", "the last", "last",
             "that last one", "the last email",
             "that one", "this one", "that", "this",
             "the top one", "top one", "the top":
            return .newest
        case "the first one", "the first", "first one", "first",
             "number one", "the number one":
            return .ordinal(0)
        case "the second one", "the second", "second one", "second",
             "number two", "the number two":
            return .ordinal(1)
        case "the third one", "the third", "third one", "third",
             "number three", "the number three":
            return .ordinal(2)
        default:
            return shortClarifyDefaultKind(normalized)
        }
    }

    public static func pickClarifiedEmail(ask: String, candidates: [EmailItem]) -> EmailItem? {
        guard !candidates.isEmpty, let kind = clarifyPickKind(ask) else { return nil }
        let ranked = EmailRecency.newestFirst(candidates)
        switch kind {
        case .newest:
            return ranked.first
        case .ordinal(let index):
            guard candidates.indices.contains(index) else { return nil }
            return candidates[index]
        }
    }

    /// Spoken leftovers after “Which one?” — filler-only or two tokens, no question word.
    /// Defaults to newest so Grok never jumps in with “the client will jump in.”
    private static func shortClarifyDefaultKind(_ normalized: String) -> ClarifyPickKind? {
        let words = normalized.split { $0.isWhitespace }.map(String.init)
        if words.isEmpty { return .newest }
        let interrogative: Set<String> = [
            "what", "whats", "who", "where", "when", "why", "how",
            "dinner", "weather", "which"
        ]
        if words.contains(where: { interrogative.contains($0) }) { return nil }
        if words.count <= 2 { return .newest }
        return nil
    }

    private static func normalizeClarifyPick(_ raw: String) -> String {
        var lower = raw.lowercased()
        lower = lower.replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
        let filler: Set<String> = [
            "um", "uh", "please", "yeah", "yes", "yep", "yup", "sure",
            "okay", "ok", "alright", "very", "just",
            "mm", "hmm", "mhm", "huh"
        ]
        let words = lower
            .split { $0.isWhitespace }
            .map(String.init)
            .filter { !$0.isEmpty && !filler.contains($0) }
        return words.joined(separator: " ")
    }

    /// Grok refusal or routing meta. Must never stay on the transcript after a local desk fetch.
    public static func isGrokDeskRefusal(_ raw: String) -> Bool {
        isGrokDeskMeta(raw)
    }

    /// Handoff / capability narration. Client owns desk turns — Grok must stay silent.
    public static func isGrokDeskHandoff(_ raw: String) -> Bool {
        contains(raw.lowercased(), [
            "let the app handle",
            "leave that to the app",
            "leave it to the app",
            "hand that off",
            "handing that off",
            "hand this off",
            "look that up in the app",
            "look it up in the app",
            "have the app look",
            "have voicedesk look",
            "look it up in voicedesk",
            "let voicedesk handle",
            "the app will handle",
            "the app can handle",
            "i'll let the app",
            "i’ll let the app",
            "i will let the app",
            "checking the app",
            "pulling that up in the app",
            "i'll pull that up in the app",
            "i’ll pull that up in the app",
            "stay quiet",
            "i'll stay quiet",
            "i’ll stay quiet",
            "ios app handles",
            "the ios app",
            "app handles gmail",
            "handles gmail"
        ])
    }

    public static func isGrokDeskMeta(_ raw: String) -> Bool {
        if isGrokDeskHandoff(raw) { return true }
        return contains(raw.lowercased(), [
            "can't pull",
            "cannot pull",
            "can’t pull",
            "not in my last sync",
            "not in the last sync",
            "not in last sync",
            "all i have is",
            "all I have is",
            "don't have the full",
            "don’t have the full",
            "do not have the full",
            "don't have the entire",
            "don’t have the entire",
            "can't get the full",
            "cannot get the full",
            "only have the snippet",
            "only have a snippet",
            "snippet only"
        ])
    }

    public static func looksLikeMailAsk(_ raw: String) -> Bool {
        if wantsDeskPreview(raw) || wantsConnectGoogle(raw) || isJustTalk(raw) || wantsVersionAsk(raw) {
            return false
        }
        if wantsCalendarDetails(raw), !contains(raw.lowercased(), ["email", "mail", "note", "message", "thread"]) {
            return false
        }
        if wantsTaskAsk(raw), !contains(raw.lowercased(), ["email", "mail", "note", "message", "thread"]) {
            return false
        }
        if wantsFullThread(raw) || wantsEmailFollowUp(raw) || wantsShowEmail(raw)
            || wantsInbox(raw) || wantsInboxOverview(raw) {
            return true
        }
        // A bare person name is not desk intent. Trivia (“what year did John Wick…”) stays with Grok.
        if wantsEmailBody(raw), hasDeskMailIntent(raw) {
            return true
        }
        if hasDeskMailIntent(raw),
           (GmailSearchQuery.hasSenderPattern(raw) || GmailSearchQuery.query(from: raw) != nil) {
            return true
        }
        return false
    }

    /// Email / inbox / send-me phrasing. Not a celebrity name inside a general question.
    public static func hasDeskMailIntent(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if contains(lower, [
            "email", "emails", "mail", "inbox", "message", "messages",
            "thread", "note", "notes"
        ]) {
            return true
        }
        if contains(lower, [
            "send me", "sent me", "sends me", "emailed", "mailed me",
            "wrote me", "written me", "from:"
        ]) {
            return true
        }
        // “Lauren wrote regarding Fleeman Road” — no “email” word required.
        if GmailSearchQuery.hasSenderPattern(raw),
           contains(lower, ["wrote", "written", "regarding", "looking for the one"]) {
            return true
        }
        return false
    }

    public static func wantsCalendarAsk(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if wantsCalendarDetails(raw) { return true }
        if wantsCalendarOverview(raw) { return true }
        return contains(lower, ["my calendar", "on my calendar", "what's on my calendar", "whats on my calendar", "schedule today", "what meetings"])
            || (contains(lower, ["calendar", "schedule"]) && contains(lower, ["my", "today", "upcoming"]))
    }

    /// Local build identity — not live Grok, not calendar.
    /// Default family (version / build / on the phone) speaks marketing + build.
    /// SHA family speaks the baked short SHA. “What’s on my calendar” stays calendar.
    public static func wantsVersionAsk(_ raw: String) -> Bool {
        if wantsCalendarAsk(raw) || wantsTaskAsk(raw) { return false }
        if hasDeskMailIntent(raw) { return false }
        return wantsSHAAsk(raw) || wantsMarketingVersionAsk(raw)
    }

    /// SHA / git-hash family. Synonyms, not one golden phrase.
    public static func wantsSHAAsk(_ raw: String) -> Bool {
        if wantsCalendarAsk(raw) || wantsTaskAsk(raw) { return false }
        if hasDeskMailIntent(raw) { return false }
        let lower = raw.lowercased()
        if contains(lower, [
            "what sha",
            "which sha",
            "what's the sha",
            "whats the sha",
            "git sha",
            "git hash",
            "what git hash",
            "which git hash",
            "what's the git hash",
            "whats the git hash"
        ]) {
            return true
        }
        return contains(lower, ["sha"]) && contains(lower, ["what", "whats", "which"])
    }

    public static func spokenIdentityLine(for raw: String, identity: BuildIdentity) -> String {
        wantsSHAAsk(raw) ? identity.spokenSHALine : identity.spokenLine
    }

    private static func wantsMarketingVersionAsk(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if contains(lower, [
            "on the phone",
            "on this phone",
            "on my phone"
        ]) {
            return true
        }
        if contains(lower, [
            "what version",
            "which version",
            "what's the version",
            "whats the version",
            "what build",
            "which build",
            "what's the build",
            "whats the build"
        ]) {
            return true
        }
        if contains(lower, ["version"]) && contains(lower, ["what", "whats", "which"]) {
            return true
        }
        return lower.contains("build")
            && contains(lower, ["this", "we on", "am i on", "are we"])
    }

    private static func versionEvidence(for raw: String) -> DeskEvidence {
        DeskEvidence(
            topic: .version,
            text: spokenIdentityLine(for: raw, identity: .unknown),
            cards: [],
            resetsFocusedEmail: true
        )
    }

    /// List / digest of upcoming events — not a named reservation or “that event”.
    public static func wantsCalendarOverview(_ raw: String) -> Bool {
        if wantsCalendarDetails(raw) { return false }
        let lower = raw.lowercased()
        if contains(lower, [
            "what's the latest on my calendar",
            "whats the latest on my calendar",
            "what's on my calendar",
            "whats on my calendar",
            "latest on my calendar",
            "recent on my calendar",
            "on my calendar this week",
            "what's on my calendar this week",
            "whats on my calendar this week",
            "my calendar this week"
        ]) {
            return true
        }
        let latest = contains(lower, ["latest", "recent"])
        if latest, contains(lower, ["my calendar", "on my calendar", "the calendar"]) {
            return true
        }
        return wantsCalendarListPhrase(lower) && !GmailSearchQuery.hasSenderPattern(raw)
    }

    private static func wantsCalendarListPhrase(_ lower: String) -> Bool {
        contains(lower, ["my calendar", "on my calendar", "what's on my calendar", "whats on my calendar", "schedule today", "what meetings"])
            || (contains(lower, ["calendar", "schedule"]) && contains(lower, ["my", "today", "upcoming"]))
    }

    public static func wantsTaskAsk(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return contains(lower, ["my tasks", "what tasks", "to-do", "todo", "open tasks"])
            || (contains(lower, ["task"]) && contains(lower, ["my", "have", "open"]))
    }

    /// Local path that always attaches evidence when the spoken copy mentions a card.
    public static func deskEvidence(
        for raw: String,
        context: DeskContext,
        focusedEmail: EmailItem? = nil,
        pendingSearchClarify: Bool = false,
        clarifyMatches: [EmailItem] = [],
        pendingSenderRefine: Bool = false
    ) -> DeskEvidence? {
        if wantsDeskPreview(raw) || wantsConnectGoogle(raw) || isJustTalk(raw) {
            return nil
        }

        if wantsVersionAsk(raw) {
            return versionEvidence(for: raw)
        }

        if wantsCalendarAsk(raw) {
            if wantsCalendarOverview(raw) {
                return calendarOverviewEvidence(context: context)
            }
            if let event = matchingCalendar(for: raw, in: context.snapshot.events) {
                return DeskEvidence(
                    topic: .calendar,
                    text: calendarDetailsReply(event),
                    cards: [.calendar(event)]
                )
            }
            if context.isConnected {
                if wantsCalendarDetails(raw) || GmailSearchQuery.hasSenderPattern(raw) {
                    return DeskEvidence(
                        topic: .calendar,
                        text: calendarMissReply,
                        cards: []
                    )
                }
                return calendarOverviewEvidence(context: context)
            }
        }

        if context.isConnected, wantsTaskAsk(raw) {
            if let task = matchingTask(for: raw, in: context.snapshot.tasks) {
                return DeskEvidence(
                    topic: .task,
                    text: taskReply(context: context),
                    cards: [.task(task)]
                )
            }
            if context.snapshot.tasks.isEmpty || GmailSearchQuery.query(from: raw) != nil {
                return DeskEvidence(topic: .task, text: taskMissReply, cards: [])
            }
            return DeskEvidence(
                topic: .task,
                text: taskReply(context: context),
                cards: cards(for: .task, context: context)
            )
        }

        let deskFollow = pendingSearchClarify || pendingSenderRefine || focusedEmail != nil || !clarifyMatches.isEmpty
        if deskFollow, isSenderRejectRefine(raw) {
            return rejectRefineEvidence(
                ask: raw,
                context: context,
                focused: focusedEmail,
                clarifyMatches: clarifyMatches
            )
        }

        if pendingSenderRefine, isClarifyPick(raw) {
            if let picked = pickClarifiedEmail(
                ask: raw,
                candidates: clarifyMatches.isEmpty ? [focusedEmail].compactMap { $0 } : clarifyMatches
            ) ?? focusedEmail {
                if wantsFullThread(raw) {
                    return threadEvidence(picked)
                }
                return emailEvidence(picked)
            }
        }

        if pendingSearchClarify || !clarifyMatches.isEmpty {
            if isClarifyPick(raw) {
                if let picked = pickClarifiedEmail(
                    ask: raw,
                    candidates: clarifyMatches.isEmpty ? [focusedEmail].compactMap { $0 } : clarifyMatches
                ) {
                    if wantsFullThread(raw) {
                        return threadEvidence(picked)
                    }
                    return emailEvidence(picked)
                }
                return DeskEvidence(
                    topic: .inbox,
                    text: clarifyMatches.isEmpty ? emailNeedMoreReply : gmailSearchSeveralReply,
                    cards: EmailItem.listCards(clarifyMatches)
                )
            }
            // Brand-as-sender is for “Who’s it from?” (no cards yet). After “Which one?”
            // with compact cards, a new question is not a Gmail search.
            if pendingSearchClarify, clarifyMatches.isEmpty, context.isConnected,
               let plan = GmailSearchQuery.plan(from: raw, treatAsBrand: true) {
                return searchEvidence(ask: raw, plan: plan, expandEarlier: wantsFullThread(raw))
            }
        }

        if wantsInboxOverview(raw) {
            return inboxOverviewEvidence(context: context)
        }

        if wantsFullThread(raw) {
            if let named = namedMailEvidence(
                ask: raw,
                context: context,
                focused: focusedEmail,
                expandEarlier: true
            ) {
                return named
            }
            if let email = resolveThreadEmail(for: raw, context: context, focusedEmail: focusedEmail) {
                return threadEvidence(email, resetsFocus: namedSenderClearsSticky(raw, focused: focusedEmail, owner: context.mailboxOwner))
            }
            if context.isConnected, let plan = GmailSearchQuery.plan(from: raw) {
                return searchEvidence(
                    ask: raw,
                    plan: plan,
                    expandEarlier: true,
                    resetsFocus: namedSenderClearsSticky(raw, focused: focusedEmail, owner: context.mailboxOwner)
                )
            }
            if GmailSearchQuery.hasSenderPattern(raw) {
                return namedSenderMissEvidence(ask: raw, focused: focusedEmail, hasInbox: !context.snapshot.emails.isEmpty, owner: context.mailboxOwner)
            }
            if !context.snapshot.emails.isEmpty {
                return inboxEvidence(context: context, followUp: true)
            }
            if context.isConnected || focusedEmail != nil {
                return DeskEvidence(
                    topic: .inbox,
                    text: emailBodyUnknownReply(hasInbox: false),
                    cards: []
                )
            }
        }

        if looksLikeMailAsk(raw), !wantsCalendarDetails(raw) {
            if let named = namedMailEvidence(
                ask: raw,
                context: context,
                focused: focusedEmail,
                expandEarlier: wantsFullThread(raw)
            ) {
                return named
            }
            if GmailSearchQuery.hasSenderPattern(raw) {
                if context.isConnected, let plan = GmailSearchQuery.plan(from: raw) {
                    return searchEvidence(
                        ask: raw,
                        plan: plan,
                        expandEarlier: wantsFullThread(raw),
                        resetsFocus: namedSenderClearsSticky(raw, focused: focusedEmail, owner: context.mailboxOwner)
                    )
                }
                return namedSenderMissEvidence(ask: raw, focused: focusedEmail, hasInbox: !context.snapshot.emails.isEmpty, owner: context.mailboxOwner)
            }
            if wantsEmailFollowUp(raw) {
                if let focusedEmail {
                    return emailEvidence(focusedEmail)
                }
                if !context.snapshot.emails.isEmpty {
                    return inboxEvidence(context: context, followUp: true)
                }
                if context.isConnected, let plan = GmailSearchQuery.plan(from: raw) {
                    return searchEvidence(ask: raw, plan: plan, expandEarlier: false)
                }
                return DeskEvidence(
                    topic: .inbox,
                    text: notSeeingCardsReply(hasInbox: false),
                    cards: []
                )
            }
            if wantsInbox(raw), isBareInboxList(raw) {
                return inboxEvidence(context: context, followUp: false)
            }
            if context.isConnected, let plan = GmailSearchQuery.plan(from: raw) {
                return searchEvidence(ask: raw, plan: plan, expandEarlier: wantsFullThread(raw))
            }
            if context.isConnected {
                return DeskEvidence(
                    topic: .inbox,
                    text: emailNeedMoreReply,
                    cards: []
                )
            }
            if wantsInbox(raw) {
                return inboxEvidence(context: context, followUp: false)
            }
        }

        return nil
    }

    public static func wantsInbox(_ raw: String) -> Bool {
        if wantsInboxOverview(raw) { return true }
        let lower = raw.lowercased()
        if contains(lower, [
            "what's in my inbox",
            "whats in my inbox",
            "what emails do i have",
            "what email do i have",
            "other emails",
            "emails i have today",
            "emails today",
            "show me my emails",
            "show me my inbox",
            "show my emails",
            "what other emails",
            "what emails do i"
        ]) {
            return true
        }
        if lower.contains("inbox") { return true }
        return contains(lower, ["email", "emails", "mail"])
            && contains(lower, ["have", "today", "other", "list", "synced"])
            && !wantsSpecificEmail(raw)
    }

    /// List / digest of recent mail — not a person or last-thread follow-up.
    public static func wantsInboxOverview(_ raw: String) -> Bool {
        if GmailSearchQuery.hasSenderPattern(raw) { return false }
        let lower = raw.lowercased()
        if contains(lower, [
            "what's in my inbox",
            "whats in my inbox",
            "what emails do i have",
            "what email do i have",
            "other emails",
            "emails i have today",
            "emails today",
            "show me my emails",
            "show me my inbox",
            "show my emails",
            "what other emails"
        ]) {
            return true
        }
        if lower.contains("inbox"), !contains(lower, ["that inbox"]) {
            return true
        }
        if contains(lower, ["latest emails", "recent emails"]) {
            return true
        }
        let recent = contains(lower, ["latest", "recent"])
        let mail = contains(lower, ["email", "emails", "mail"])
        if recent, mail, contains(lower, ["my"]) {
            return true
        }
        if contains(lower, ["summarize", "summary of", "summary"]), mail, contains(lower, ["my"]) {
            return true
        }
        return false
    }

    public static func isBareInboxList(_ raw: String) -> Bool {
        if wantsInboxOverview(raw) { return true }
        let lower = raw.lowercased()
        if GmailSearchQuery.hasSenderPattern(raw) { return false }
        if contains(lower, [
            "what's in my inbox",
            "whats in my inbox",
            "what emails do i have",
            "what email do i have",
            "other emails",
            "emails i have today",
            "emails today",
            "show me my emails",
            "show me my inbox",
            "show my emails",
            "what other emails"
        ]), GmailSearchQuery.query(from: raw) == nil {
            return true
        }
        return wantsInbox(raw) && GmailSearchQuery.query(from: raw) == nil && !hasMailTarget(raw)
    }

    private static func hasMailTarget(_ raw: String) -> Bool {
        GmailSearchQuery.hasSenderPattern(raw) || GmailSearchQuery.query(from: raw) != nil
    }

    public static func wantsShowEmail(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        let show = contains(lower, [
            "show", "open", "read", "pull up", "summarize", "summary", "details",
            "what does", "what's it", "whats it", "tell me more",
            "find", "look up", "look for", "search"
        ])
        let noun = contains(lower, ["email", "mail", "note", "message", "thread"])
        return show && noun
    }

    public static func wantsSpecificEmail(_ raw: String) -> Bool {
        wantsEmailBody(raw) || wantsShowEmail(raw)
    }

    public static func wantsEmailFollowUp(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if wantsDeskPreview(raw) || wantsInboxOverview(raw) { return false }
        if wantsFullThread(raw) { return true }
        return contains(lower, [
            "show it to me",
            "show it",
            "show me it",
            "can you show it",
            "can you show me",
            "i'm not seeing",
            "im not seeing",
            "not seeing any email",
            "where's the card",
            "where is the card",
            "i don't see the card",
            "i dont see the card",
            "don't see any email",
            "dont see any email"
        ])
    }

    public static func wantsFullThread(_ raw: String) -> Bool {
        if wantsInboxOverview(raw) { return false }
        let lower = raw.lowercased()
        if contains(lower, [
            "full thread",
            "entire thread",
            "whole thread",
            "full summary",
            "full email",
            "full body",
            "pull the full",
            "read the whole email",
            "entire email",
            "summarize the thread",
            "summarize this thread",
            "summarize the full thread",
            "what's in the thread",
            "whats in the thread",
            "earlier messages",
            "show earlier",
            "whole conversation"
        ]) {
            return true
        }
        let summary = contains(lower, ["summarize", "summary of", "summarize the", "give me a summary"])
        let mail = contains(lower, ["email", "mail", "note", "message", "thread"])
        return summary && mail
    }

    public static func wantsEmailBody(_ raw: String) -> Bool {
        if wantsShowEmail(raw) { return true }
        let lower = raw.lowercased()
        return contains(lower, [
            "details",
            "pull up",
            "the body",
            "read it",
            "read the",
            "read that",
            "what does it say",
            "what's it say",
            "whats it say",
            "tell me more",
            "full email",
            "full body",
            "pull the full",
            "read the whole",
            "whole email",
            "entire email",
            "latest email",
            "that email",
            "this email",
            "the email",
            "open the email",
            "open that email",
            "read the email",
            "read that email",
            "show me the email",
            "show details",
            "what's in the email",
            "whats in the email",
            "summarize",
            "summary",
            "what did they say"
        ])
    }

    public static func matchingEmail(
        for raw: String,
        in emails: [EmailItem],
        owner: MailboxOwner? = nil
    ) -> EmailItem? {
        if let plan = GmailSearchQuery.plan(from: raw) {
            switch GmailSearchQuery.pick(emails, plan: plan, owner: owner) {
            case .one(let email):
                return email
            case .several, .selfOnly, .none:
                if GmailSearchQuery.hasSenderPattern(raw) {
                    return nil
                }
            }
        }
        let lower = raw.lowercased()
        if GmailSearchQuery.hasSenderPattern(raw) {
            return nil
        }
        if wantsEmailBody(raw),
           contains(lower, ["that email", "this email", "the email"]) {
            return emails.first
        }
        if wantsEmailBody(raw), emails.count == 1, !wantsInbox(raw) {
            return emails.first
        }
        return nil
    }

    public static func notSeeingCardsReply(hasInbox: Bool) -> String {
        if hasInbox {
            return "Here they are — the synced emails."
        }
        return "I don’t have a synced thread yet. I’m not inventing cards."
    }

    /// Named `from:X` never inherits sticky or inbox[0] when that sender is not the match.
    public static func namedSenderClearsSticky(
        _ raw: String,
        focused: EmailItem?,
        owner: MailboxOwner? = nil
    ) -> Bool {
        GmailSearchQuery.namedSenderMismatches(focused, ask: raw, owner: owner)
    }

    private static func resolveThreadEmail(
        for raw: String,
        context: DeskContext,
        focusedEmail: EmailItem?
    ) -> EmailItem? {
        if let match = matchingEmail(for: raw, in: context.snapshot.emails, owner: context.mailboxOwner) {
            return match
        }
        if GmailSearchQuery.hasSenderPattern(raw) {
            return nil
        }
        if let focusedEmail { return focusedEmail }
        if context.snapshot.emails.count == 1 {
            return context.snapshot.emails.first
        }
        if wantsFullThread(raw) {
            return context.snapshot.emails.first
        }
        return nil
    }

    private static func emailEvidence(_ email: EmailItem, resetsFocus: Bool = false) -> DeskEvidence {
        DeskEvidence(
            topic: .inbox,
            text: emailBodyReply(email),
            cards: [.email(email)],
            focusedEmail: email,
            shouldFetchBody: true,
            resetsFocusedEmail: resetsFocus
        )
    }

    private static func threadEvidence(_ email: EmailItem, resetsFocus: Bool = false) -> DeskEvidence {
        DeskEvidence(
            topic: .inbox,
            text: emailThreadReply(email),
            cards: [.email(email)],
            focusedEmail: email,
            shouldFetchBody: true,
            expandEarlierMessages: true,
            resetsFocusedEmail: resetsFocus
        )
    }

    private static func searchEvidence(
        ask: String,
        plan: GmailSearchPlan,
        expandEarlier: Bool,
        resetsFocus: Bool = false
    ) -> DeskEvidence {
        DeskEvidence(
            topic: .inbox,
            text: gmailSearchingBeat,
            cards: [],
            shouldFetchBody: false,
            expandEarlierMessages: expandEarlier,
            shouldSearchGmail: true,
            gmailQuery: plan.primary,
            gmailPlan: plan,
            searchAsk: ask,
            resetsFocusedEmail: resetsFocus
        )
    }

    private static func namedSenderMissEvidence(
        ask: String,
        focused: EmailItem?,
        hasInbox: Bool,
        owner: MailboxOwner? = nil
    ) -> DeskEvidence {
        DeskEvidence(
            topic: .inbox,
            text: emailBodyUnknownReply(hasInbox: hasInbox),
            cards: [],
            resetsFocusedEmail: namedSenderClearsSticky(ask, focused: focused, owner: owner) || focused != nil
        )
    }

    private static func namedMailEvidence(
        ask: String,
        context: DeskContext,
        focused: EmailItem?,
        expandEarlier: Bool,
        emails: [EmailItem]? = nil
    ) -> DeskEvidence? {
        guard let plan = GmailSearchQuery.plan(from: ask) else { return nil }
        let owner = context.mailboxOwner
        let pool = emails ?? context.snapshot.emails
        switch GmailSearchQuery.pick(pool, plan: plan, owner: owner) {
        case .one(let email):
            let reset = namedSenderClearsSticky(ask, focused: focused, owner: owner)
            if expandEarlier {
                return threadEvidence(email, resetsFocus: reset)
            }
            return emailEvidence(email, resetsFocus: reset)
        case .several(let list):
            return severalClarifyEvidence(
                list,
                resetsFocus: namedSenderClearsSticky(ask, focused: focused, owner: owner)
            )
        case .selfOnly:
            return selfSenderClarifyEvidence(ask: ask, owner: owner)
        case .none:
            return nil
        }
    }

    private static func rejectRefineEvidence(
        ask: String,
        context: DeskContext,
        focused: EmailItem?,
        clarifyMatches: [EmailItem]
    ) -> DeskEvidence {
        let pool: [EmailItem]
        if !clarifyMatches.isEmpty {
            pool = clarifyMatches.filter { $0.id != focused?.id }
        } else {
            pool = context.snapshot.emails.filter { $0.id != focused?.id }
        }
        if let named = namedMailEvidence(
            ask: ask,
            context: context,
            focused: focused,
            expandEarlier: wantsFullThread(ask),
            emails: pool
        ) {
            var copy = named
            copy.keepsSenderRefine = true
            copy.resetsFocusedEmail = true
            return copy
        }
        if let plan = GmailSearchQuery.plan(from: ask), context.isConnected {
            var evidence = searchEvidence(
                ask: ask,
                plan: plan,
                expandEarlier: wantsFullThread(ask),
                resetsFocus: true
            )
            evidence.keepsSenderRefine = true
            return evidence
        }
        let related = pool.filter { sharesSenderFamily($0, with: focused) }
        let remaining = related.isEmpty ? pool : related
        if remaining.count == 1 {
            var evidence = emailEvidence(remaining[0], resetsFocus: true)
            evidence.keepsSenderRefine = true
            return evidence
        }
        if remaining.count > 1 {
            var evidence = severalClarifyEvidence(Array(EmailRecency.newestFirst(remaining).prefix(3)), resetsFocus: true)
            evidence.keepsSenderRefine = true
            return evidence
        }
        return DeskEvidence(
            topic: .inbox,
            text: emailNeedMoreReply,
            cards: [],
            resetsFocusedEmail: true,
            keepsSenderRefine: true
        )
    }

    private static func severalClarifyEvidence(_ emails: [EmailItem], resetsFocus: Bool) -> DeskEvidence {
        DeskEvidence(
            topic: .inbox,
            text: gmailSearchSeveralReply,
            cards: EmailItem.listCards(EmailRecency.newestFirst(emails)),
            resetsFocusedEmail: resetsFocus
        )
    }

    private static func selfSenderClarifyEvidence(ask: String, owner: MailboxOwner?) -> DeskEvidence {
        DeskEvidence(
            topic: .inbox,
            text: selfSenderClarifyReply(ask: ask, owner: owner),
            cards: [],
            resetsFocusedEmail: true
        )
    }

    public static func selfSenderClarifyReply(ask: String, owner: MailboxOwner?) -> String {
        _ = owner
        let spoken = GmailSearchQuery.plan(from: ask)?.senders.first.map { $0.capitalized } ?? "that name"
        return "The only \(spoken) I see is you. Did you mean your own email, or someone else?"
    }

    /// After rejecting Alex & Laren, keep Laren Jansen — not Greenacre.
    private static func sharesSenderFamily(_ email: EmailItem, with focused: EmailItem?) -> Bool {
        guard let focused else { return true }
        let focusedWords = senderGivenNames(focused.fromName)
        let emailWords = senderGivenNames(email.fromName)
        for word in emailWords where word.count >= GmailSearchQuery.senderFuzzyMinLength {
            if focusedWords.contains(where: { GmailSearchQuery.editDistance($0, word) <= GmailSearchQuery.senderFuzzyMaxEdits }) {
                return true
            }
        }
        return false
    }

    private static func senderGivenNames(_ raw: String) -> [String] {
        raw.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count >= 3 && !GmailSearchQuery.stop.contains($0) }
    }

    /// Spoken while the client actually calls Gmail. Never a capability claim.
    /// Stored / spoken-skip text stays static; the UI animates `gmailSearchingStem` + dots.
    public static let gmailSearchingStem = "Searching Gmail"
    public static let gmailSearchingBeat = gmailSearchingStem + "…"
    public static let gmailSearchPendingReply = gmailSearchingBeat
    public static let thinkingStatusStem = "Thinking"
    public static let thinkingStatusBeat = thinkingStatusStem + "…"

    public static func isGmailSearchingBeat(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == gmailSearchingBeat
    }

    public static func isThinkingBeat(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == thinkingStatusBeat
    }

    public static func isStatusBeat(_ text: String) -> Bool {
        isGmailSearchingBeat(text) || isThinkingBeat(text)
    }

    public static let gmailSearchEmptyReply =
        "I searched Gmail and didn’t find that. I’m not inventing it."

    public static let gmailSearchSeveralReply =
        "I found a few matches. Which one?"

    public static let gmailSearchFailedReply =
        "I couldn’t reach Gmail just now. I’m not inventing that message."

    public static let emailNeedMoreReply =
        "Who’s it from, or what’s the subject?"

    public static let calendarMissReply =
        "Nothing matching that is in the upcoming calendar sync. I’m not inventing an event."

    public static let taskMissReply =
        "No matching open task in the last sync. I’m not inventing one."

    private static func inboxOverviewEvidence(context: DeskContext) -> DeskEvidence {
        var evidence = inboxEvidence(context: context, followUp: false, resetsFocus: true)
        if context.isConnected, !context.snapshot.emails.isEmpty {
            evidence.shouldGlanceInbox = true
        }
        return evidence
    }

    private static func calendarOverviewEvidence(context: DeskContext) -> DeskEvidence {
        DeskEvidence(
            topic: .calendar,
            text: calendarReply(context: context),
            cards: cards(for: .calendar, context: context)
        )
    }

    private static func inboxEvidence(
        context: DeskContext,
        followUp: Bool,
        resetsFocus: Bool = false
    ) -> DeskEvidence {
        let cards = cards(for: .inbox, context: context)
        let text: String
        if followUp {
            text = notSeeingCardsReply(hasInbox: !context.snapshot.emails.isEmpty)
        } else {
            text = inboxReply(context: context)
        }
        return DeskEvidence(
            topic: .inbox,
            text: text,
            cards: EmailItem.listCards(
                cards.compactMap { card in
                    if case .email(let item) = card { return item }
                    return nil
                }
            ) + cards.filter { $0.kind != .email },
            focusedEmail: resetsFocus ? nil : context.snapshot.emails.first,
            shouldFetchBody: false,
            resetsFocusedEmail: resetsFocus
        )
    }

    public static func emailBodyReply(_ email: EmailItem) -> String {
        if email.hasFullBody {
            return EmailSummary.heuristic(EmailSummaryRequest.from(email, includeEarlier: false))
        }
        return emailBodySyncFailedReply(email)
    }

    /// Multi-sentence summary of the latest body, plus a brief earlier beat if present.
    public static func emailThreadReply(_ email: EmailItem) -> String {
        if email.hasFullBody || email.hasEarlierMessages {
            return EmailSummary.heuristic(EmailSummaryRequest.from(email, includeEarlier: true))
        }
        return "I’ll load \(email.fromName)’s earlier messages here in VoiceDesk."
    }

    public static func emailBodySyncFailedReply(_ email: EmailItem) -> String {
        "I still have \(email.fromName)’s email. I couldn’t load the full message — I’ll retry here in VoiceDesk."
    }

    public static func wantsCalendarDetails(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return contains(lower, ["reservation", "that event", "the event", "calendar event"])
            || (contains(lower, ["details", "pull up"]) && contains(lower, ["reservation", "event", "meeting", "calendar"]))
    }

    public static func matchingTask(for raw: String, in tasks: [TaskItem]) -> TaskItem? {
        let lower = raw.lowercased()
        let stop: Set<String> = ["task", "tasks", "open", "have", "what", "my", "the"]
        for task in tasks {
            let words = task.title.lowercased()
                .split { !$0.isLetter }
                .map(String.init)
                .filter { $0.count >= 4 && !stop.contains($0) }
            if words.contains(where: { lower.contains($0) }) {
                return task
            }
        }
        return nil
    }

    public static func matchingCalendar(for raw: String, in events: [CalendarItem]) -> CalendarItem? {
        let lower = raw.lowercased()
        let stop: Set<String> = [
            "latest", "recent", "calendar", "schedule", "today", "week",
            "upcoming", "what", "whats", "this", "that", "your"
        ]
        for event in events {
            let titleWords = event.title.lowercased()
                .split { !$0.isLetter }
                .map(String.init)
                .filter { $0.count >= 4 && !stop.contains($0) }
            if titleWords.contains(where: { lower.contains($0) }) {
                return event
            }
            for person in event.relatedPeople {
                let nameWords = person.lowercased()
                    .split { !$0.isLetter }
                    .map(String.init)
                    .filter { $0.count >= 3 && !stop.contains($0) }
                if nameWords.contains(where: { lower.contains($0) }) {
                    return event
                }
            }
        }
        return nil
    }

    public static func calendarDetailsReply(_ event: CalendarItem) -> String {
        var line = "Here’s \(event.title) — \(event.whenLabel)."
        if let location = event.location, !location.isEmpty {
            line += " \(location)."
        }
        if !event.relatedPeople.isEmpty {
            line += " With \(event.relatedPeople.joined(separator: ", "))."
        }
        return line + " Details are on the calendar card."
    }

    public static func emailBodyUnknownReply(hasInbox: Bool) -> String {
        if hasInbox {
            return "Which message? Say the sender or subject. I’ll open it on a card here — I won’t send you out of VoiceDesk."
        }
        return "I don’t have a synced thread yet. I’ll show it on a card here once it syncs — I won’t send you out of VoiceDesk."
    }

    /// Connecting / linking Google or Gmail — never a Settings or Integrations path.
    public static func wantsConnectGoogle(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if contains(lower, [
            "connect google",
            "connecting google",
            "connect my google",
            "connect your google",
            "sign in with google",
            "sign into google",
            "sign in to google",
            "signin with google",
            "disconnect google",
            "link gmail",
            "linking gmail",
            "link my gmail",
            "connect gmail",
            "connect my gmail",
            "link google",
            "link my google",
            "linking google"
        ]) {
            return true
        }
        let askingHow = contains(lower, [
            "how do i",
            "how do we",
            "how to",
            "how can i",
            "where do i",
            "where can i",
            "where is"
        ])
        let linking = contains(lower, ["connect", "link", "sign in", "signin", "log in", "login"])
        let google = contains(lower, ["google", "gmail"])
        if askingHow && linking && google {
            return true
        }
        return google && contains(lower, ["settings", "integrations", "integration"])
    }

    public static func wantsDeskPreview(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower == deskPreview.lowercased() { return true }
        return contains(lower, [
            "sample email and listing",
            "sample email",
            "sample listing",
            "what email looks like",
            "what emails look like",
            "what listings look like"
        ])
    }

    public static func wantsTour(_ raw: String) -> Bool {
        if wantsDeskPreview(raw) { return false }
        let lower = raw.lowercased()
        return contains(lower, [
            "show me around",
            "sure, show me",
            "give me a tour",
            "the tour",
            "start the tour"
        ])
    }

    public static func isJustTalk(_ raw: String) -> Bool {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == justTalk.lowercased()
            || lower == "just talk"
            || contains(lower, ["just talk to me"])
    }

    public static func chipAccessibilityID(_ item: String) -> String {
        if wantsDeskPreview(item) || item == deskPreview { return "suggestion.tour" }
        if item == justTalk { return "suggestion.justTalk" }
        if item == draftStarter { return "suggestion.draft" }
        if item == connectGoogleChip { return "suggestion.connectGoogle" }
        return "suggestion.\(item)"
    }

    private static func generalReply(for text: String, lower: String, context: DeskContext) -> String {
        if contains(lower, ["weather", "rain", "storm"]) {
            return "Tampa Bay this time of year I’d plan on warm, with a late storm always in the mix — glance before you leave for a showing. What else?"
        }
        if contains(lower, ["dinner", "lunch", "eat", "food", "hungry"]) {
            return "After a day in the car I’d keep it simple — something you don’t have to think about. I’m here either way."
        }
        if contains(lower, ["how are you", "how's it going", "how’re you"]) {
            return "I’m good — I’m right here. What’s going on?"
        }
        if contains(lower, ["joke"]) {
            return "Why did the listing go to therapy? Too many attachments. I’m kidding — what’s actually on your mind?"
        }
        if contains(lower, ["calendar", "schedule", "task", "todo"]) {
            if context.isConnected {
                return "Ask me what’s on your calendar or what tasks you have — I’ll use the last Google sync, not a sample day."
            }
            return "I don’t have your live calendar yet. Connect Google and I will — until then I’ll just talk it through with you. What are you trying to fit in?"
        }
        if text.isEmpty {
            return "I’m here. Say anything."
        }
        return "I’m with you. I’ll talk this through like a person — no menu, no mode to pick. If it ties to your desk I’ll pin the evidence; otherwise we can just keep going."
    }

    private static func contains(_ lower: String, _ keys: [String]) -> Bool {
        keys.contains { lower.contains($0) }
    }
}
