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

        if contains(lower, ["inbox", "my email", "my mail", "what's in my inbox", "whats in my inbox"])
            || (contains(lower, ["email", "mail"]) && contains(lower, ["my", "inbox"])) {
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
                return context.snapshot.emails.prefix(3).map { .email($0) }
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

    public static func wantsEmailBody(_ raw: String) -> Bool {
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
        let lower = raw.lowercased()
        let stop: Set<String> = [
            "the", "and", "for", "from", "you", "your", "this", "that",
            "email", "mail", "with", "about", "inbox", "details", "body", "read"
        ]
        for email in emails {
            let nameWords = email.fromName.lowercased()
                .split { !$0.isLetter }
                .map(String.init)
                .filter { $0.count >= 3 }
            if nameWords.contains(where: { lower.contains($0) }) {
                return email
            }
            let local = email.fromEmail.split(separator: "@").first.map(String.init)?.lowercased() ?? ""
            if local.count >= 3, lower.contains(local) {
                return email
            }
        }
        for email in emails {
            let subjectWords = email.subject.lowercased()
                .split { !$0.isLetter }
                .map(String.init)
                .filter { $0.count >= 4 && !stop.contains($0) }
            if subjectWords.contains(where: { lower.contains($0) }) {
                return email
            }
        }
        if wantsEmailBody(raw),
           contains(lower, ["latest", "first", "that email", "this email", "the email"]) {
            return emails.first
        }
        if wantsEmailBody(raw), emails.count == 1 {
            return emails.first
        }
        return nil
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

    public static func emailBodySyncFailedReply(_ email: EmailItem) -> String {
        "I still have \(email.fromName)’s email on the card. Tap Read email to retry — I’ll show the full message here in VoiceDesk."
    }

    public static func wantsCalendarDetails(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return contains(lower, ["reservation", "that event", "the event", "calendar event"])
            || (contains(lower, ["details", "pull up"]) && contains(lower, ["reservation", "event", "meeting", "calendar"]))
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
        return line + " It’s on the calendar card."
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
