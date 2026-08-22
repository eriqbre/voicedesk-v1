import Foundation
import Observation
import VoiceDeskLogic

@MainActor
@Observable
final class AppModel {
    var turns: [ConversationTurn] = []
    var phase: SessionPhase = .welcome
    var activity: [ActivityEntry] = []
    var composerText = ""
    var showActivity = false
    var isTourRunning = false

    let voice: MockVoiceService
    let google: StubGoogleAuth
    let wakeWord: WakeWordPlaceholder
    let sendClient: RecordingSendClient

    init(
        voice: MockVoiceService? = nil,
        google: StubGoogleAuth? = nil,
        wakeWord: WakeWordPlaceholder? = nil,
        sendClient: RecordingSendClient? = nil
    ) {
        self.voice = voice ?? VoiceRuntime.makeService()
        self.google = google ?? StubGoogleAuth()
        self.wakeWord = wakeWord ?? WakeWordPlaceholder()
        self.sendClient = sendClient ?? RecordingSendClient()
        startWelcome()
    }

    static func makeForLaunch() -> AppModel {
        let uiTesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        return AppModel(
            voice: uiTesting
                ? MockVoiceService(label: "UITest", instant: true)
                : VoiceRuntime.makeService()
        )
    }

    func applyUserTurn(_ text: String) async {
        await handleUserText(text)
    }

    var lastTurnID: UUID? { turns.last?.id }

    func startWelcome() {
        turns = [
            ConversationTurn(
                role: .assistant,
                text: "Hi — I’m VoiceDesk. Talk whenever you’re ready. Want a 30-second tour of how this works?",
                suggestions: ["Start the tour"]
            )
        ]
        phase = .welcome
    }

    func tapTalk() {
        switch voice.state {
        case .listening, .speaking, .thinking:
            voice.cancel()
            cancelPendingDraftsFromVoice()
        case .idle:
            Task { await listenAndHandle() }
        }
    }

    func sendComposer() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composerText = ""
        Task { await handleUserText(text) }
    }

    func useSuggestion(_ text: String) {
        Task { await handleUserText(text) }
    }

    func confirmDraft(_ id: UUID) {
        updateDraft(id) { $0.status = DraftConfirmMachine.apply($0.status, .confirm) }
        guard let draft = draft(id), DraftConfirmMachine.mayCallSendClient(after: draft.status) else { return }
        let attempt = sendClient.send(draft)
        let outcome: String
        switch attempt {
        case .queuedNotDelivered:
            outcome = "Not sent — Google write is stubbed. Never reported as delivered."
        case .blockedUnconfirmed:
            outcome = "Blocked. Confirm is required before send."
        case .delivered:
            outcome = "Delivered."
        }
        activity.append(
            ActivityEntry(
                title: "Email send confirmed",
                detail: "Jordan Hale · Saturday showing",
                outcome: outcome
            )
        )
        appendAssistant(
            "Confirmed. It’s on Activity as a draft, not sent. Delivery waits for Google write — I won’t say “sent” until the provider succeeds."
        )
        Task { await voice.speak("Confirmed. Nothing was sent yet.") }
    }

    func cancelDraft(_ id: UUID) {
        updateDraft(id) { $0.status = DraftConfirmMachine.apply($0.status, .cancel) }
        activity.append(
            ActivityEntry(
                title: "Email send cancelled",
                detail: "Jordan Hale · Saturday showing",
                outcome: "Aborted. Nothing left the device."
            )
        )
        appendAssistant("Cancelled. Nothing was sent.")
    }

    func beginEditDraft(_ id: UUID) {
        updateDraft(id) { $0.status = DraftConfirmMachine.apply($0.status, .beginEdit) }
    }

    func saveDraftBody(_ id: UUID, body: String) {
        updateDraft(id) {
            $0.body = body
            $0.status = DraftConfirmMachine.apply($0.status, .saveBody)
        }
    }

    func connectGoogle() {
        Task {
            await google.connect()
            markGoogleConnected()
            activity.append(
                ActivityEntry(
                    title: "Google connect",
                    detail: "Gmail, Calendar, Tasks",
                    outcome: "Stubbed success. Real OAuth is the next slice."
                )
            )
            appendAssistant(
                "Google is connected (stub). Next slice is real OAuth and sync. Try “What’s in my inbox?” or tap the mic."
            )
            await voice.speak("Google is connected, stub only.")
        }
    }

    func handlePersonCall(_ person: PersonItem) {
        appendAssistant("Calling \(person.name) is a system handoff — not wired in this slice.")
    }

    func handlePersonMessage(_ person: PersonItem) {
        appendAssistant("Messages for \(person.name) will use the system composer after contacts land.")
    }

    // MARK: - Voice / tour

    private func listenAndHandle() async {
        let overheard = await voice.startListening()
        if voice.state == .idle, overheard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        let spoken = overheard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? mockUtterance()
            : overheard
        await handleUserText(spoken)
    }

    private func handleUserText(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if matchesCancel(text) {
            voice.cancel()
            cancelPendingDraftsFromVoice()
            appendUser(text)
            appendAssistant("Stopped. Nothing was sent.")
            return
        }

        appendUser(text)

        if phase == .welcome, shouldStartTour(text) {
            await runTour()
            return
        }
        if shouldRestartTour(text) {
            await runTour()
            return
        }
        if phase == .welcome {
            phase = .ready
        }

        await replyReady(to: text)
    }

    private func runTour() async {
        guard !isTourRunning else { return }
        isTourRunning = true
        phase = .touring

        await pause(320)
        appendAssistant(
            "You talk, I answer, and I put the evidence on cards. Here’s a sample email about a listing — and the people on it.",
            cards: TourScript.graphCards()
        )
        await voice.speak("Here’s the email, the listing, and the people on it.")

        await pause(400)
        appendAssistant(
            "If I need to send or change anything, you see the exact action first. Nothing goes out until you confirm.",
            cards: [TourScript.draftCard()]
        )
        await voice.speak("Writes always wait for your confirm.")

        await pause(400)
        appendAssistant(
            "Florida law and broker rules show a confidence score and the source. I won’t bluff.",
            cards: [TourScript.statuteCard()]
        )
        await voice.speak("Legal answers show confidence and the citation.")

        await pause(400)
        appendAssistant(
            "Connect Google for your real inbox, calendar, and tasks. Tap the mic anytime. Wake word is next — for now, tap to talk.",
            cards: [TourScript.connectGoogleCard(isConnected: google.isConnected)],
            suggestions: google.isConnected ? ["What’s in my inbox?"] : []
        )
        await voice.speak("Connect Google when you’re ready.")

        phase = .ready
        isTourRunning = false
    }

    private func replyReady(to text: String) async {
        let lower = text.lowercased()
        let reply: (String, [ContentCard], [String])

        if matches(lower, ["inbox", "email", "mail", "jordan"]) {
            reply = (
                "Sample inbox thread — not live Gmail. Jordan wrote this morning about Beach Drive.",
                [.email(SampleData.email()), .person(SampleData.buyer())],
                ["Draft a reply", "Show the listing"]
            )
        } else if matches(lower, ["listing", "showing", "beach", "house", "property"]) {
            reply = (
                "1842 Beach Drive NE, inferred as yours from the thread. Claim/confirm lands with listing graph work.",
                [.listing(SampleData.listing()), .person(SampleData.buyer()), .person(SampleData.partner())],
                ["Draft a reply"]
            )
        } else if matches(lower, ["send", "reply", "draft", "write", "email them"]) {
            reply = (
                "Here’s the exact send. Confirm & Send logs it — it will not leave the device in this slice.",
                [.draftConfirm(SampleData.draftReply())],
                []
            )
        } else if matches(lower, ["law", "statute", "florida", "disclosure", "475", "legal", "compliance"]) {
            reply = (
                "Sample statute card. Confidence 86% — firm tone, still not legal advice.",
                [.statute(SampleData.statute())],
                []
            )
        } else if matches(lower, ["google", "connect", "gmail", "calendar", "tasks"]) {
            reply = (
                "Google is required for a real day. OAuth is stubbed here.",
                [.connectGoogle(SampleData.connectGoogle(isConnected: google.isConnected))],
                []
            )
        } else if matches(lower, ["calendar", "task", "todo", "schedule"]) {
            reply = (
                "Calendar and task cards are in the PRD; this slice stubs email, listing, people, draft-confirm, and statute. Next recommended slice is Google OAuth + sync.",
                [],
                ["What’s in my inbox?", "Show a listing"]
            )
        } else {
            reply = (
                "I can demo inbox, listing, people, a confirm-to-send draft, or a statute card. Live Grok answers wait for the voice wire-up.",
                [],
                ["What’s in my inbox?", "Show the listing", "Draft a reply", "Florida disclosure"]
            )
        }

        appendAssistant(reply.0, cards: reply.1, suggestions: reply.2)
        await voice.speak(reply.0)
    }

    // MARK: - Mutations

    private func appendUser(_ text: String) {
        turns.append(ConversationTurn(role: .user, text: text))
    }

    private func appendAssistant(_ text: String, cards: [ContentCard] = [], suggestions: [String] = []) {
        turns.append(ConversationTurn(role: .assistant, text: text, cards: cards, suggestions: suggestions))
    }

    private func draft(_ id: UUID) -> DraftConfirmItem? {
        for turn in turns {
            for card in turn.cards {
                if case .draftConfirm(let item) = card, item.id == id {
                    return item
                }
            }
        }
        return nil
    }

    private func updateDraft(_ id: UUID, _ body: (inout DraftConfirmItem) -> Void) {
        for index in turns.indices {
            for cardIndex in turns[index].cards.indices {
                guard case .draftConfirm(var draft) = turns[index].cards[cardIndex], draft.id == id else {
                    continue
                }
                body(&draft)
                turns[index].cards[cardIndex] = .draftConfirm(draft)
                return
            }
        }
    }

    private func markGoogleConnected() {
        for index in turns.indices {
            for cardIndex in turns[index].cards.indices {
                if case .connectGoogle(var item) = turns[index].cards[cardIndex] {
                    item.isConnected = true
                    turns[index].cards[cardIndex] = .connectGoogle(item)
                }
            }
        }
    }

    private func cancelPendingDraftsFromVoice() {
        var cancelled = false
        for index in turns.indices {
            for cardIndex in turns[index].cards.indices {
                if case .draftConfirm(var draft) = turns[index].cards[cardIndex],
                   draft.status == .pending || draft.status == .editing {
                    draft.status = .cancelled
                    turns[index].cards[cardIndex] = .draftConfirm(draft)
                    cancelled = true
                }
            }
        }
        if cancelled {
            activity.append(
                ActivityEntry(
                    title: "Voice stop",
                    detail: "In-progress confirm aborted",
                    outcome: "Cancelled. Nothing was sent."
                )
            )
        }
    }

    private func mockUtterance() -> String {
        switch phase {
        case .welcome:
            return "Yes, show me."
        case .touring:
            return "Keep going."
        case .ready:
            return "What’s in my inbox?"
        }
    }

    private func shouldStartTour(_ text: String) -> Bool {
        matches(text.lowercased(), ["tour", "show me", "yes", "start"])
    }

    private func shouldRestartTour(_ text: String) -> Bool {
        matches(text.lowercased(), ["start the tour", "give me a tour", "show me the tour"])
    }

    private func matchesCancel(_ text: String) -> Bool {
        matches(text.lowercased(), ["stop", "cancel", "nevermind", "never mind", "abort"])
    }

    private func matches(_ lower: String, _ keys: [String]) -> Bool {
        keys.contains { lower.contains($0) }
    }

    private func pause(_ milliseconds: UInt64) async {
        if voice.instant { return }
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}
