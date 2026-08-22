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
    var showVoiceSetup = false
    var hasCompletedPlaybook = false

    let voice: VoiceBox
    let google: StubGoogleAuth
    let wakeWord: WakeWordPlaceholder
    let sendClient: RecordingSendClient
    let playbook: PlaybookStoring

    private var liveAssistantID: UUID?
    private var pendingDeskTopic: ConversationPresence.Topic?
    private var userDedupe = TranscriptDedupe()

    var showsTalkCoach: Bool {
        !hasCompletedPlaybook && voice.state == .idle && !voice.needsCredentials
    }

    init(
        voice: (any VoiceServicing)? = nil,
        google: StubGoogleAuth? = nil,
        wakeWord: WakeWordPlaceholder? = nil,
        sendClient: RecordingSendClient? = nil,
        playbook: PlaybookStoring? = nil
    ) {
        self.voice = VoiceBox(service: voice ?? VoiceRuntime.makeService())
        self.google = google ?? StubGoogleAuth()
        self.wakeWord = wakeWord ?? WakeWordPlaceholder()
        self.sendClient = sendClient ?? RecordingSendClient()
        self.playbook = playbook ?? InMemoryPlaybookStore(completed: false)
        self.hasCompletedPlaybook = self.playbook.hasCompleted
        self.voice.transcriptHandler = { [weak self] event in
            self?.handleLiveTranscript(event)
        }
        startWelcome()
    }

    private static func makeLaunchPlaybookStore() -> PlaybookStoring {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return InMemoryPlaybookStore(completed: false)
        }
        return UserDefaultsPlaybookStore()
    }

    static func makeForLaunch() -> AppModel {
        AppModel(voice: VoiceRuntime.makeService(), playbook: makeLaunchPlaybookStore())
    }

    func applyUserTurn(_ text: String) async {
        await handleUserText(text)
    }

    var lastTurnID: UUID? { turns.last?.id }

    func startWelcome() {
        let firstRun = !hasCompletedPlaybook
        turns = [
            ConversationTurn(
                role: .assistant,
                text: firstRun ? ConversationPresence.firstRunWelcome : ConversationPresence.returningWelcome,
                suggestions: firstRun ? ConversationPresence.starterChips : []
            )
        ]
        phase = .welcome
    }

    func tapTalk() {
        completePlaybook()
        if voice.needsCredentials {
            showVoiceSetup = true
            return
        }
        switch voice.state {
        case .listening, .speaking, .thinking:
            voice.cancel()
            liveAssistantID = nil
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
        if voice.usesLiveLoop {
            _ = await voice.startListening()
            if let error = voice.lastError, !error.isEmpty {
                appendAssistant("I couldn’t reach Grok. \(error)")
            }
            return
        }

        let overheard = await voice.startListening()
        if voice.state == .idle, overheard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        let spoken = overheard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? mockUtterance()
            : overheard
        await handleUserText(spoken)
    }

    private func handleLiveTranscript(_ event: VoiceTranscript) {
        switch event.role {
        case .user:
            guard event.isFinal else { return }
            handleLiveUser(event.text, itemID: event.itemID)
        case .assistant:
            upsertLiveAssistant(event.text, isFinal: event.isFinal)
        }
    }

    private func handleLiveUser(_ raw: String, itemID: String?) {
        guard let text = userDedupe.accept(text: raw, itemID: itemID) else { return }
        completePlaybook()

        if matchesCancel(text) {
            voice.cancel()
            cancelPendingDraftsFromVoice()
            appendUser(text)
            appendAssistant("Stopped. Nothing was sent.")
            return
        }

        appendUser(text)
        pendingDeskTopic = ConversationPresence.plan(for: text).topic
        if phase == .welcome {
            phase = .ready
        }
        if ConversationPresence.wantsTour(text) {
            Task { await runTour() }
        }
    }

    private func upsertLiveAssistant(_ text: String, isFinal: Bool) {
        if text.isEmpty, isFinal {
            if let id = liveAssistantID, let index = turns.firstIndex(where: { $0.id == id }) {
                attachPendingCards(to: index)
                liveAssistantID = nil
            }
            return
        }

        if let id = liveAssistantID, let index = turns.firstIndex(where: { $0.id == id }) {
            turns[index].text += text
            if isFinal {
                attachPendingCards(to: index)
                liveAssistantID = nil
            }
            return
        }

        guard !text.isEmpty else { return }
        let turn = ConversationTurn(role: .assistant, text: text)
        liveAssistantID = turn.id
        turns.append(turn)
        if isFinal {
            attachPendingCards(to: turns.count - 1)
            liveAssistantID = nil
        }
    }

    private func attachPendingCards(to index: Int) {
        guard let topic = pendingDeskTopic, topic != .general else {
            pendingDeskTopic = nil
            return
        }
        guard turns.indices.contains(index), turns[index].cards.isEmpty else {
            pendingDeskTopic = nil
            return
        }
        turns[index].cards = ConversationPresence.cards(for: topic, googleConnected: google.isConnected)
        pendingDeskTopic = nil
    }

    private func handleUserText(_ raw: String) async {
        guard let text = userDedupe.accept(text: raw, itemID: nil) else { return }
        completePlaybook()

        if matchesCancel(text) {
            voice.cancel()
            cancelPendingDraftsFromVoice()
            appendUser(text)
            appendAssistant("Stopped. Nothing was sent.")
            return
        }

        appendUser(text)

        if ConversationPresence.isJustTalk(text) {
            appendAssistant(ConversationPresence.justTalkReply)
            return
        }

        if ConversationPresence.wantsTour(text) {
            await runTour()
            return
        }
        if phase == .welcome {
            phase = .ready
        }

        if voice.usesLiveLoop {
            pendingDeskTopic = ConversationPresence.plan(for: text).topic
            await voice.sendTextTurn(text)
            return
        }

        await replyReady(to: text)
    }

    private func completePlaybook() {
        guard !hasCompletedPlaybook else { return }
        hasCompletedPlaybook = true
        playbook.hasCompleted = true
    }

    private func runTour() async {
        guard !isTourRunning else { return }
        isTourRunning = true
        phase = .touring

        await pause(320)
        appendAssistant(
            "You talk, I answer. When it’s your desk, I put the proof next to what I say — the email, the house, the people.",
            cards: TourScript.graphCards()
        )
        await voice.speak("Here’s that Beach Drive thread, the listing, and who’s on it.")

        await pause(400)
        appendAssistant(
            "If I need to send something, you’ll see the exact words first. I won’t go quiet and do it.",
            cards: [TourScript.draftCard()]
        )
        await voice.speak("Writes always wait for you.")

        await pause(400)
        appendAssistant(
            "Law and broker rules come with how sure I am, and the source. I won’t bluff.",
            cards: [TourScript.statuteCard()]
        )
        await voice.speak("Legal answers show confidence and the citation.")

        await pause(400)
        appendAssistant(
            "When you want me to know your real day, connect Google. Until then I’m still here — ask me anything.",
            cards: [TourScript.connectGoogleCard(isConnected: google.isConnected)]
        )
        await voice.speak("I’m here whenever you’re ready.")

        phase = .ready
        isTourRunning = false
    }

    private func replyReady(to text: String) async {
        let plan = ConversationPresence.plan(for: text)
        let cards = ConversationPresence.cards(for: plan.topic, googleConnected: google.isConnected)
        appendAssistant(plan.text, cards: cards)
        await voice.speak(plan.text)
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
            return ConversationPresence.tourOffer
        case .touring:
            return "Keep going."
        case .ready:
            return "What’s in my inbox?"
        }
    }

    private func matchesCancel(_ text: String) -> Bool {
        matches(text.lowercased(), ["stop", "cancel", "nevermind", "never mind", "abort"])
    }

    private func matches(_ lower: String, _ keys: [String]) -> Bool {
        keys.contains { lower.contains($0) }
    }

    private func pause(_ milliseconds: UInt64) async {
        if voice.isInstant { return }
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}
