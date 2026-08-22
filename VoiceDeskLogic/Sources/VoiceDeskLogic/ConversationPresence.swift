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
        case general
    }

    public struct Plan: Equatable, Sendable {
        public let topic: Topic
        public let text: String

        public var attachesCards: Bool { topic != .general }

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
                text: "1842 Beach Drive — I have it as inferred yours from that thread. People on it are on the card."
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
                text: "Florida wants the brokerage relationship on the table before you show as a single agent. Confidence is on the card — I’m not your lawyer."
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
        case .general:
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
        let first = context.snapshot.emails[0]
        return "Latest from \(first.fromName): \(first.subject). I’m only showing mail I actually synced."
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
            searchAsk: String? = nil
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
        }

        public var claimsCardWithoutAttaching: Bool {
            ConversationPresence.replyMentionsCard(text) && cards.isEmpty
        }

        public var awaitsSearchClarify: Bool {
            text == ConversationPresence.emailNeedMoreReply && cards.isEmpty
        }
    }

    public static func replyMentionsCard(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return contains(lower, ["on the card", "email card", "calendar card", "cards below", "waiting on the"])
    }

    /// Connected Google + desk ask: the client owns the turn. Grok must not speak.
    public static func ownsConnectedDeskTurn(_ raw: String) -> Bool {
        looksLikeMailAsk(raw) || wantsCalendarAsk(raw) || wantsTaskAsk(raw)
    }

    public static func looksLikeMailAsk(_ raw: String) -> Bool {
        if wantsDeskPreview(raw) || wantsConnectGoogle(raw) || isJustTalk(raw) {
            return false
        }
        if wantsCalendarDetails(raw), !contains(raw.lowercased(), ["email", "mail", "note", "message", "thread"]) {
            return false
        }
        if wantsTaskAsk(raw), !contains(raw.lowercased(), ["email", "mail", "note", "message", "thread"]) {
            return false
        }
        if wantsFullThread(raw) || wantsEmailFollowUp(raw) || wantsSpecificEmail(raw)
            || wantsShowEmail(raw) || wantsEmailBody(raw) || wantsInbox(raw) {
            return true
        }
        if GmailSearchQuery.hasSenderPattern(raw) { return true }
        if GmailSearchQuery.query(from: raw) != nil,
           contains(raw.lowercased(), ["find", "look", "search", "get", "pull", "show", "email", "mail", "note", "message", "thread"]) {
            return true
        }
        return false
    }

    public static func wantsCalendarAsk(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if wantsCalendarDetails(raw) { return true }
        return contains(lower, ["my calendar", "on my calendar", "what's on my calendar", "whats on my calendar", "schedule today", "what meetings"])
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
        pendingSearchClarify: Bool = false
    ) -> DeskEvidence? {
        if wantsDeskPreview(raw) || wantsConnectGoogle(raw) || isJustTalk(raw) {
            return nil
        }

        if wantsCalendarAsk(raw) {
            if let event = matchingCalendar(for: raw, in: context.snapshot.events) {
                return DeskEvidence(
                    topic: .calendar,
                    text: calendarDetailsReply(event),
                    cards: [.calendar(event)]
                )
            }
            if context.isConnected {
                if wantsCalendarDetails(raw) || matchingCalendar(for: raw, in: context.snapshot.events) == nil,
                   GmailSearchQuery.hasSenderPattern(raw) || wantsCalendarDetails(raw) {
                    return DeskEvidence(
                        topic: .calendar,
                        text: calendarMissReply,
                        cards: []
                    )
                }
                return DeskEvidence(
                    topic: .calendar,
                    text: calendarReply(context: context),
                    cards: cards(for: .calendar, context: context)
                )
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

        if pendingSearchClarify, context.isConnected,
           let plan = GmailSearchQuery.plan(from: raw, treatAsBrand: true) {
            return searchEvidence(ask: raw, plan: plan, expandEarlier: wantsFullThread(raw))
        }

        if wantsFullThread(raw) {
            if let email = resolveThreadEmail(for: raw, context: context, focusedEmail: focusedEmail) {
                return threadEvidence(email)
            }
            if context.isConnected, let plan = GmailSearchQuery.plan(from: raw) {
                return searchEvidence(ask: raw, plan: plan, expandEarlier: true)
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
            if let email = matchingEmail(for: raw, in: context.snapshot.emails) {
                return emailEvidence(email)
            }
            if wantsEmailFollowUp(raw) {
                if let focusedEmail {
                    return emailEvidence(focusedEmail)
                }
                if !context.snapshot.emails.isEmpty {
                    return inboxEvidence(context: context, followUp: true)
                }
                if context.isConnected, GmailSearchQuery.hasSenderPattern(raw),
                   let plan = GmailSearchQuery.plan(from: raw) {
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

    public static func isBareInboxList(_ raw: String) -> Bool {
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
        if wantsDeskPreview(raw) { return false }
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
        let lower = raw.lowercased()
        if contains(lower, [
            "full thread",
            "entire thread",
            "whole thread",
            "full summary",
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
            "whole email",
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

    public static func matchingEmail(for raw: String, in emails: [EmailItem]) -> EmailItem? {
        if let plan = GmailSearchQuery.plan(from: raw) {
            switch GmailSearchQuery.pick(emails, plan: plan) {
            case .one(let email):
                return email
            case .several(let list):
                return list.first
            case .none:
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
            return "Here they are — the synced emails are on the cards below."
        }
        return "I don’t have a synced thread yet. I’m not inventing cards."
    }

    private static func resolveThreadEmail(
        for raw: String,
        context: DeskContext,
        focusedEmail: EmailItem?
    ) -> EmailItem? {
        if let match = matchingEmail(for: raw, in: context.snapshot.emails) {
            return match
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

    private static func emailEvidence(_ email: EmailItem) -> DeskEvidence {
        DeskEvidence(
            topic: .inbox,
            text: emailBodyReply(email),
            cards: [.email(email)],
            focusedEmail: email,
            shouldFetchBody: true
        )
    }

    private static func threadEvidence(_ email: EmailItem) -> DeskEvidence {
        DeskEvidence(
            topic: .inbox,
            text: emailThreadReply(email),
            cards: [.email(email)],
            focusedEmail: email,
            shouldFetchBody: true,
            expandEarlierMessages: true
        )
    }

    private static func searchEvidence(ask: String, plan: GmailSearchPlan, expandEarlier: Bool) -> DeskEvidence {
        DeskEvidence(
            topic: .inbox,
            text: gmailSearchingBeat,
            cards: [],
            shouldFetchBody: false,
            expandEarlierMessages: expandEarlier,
            shouldSearchGmail: true,
            gmailQuery: plan.primary,
            gmailPlan: plan,
            searchAsk: ask
        )
    }

    /// Spoken while the client actually calls Gmail. Never a capability claim.
    public static let gmailSearchingBeat = "Searching Gmail…"
    public static let gmailSearchPendingReply = gmailSearchingBeat

    public static let gmailSearchEmptyReply =
        "I searched Gmail and didn’t find that. I’m not inventing it."

    public static let gmailSearchSeveralReply =
        "I found a few matches. They’re on the cards — which one?"

    public static let gmailSearchFailedReply =
        "I couldn’t reach Gmail just now. I’m not inventing that message."

    public static let emailNeedMoreReply =
        "Who’s it from, or what’s the subject?"

    public static let calendarMissReply =
        "Nothing matching that is in the upcoming calendar sync. I’m not inventing an event."

    public static let taskMissReply =
        "No matching open task in the last sync. I’m not inventing one."

    private static func inboxEvidence(context: DeskContext, followUp: Bool) -> DeskEvidence {
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
            cards: cards,
            focusedEmail: context.snapshot.emails.first,
            shouldFetchBody: false
        )
    }

    public static func emailBodyReply(_ email: EmailItem) -> String {
        if email.hasFullBody {
            let beat = EmailBodyFormatting.spokenSummary(from: email.body, fallback: email.preview)
            if beat.isEmpty {
                return "Latest from \(email.fromName) is on the card."
            }
            return "Latest from \(email.fromName) is on the card. \(beat)"
        }
        if !email.preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return emailBodySyncFailedReply(email)
        }
        return emailBodySyncFailedReply(email)
    }

    /// Multi-sentence summary of the latest body, plus a brief earlier beat if present.
    public static func emailThreadReply(_ email: EmailItem) -> String {
        let latest = EmailBodyFormatting.spokenSummary(
            from: email.body,
            fallback: email.preview,
            style: .full
        )
        if email.hasEarlierMessages {
            let earlierBeats = email.earlierMessages.compactMap { message -> String? in
                let beat = EmailBodyFormatting.spokenSummary(from: message.plainBody, fallback: "", style: .brief)
                return beat.isEmpty ? nil : beat
            }
            var parts: [String] = []
            if latest.isEmpty {
                parts.append("Latest from \(email.fromName) is on the card.")
            } else {
                parts.append("\(email.fromName) wrote: \(latest)")
            }
            if let first = earlierBeats.first {
                let who = email.earlierMessages.first?.fromName
                if let who, !who.isEmpty {
                    parts.append("Earlier from \(who): \(first)")
                } else {
                    parts.append("Earlier: \(first)")
                }
            }
            return parts.joined(separator: " ")
        }
        if email.hasFullBody {
            if latest.isEmpty {
                return "This thread is only the latest from \(email.fromName) — no earlier messages in the sync."
            }
            return "\(email.fromName) wrote: \(latest)"
        }
        return "The thread is on the card. I’ll load earlier messages here in VoiceDesk."
    }

    public static func emailBodySyncFailedReply(_ email: EmailItem) -> String {
        "I still have \(email.fromName)’s email on the card. Tap Read email to retry — I’ll show the full message here in VoiceDesk."
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
        for event in events {
            let titleWords = event.title.lowercased()
                .split { !$0.isLetter }
                .map(String.init)
                .filter { $0.count >= 4 }
            if titleWords.contains(where: { lower.contains($0) }) {
                return event
            }
            for person in event.relatedPeople {
                let nameWords = person.lowercased()
                    .split { !$0.isLetter }
                    .map(String.init)
                    .filter { $0.count >= 3 }
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
