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
    var showVoiceLog = false
    var isTourRunning = false
    var showVoiceSetup = false
    var hasCompletedPlaybook = false
    var deskSnapshot = DeskSnapshot.empty
    var isOnline = true
    var isSyncing = false
    /// First-load restore/sync chip. Not a chat turn. Never spoken.
    var launchSyncPhase: LaunchSyncPhase = .idle
    var launchStatusHold: Duration = .milliseconds(Int(LaunchSyncStatus.holdSeconds * 1000))

    let voice: VoiceBox
    let google: GoogleSession
    let wakeWord: WakeWordPlaceholder
    let sendClient: RecordingSendClient
    let playbook: PlaybookStoring
    let cache: DeskCaching
    /// Main-actor `GoogleSyncing` — never hop this existential off `@MainActor`.
    let sync: any GoogleSyncing
    let emailSummarizer: any EmailSummarizing
    let buildIdentity: BuildIdentity

    private var liveAssistantID: UUID?
    private var pendingDeskTopic: ConversationPresence.Topic?
    private var userDedupe = TranscriptDedupe()
    private var waitingToOfferConnectAfterTalk = false
    /// After we script Connect / email-body locally, drop Grok’s spoken contradiction.
    private var suppressLiveAssistant = false
    /// Last email the local path attached, for “show it to me” / full-thread follow-ups.
    private var lastFocusedEmail: EmailItem?
    private var pendingThreadSummary = false
    /// Last local reply asked “Who’s it from?” or “Which one?” — next utterance is desk.
    private var pendingSearchClarify = false
    /// After “no / not that one” a short ack (“Yeah”) stays desk, not small talk.
    private var pendingSenderRefine = false
    /// Cards from the last multi-match Gmail search, for “the last one” / “most recent.”
    private var lastSearchMatches: [EmailItem] = []
    /// Spoken ask that produced the last named/topic search — “that one” reuses its topic.
    private var lastSearchAsk: String?
    /// Last desk reply spoken via `voice.speak` — skip exact duplicates.
    private var lastSpokenDeskReply: String?
    private var lastUserUtterance = ""
    private var lastUserSource = "text"
    private var hadFocusedEmailAtTurnStart = false
    private var focusedPersonAtTurnStart: String?
    private var pendingGeneralVoiceLog = false
    private var pendingClarifyAtTurnStart = false
    private var pendingRefineAtTurnStart = false
    private var hadClarifyMatchesAtTurnStart = false
    private var expandEarlierEmailIDs: Set<UUID> = []
    private var expandEarlierProviderIDs: Set<String> = []
    var expandEarlierEpoch: Int = 0
    /// Last known listening visual — used for the off earcon, not Grok.
    private var voiceListeningVisual = false

    var showsTalkCoach: Bool {
        !hasCompletedPlaybook && voice.state == .idle && !voice.needsCredentials
    }

    var deskContext: DeskContext {
        DeskContext(
            isConnected: google.isConnected,
            clientIDConfigured: !google.setupNeeded,
            isOnline: isOnline,
            snapshot: deskSnapshot,
            auth: google.snapshot
        )
    }

    init(
        voice: (any VoiceServicing)? = nil,
        google: GoogleSession? = nil,
        wakeWord: WakeWordPlaceholder? = nil,
        sendClient: RecordingSendClient? = nil,
        playbook: PlaybookStoring? = nil,
        cache: DeskCaching? = nil,
        sync: (any GoogleSyncing)? = nil,
        isOnline: Bool = true,
        emailSummarizer: (any EmailSummarizing)? = nil,
        buildIdentity: BuildIdentity? = nil
    ) {
        self.voice = VoiceBox(service: voice ?? VoiceRuntime.makeService())
        self.google = google ?? GoogleSession.mock()
        self.wakeWord = wakeWord ?? WakeWordPlaceholder()
        self.sendClient = sendClient ?? RecordingSendClient(isOnline: isOnline)
        self.playbook = playbook ?? InMemoryPlaybookStore(completed: false)
        self.cache = cache ?? MemoryDeskCache()
        self.sync = sync ?? MockGoogleSync()
        self.emailSummarizer = emailSummarizer ?? HeuristicEmailSummarizer()
        self.buildIdentity = buildIdentity ?? BuildIdentity(infoDictionary: Bundle.main.infoDictionary)
        self.isOnline = isOnline
        self.hasCompletedPlaybook = self.playbook.hasCompleted
        // First paint: local cache only. Google restore + sync run after first frame.
        self.deskSnapshot = self.cache.load()
        self.voice.transcriptHandler = { [weak self] event in
            self?.handleLiveTranscript(event)
        }
        startWelcome()
        refreshPresence()
    }

    private static func makeLaunchPlaybookStore() -> PlaybookStoring {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return InMemoryPlaybookStore(completed: false)
        }
        return UserDefaultsPlaybookStore()
    }

    static func makeForLaunch() -> AppModel {
        let uiTesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        return AppModel(
            voice: VoiceRuntime.makeService(),
            google: GoogleSession.makeForLaunch(),
            playbook: makeLaunchPlaybookStore(),
            cache: uiTesting ? MemoryDeskCache() : FileDeskCache.applicationSupport(),
            sync: uiTesting ? MockGoogleSync() : LiveGoogleSync(),
            emailSummarizer: uiTesting ? HeuristicEmailSummarizer() : GrokEmailSummarizer.makeDefault()
        )
    }

    func applyUserTurn(_ text: String) async {
        await handleUserText(text)
    }

    var lastTurnID: UUID? { turns.last?.id }
    /// Bumps when a turn should be brought on-screen. Never used for compact expand.
    var conversationScrollEpoch: Int = 0
    var conversationScrollTarget: UUID?
    var conversationScrollAnchor: ConversationScrollAnchor = .top
    var conversationScrollReason: ConversationScrollReason = .none
    /// User dragged the thread — skip auto-scroll until the next user utterance.
    var userOwnsConversationScroll = false

    func startWelcome() {
        let firstRun = !hasCompletedPlaybook
        var suggestions = firstRun ? ConversationPresence.starterChips : [String]()
        if !firstRun,
           ConnectOfferPolicy.shouldSoftPrompt(
            isConnected: google.isConnected,
            lastSoftPromptAt: playbook.lastConnectSoftPromptAt
           ) {
            suggestions = [ConversationPresence.connectGoogleChip]
            playbook.lastConnectSoftPromptAt = Date()
        }
        turns = [
            ConversationTurn(
                role: .assistant,
                text: firstRun ? ConversationPresence.firstRunWelcome : ConversationPresence.returningWelcome,
                suggestions: suggestions
            )
        ]
        phase = .welcome
    }

    func voiceBecame(_ state: VoiceState) {
        voiceListeningVisual = state == .listening
        guard state == .idle, waitingToOfferConnectAfterTalk else { return }
        waitingToOfferConnectAfterTalk = false
        offerConnectIfNeeded()
    }

    func handleOpenURL(_ url: URL) -> Bool {
        google.handleURL(url)
    }

    func tapTalk() {
        completePlaybook()
        if !google.isConnected {
            waitingToOfferConnectAfterTalk = true
        }
        if voice.needsCredentials {
            showVoiceSetup = true
            return
        }
        switch voice.state {
        case .listening, .speaking, .thinking:
            VoiceEarcon.listenEnded()
            voiceListeningVisual = false
            voice.cancel()
            liveAssistantID = nil
            cancelPendingDraftsFromVoice()
        case .idle:
            VoiceEarcon.listenStarted()
            voiceListeningVisual = true
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
        sendClient.isOnline = isOnline
        let attempt = sendClient.send(draft)
        let outcome: String
        switch attempt {
        case .queuedNotDelivered:
            outcome = isOnline
                ? "Not sent — queued, not delivered. Gmail send waits on a write scope in a later slice."
                : "Queued until you’re back online. Not delivered."
        case .blockedUnconfirmed:
            outcome = "Blocked. Confirm is required before send."
        case .delivered:
            outcome = "Delivered."
        }
        activity.append(
            ActivityEntry(
                title: "\(draft.actionTitle) confirmed",
                detail: "\(draft.toLine) · \(draft.subject)",
                outcome: outcome
            )
        )
        appendAssistant(
            "Confirmed. It’s on Activity as queued, not sent. I won’t say “sent” until Google accepts the write."
        )
        Task { await voice.speak("Confirmed. Nothing was sent yet.") }
    }

    func cancelDraft(_ id: UUID) {
        updateDraft(id) { $0.status = DraftConfirmMachine.apply($0.status, .cancel) }
        let draft = draft(id)
        activity.append(
            ActivityEntry(
                title: "Write cancelled",
                detail: draft.map { "\($0.toLine) · \($0.subject)" } ?? "Draft",
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

    func connectGoogle() async {
        await google.connect()
        refreshGoogleCards()
        if google.setupNeeded || !google.isConnected {
            let copy = google.snapshot.message ?? GoogleAuthSnapshot.missingClientIDCopy
            activity.append(
                ActivityEntry(
                    title: "Google connect",
                    detail: "Gmail, Calendar, Tasks",
                    outcome: google.setupNeeded ? "Setup required. Not connected." : (google.snapshot.message ?? "Failed. Not connected.")
                )
            )
            appendAssistant(copy)
            return
        }
        await syncDesk()
        activity.append(
            ActivityEntry(
                title: "Google connect",
                detail: google.snapshot.email ?? "Gmail, Calendar, Tasks",
                outcome: "Connected. Last-synced reads are cached offline."
            )
        )
        appendAssistant(
            "Google is connected as \(google.snapshot.email ?? "your account"). Ask what’s in your inbox — I’ll only show synced mail."
        )
        await voice.speak("Google is connected.")
    }

    func disconnectGoogle() {
        google.disconnect()
        cache.clear()
        deskSnapshot = .empty
        refreshGoogleCards()
        refreshPresence()
        activity.append(
            ActivityEntry(
                title: "Google disconnect",
                detail: "Cached inbox, calendar, and tasks cleared",
                outcome: "Signed out. No leftover mail bodies."
            )
        )
        appendAssistant("Google is disconnected. Cached mail is gone — I won’t keep showing it.")
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
            if !event.isFinal {
                preemptGrokIfDeskTurn(event.text)
                return
            }
            handleLiveUser(event.text, itemID: event.itemID)
        case .assistant:
            upsertLiveAssistant(event.text, isFinal: event.isFinal)
        }
    }

    private func handleLiveUser(_ raw: String, itemID: String?) {
        guard let text = userDedupe.accept(text: raw, itemID: itemID) else { return }
        rememberUserTurn(text, source: "live voice")
        completePlaybook()

        if matchesCancel(text) {
            voice.cancel()
            cancelPendingDraftsFromVoice()
            appendUser(text)
            appendAssistant("Stopped. Nothing was sent.")
            logVoiceTurn(intentHint: "cancel", reply: "Stopped. Nothing was sent.", notes: ["voice stop"])
            return
        }

        appendUser(text)
        if phase == .welcome {
            phase = .ready
        }
        if ConversationPresence.wantsDeskPreview(text) {
            appendDeskPreview()
            return
        }
        if surfaceConnectGoogleIfAsked(text) {
            logVoiceTurn(intentHint: "connect", reply: turns.last?.text, cards: turns.last?.cards ?? [])
            return
        }
        if google.isConnected {
            let awaitingClarify = consumeSearchClarify()
            if ConversationPresence.ownsConnectedDeskTurn(
                text,
                pendingSearchClarify: awaitingClarify,
                hasClarifyMatches: !lastSearchMatches.isEmpty,
                hasFocusedEmail: lastFocusedEmail != nil,
                pendingSenderRefine: pendingSenderRefine
            ) {
                claimLocalAssistantReply()
                Task { await fulfillConnectedDeskTurn(text, awaitingClarify: awaitingClarify) }
                return
            }
        }
        if let evidence = ConversationPresence.deskEvidence(
            for: text,
            context: deskContext,
            focusedEmail: lastFocusedEmail,
            priorSearchAsk: lastSearchAsk
        ) {
            claimLocalAssistantReply()
            surfaceDeskEvidence(evidence)
            return
        }
        unmuteGrokAssistant()
        pendingDeskTopic = ConversationPresence.plan(for: text, context: deskContext).topic
        pendingGeneralVoiceLog = true
        if ConversationPresence.wantsTour(text) {
            Task { await runTour() }
            pendingGeneralVoiceLog = false
            logVoiceTurn(intentHint: "tour", reply: turns.last?.text, notes: ["tour"])
        }
        offerConnectIfNeeded()
    }

    private func upsertLiveAssistant(_ text: String, isFinal: Bool) {
        if ConversationPresence.isGrokDeskMeta(text) {
            return
        }
        if suppressLiveAssistant {
            return
        }
        if text.isEmpty, isFinal {
            if let id = liveAssistantID, let index = turns.firstIndex(where: { $0.id == id }) {
                attachPendingCards(to: index)
                liveAssistantID = nil
                finishGeneralVoiceLog(reply: turns[index].text)
            }
            return
        }

        if let id = liveAssistantID, let index = turns.firstIndex(where: { $0.id == id }) {
            turns[index].text += text
            if isFinal {
                attachPendingCards(to: index)
                liveAssistantID = nil
                finishGeneralVoiceLog(reply: turns[index].text)
            }
            return
        }

        guard !text.isEmpty else { return }
        let turn = ConversationTurn(role: .assistant, text: text)
        liveAssistantID = turn.id
        turns.append(turn)
        requestScroll(ConversationScrollPolicy.afterAssistant(turnID: turn.id, hasCards: false))
        if isFinal {
            attachPendingCards(to: turns.count - 1)
            liveAssistantID = nil
            finishGeneralVoiceLog(reply: turns.last?.text ?? text)
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
        turns[index].cards = ConversationPresence.cards(for: topic, context: deskContext)
        pendingDeskTopic = nil
        requestScroll(ConversationScrollPolicy.afterAssistant(turnID: turns[index].id, hasCards: true))
    }

    private func handleUserText(_ raw: String) async {
        let stripped = EarlyFinalHold.dropLeadingLeftoverStem(raw)
        guard let text = userDedupe.accept(text: stripped, itemID: nil) else { return }
        rememberUserTurn(text, source: "text")
        completePlaybook()

        if matchesCancel(text) {
            voice.cancel()
            cancelPendingDraftsFromVoice()
            appendUser(text)
            appendAssistant("Stopped. Nothing was sent.")
            logVoiceTurn(intentHint: "cancel", reply: "Stopped. Nothing was sent.", notes: ["voice stop"])
            return
        }

        appendUser(text)

        if ConversationPresence.isJustTalk(text) {
            appendAssistant(ConversationPresence.justTalkReply)
            offerConnectIfNeeded()
            logVoiceTurn(intentHint: "general", reply: ConversationPresence.justTalkReply, notes: ["just talk"])
            return
        }

        if ConversationPresence.wantsDeskPreview(text) {
            appendDeskPreview()
            return
        }

        if ConversationPresence.wantsTour(text) {
            await runTour()
            logVoiceTurn(intentHint: "tour", reply: turns.last?.text, notes: ["tour"])
            return
        }
        if phase == .welcome {
            phase = .ready
        }

        if surfaceConnectGoogleIfAsked(text) {
            logVoiceTurn(intentHint: "connect", reply: turns.last?.text, cards: turns.last?.cards ?? [])
            return
        }

        if google.isConnected {
            let awaitingClarify = consumeSearchClarify()
            if ConversationPresence.ownsConnectedDeskTurn(
                text,
                pendingSearchClarify: awaitingClarify,
                hasClarifyMatches: !lastSearchMatches.isEmpty,
                hasFocusedEmail: lastFocusedEmail != nil,
                pendingSenderRefine: pendingSenderRefine
            ) {
                claimLocalAssistantReply()
                await fulfillConnectedDeskTurn(text, awaitingClarify: awaitingClarify)
                return
            }
        }

        if let evidence = ConversationPresence.deskEvidence(
            for: text,
            context: deskContext,
            focusedEmail: lastFocusedEmail,
            priorSearchAsk: lastSearchAsk
        ) {
            claimLocalAssistantReply()
            await applyDeskEvidence(evidence)
            return
        }

        if voice.usesLiveLoop {
            unmuteGrokAssistant()
            pendingDeskTopic = ConversationPresence.plan(for: text, context: deskContext).topic
            pendingGeneralVoiceLog = true
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

    private func appendDeskPreview() {
        if phase == .welcome { phase = .ready }
        appendAssistant(
            ConversationPresence.deskPreviewReply,
            cards: TourScript.deskPreviewCards()
        )
        offerConnectIfNeeded()
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
            ConversationPresence.connectCoach,
            cards: [.connectGoogle(deskContext.connectItem)]
        )
        playbook.hasSeenConnectOffer = true
        await voice.speak(ConversationPresence.connectCoach)

        phase = .ready
        isTourRunning = false
    }

    private func replyReady(to text: String) async {
        let plan = ConversationPresence.plan(for: text, context: deskContext)
        let cards = ConversationPresence.cards(for: plan.topic, context: deskContext)
        appendAssistant(plan.text, cards: cards)
        await voice.speak(plan.text)
        logVoiceTurn(intentHint: "general", reply: plan.text, cards: cards, notes: ["local plan"])
    }

    /// Stop Grok from contradicting a local Connect / email-body reply on the thread.
    private func claimLocalAssistantReply() {
        suppressLiveAssistant = true
        voice.interruptResponse()
        voice.suppressAssistantOutput(true)
        if let id = liveAssistantID, let index = turns.firstIndex(where: { $0.id == id }) {
            turns.remove(at: index)
        }
        liveAssistantID = nil
        pendingDeskTopic = nil
        scrubGrokDeskRefusals()
    }

    private func unmuteGrokAssistant() {
        suppressLiveAssistant = false
        voice.suppressAssistantOutput(false)
    }

    /// Interrupt as soon as a partial transcript looks like a connected desk ask.
    private func preemptGrokIfDeskTurn(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if ConversationPresence.wantsVersionAsk(text) {
            claimLocalAssistantReply()
            return
        }
        guard google.isConnected else { return }
        if ConversationPresence.ownsConnectedDeskTurn(
            text,
            pendingSearchClarify: pendingSearchClarify,
            hasClarifyMatches: !lastSearchMatches.isEmpty,
            hasFocusedEmail: lastFocusedEmail != nil,
            pendingSenderRefine: pendingSenderRefine
        ) {
            claimLocalAssistantReply()
        }
    }

    private func scrubGrokDeskRefusals() {
        let cutoff = Date().addingTimeInterval(-60)
        turns.removeAll { turn in
            turn.role == .assistant
                && turn.cards.isEmpty
                && turn.createdAt >= cutoff
                && ConversationPresence.isGrokDeskMeta(turn.text)
        }
    }

    /// Live voice and typed path: attach the Connect Google card on the user ask.
    /// Do not wait for Grok — there is no Settings screen to invent.
    @discardableResult
    private func surfaceConnectGoogleIfAsked(_ text: String) -> Bool {
        let plan = ConversationPresence.plan(for: text, context: deskContext)
        guard plan.topic == .google else { return false }
        claimLocalAssistantReply()
        pendingDeskTopic = nil
        appendAssistant(
            plan.text,
            cards: ConversationPresence.cards(for: .google, context: deskContext)
        )
        if !google.isConnected {
            playbook.hasSeenConnectOffer = true
        }
        return true
    }

    func openEmail(_ item: EmailItem) {
        lastFocusedEmail = item
        Task { await revealEmailBody(item) }
    }

    /// Compact ↔ full Mail reader. Same tap. Stay in place. No new bubble.
    func toggleEmailCard(_ item: EmailItem) {
        lastFocusedEmail = item
        for index in turns.indices {
            for cardIndex in turns[index].cards.indices {
                if case .email(let existing) = turns[index].cards[cardIndex],
                   existing.id == item.id || (existing.providerID != nil && existing.providerID == item.providerID) {
                    turns[index].cards[cardIndex] = .email(existing.togglingCardPresentation())
                }
            }
        }
    }

    func noteUserScrolling() {
        userOwnsConversationScroll = true
    }

    func expandsEarlierMessages(_ email: EmailItem) -> Bool {
        if expandEarlierEmailIDs.contains(email.id) { return true }
        if let providerID = email.providerID, expandEarlierProviderIDs.contains(providerID) {
            return true
        }
        if let threadID = email.threadID, expandEarlierProviderIDs.contains(threadID) {
            return true
        }
        return false
    }

    private func markExpandEarlier(for email: EmailItem) {
        expandEarlierEmailIDs.insert(email.id)
        if let providerID = email.providerID { expandEarlierProviderIDs.insert(providerID) }
        if let threadID = email.threadID { expandEarlierProviderIDs.insert(threadID) }
        expandEarlierEpoch += 1
    }

    private func rememberEvidence(_ evidence: ConversationPresence.DeskEvidence) {
        if evidence.resetsFocusedEmail {
            lastFocusedEmail = evidence.focusedEmail
        } else if let email = evidence.focusedEmail {
            lastFocusedEmail = email
        }
        pendingThreadSummary = evidence.expandEarlierMessages
        pendingSearchClarify = evidence.awaitsSearchClarify
        pendingSenderRefine = evidence.keepsSenderRefine
        if evidence.awaitsSearchClarify {
            let cards = evidence.cards.compactMap { card -> EmailItem? in
                if case .email(let item) = card { return item }
                return nil
            }
            if !cards.isEmpty {
                lastSearchMatches = EmailRecency.newestFirst(cards)
            }
        } else {
            lastSearchMatches = []
        }
        if let ask = evidence.searchAsk, !ask.isEmpty {
            lastSearchAsk = ask
        } else if let plan = GmailSearchQuery.plan(from: lastUserUtterance),
                  !plan.subjectTokens.isEmpty {
            lastSearchAsk = lastUserUtterance
        }
        if evidence.expandEarlierMessages, let email = evidence.focusedEmail {
            markExpandEarlier(for: email)
        }
    }

    private func consumeSearchClarify() -> Bool {
        if pendingSearchClarify { return true }
        guard let last = turns.last(where: { $0.role == .assistant }) else { return false }
        if last.text == ConversationPresence.emailNeedMoreReply { return true }
        if last.text == ConversationPresence.gmailSearchSeveralReply {
            if lastSearchMatches.isEmpty {
                lastSearchMatches = last.cards.compactMap { card in
                    if case .email(let item) = card { return item }
                    return nil
                }
            }
            return true
        }
        return false
    }

    /// Inbox-overview / calendar-overview must hit Google before cards are built.
    private func fulfillConnectedDeskTurn(_ text: String, awaitingClarify: Bool) async {
        if shouldRefreshDeskSnapshot(for: text) {
            await syncDesk()
        }
        if let evidence = ConversationPresence.deskEvidence(
            for: text,
            context: deskContext,
            focusedEmail: lastFocusedEmail,
            pendingSearchClarify: awaitingClarify,
            clarifyMatches: lastSearchMatches,
            pendingSenderRefine: pendingSenderRefine,
            priorSearchAsk: lastSearchAsk
        ) {
            await applyDeskEvidence(evidence)
        } else {
            pendingSearchClarify = true
            appendAssistant(ConversationPresence.emailNeedMoreReply)
            await speakDeskReply(ConversationPresence.emailNeedMoreReply)
            logVoiceTurn(
                evidence: nil,
                reply: ConversationPresence.emailNeedMoreReply,
                notes: ["need-more"]
            )
        }
    }

    private func shouldRefreshDeskSnapshot(for text: String) -> Bool {
        guard google.isConnected, isOnline else { return false }
        if ConversationPresence.wantsInboxOverview(text) {
            return InboxGlanceSpeakPlan.shouldRefreshGmailListBeforeFirstSpeak(
                ask: text,
                snapshot: deskSnapshot,
                isConnected: true,
                isOnline: true
            )
        }
        return ConversationPresence.wantsCalendarAsk(text) && deskSnapshot.events.isEmpty
    }

    private func surfaceDeskEvidence(_ evidence: ConversationPresence.DeskEvidence) {
        Task { await applyDeskEvidence(evidence) }
    }

    private func applyDeskEvidence(_ evidence: ConversationPresence.DeskEvidence) async {
        rememberEvidence(evidence)
        if evidence.topic == .version {
            let line = ConversationPresence.spokenIdentityLine(
                for: lastUserUtterance,
                identity: buildIdentity
            )
            appendAssistant(line)
            await speakDeskReply(line)
            logVoiceTurn(
                evidence: evidence,
                intentHint: "version",
                reply: line,
                cards: [],
                notes: ["local build identity", buildIdentity.dogfoodLine]
            )
            return
        }
        if evidence.shouldSearchGmail, let query = evidence.gmailQuery, !query.isEmpty {
            await searchGmail(query, plan: evidence.gmailPlan, ask: evidence.searchAsk)
            logVoiceTurn(
                evidence: evidence,
                reply: spokenReplyForLog(fallback: turns.last?.text),
                cards: turns.last?.cards ?? []
            )
            return
        }
        if evidence.shouldFetchBody, let email = evidence.focusedEmail {
            await revealEmailBody(email)
            logVoiceTurn(
                evidence: evidence,
                reply: spokenReplyForLog(fallback: turns.last?.text),
                cards: turns.last?.cards ?? []
            )
            return
        }
        if evidence.shouldGlanceInbox {
            await applyInboxGlance(evidence)
            return
        }
        // Calendar overview (and any other cards-only evidence): speak `text`,
        // don’t reprint it in the bubble. Cards are the visual — same as inbox.
        appendAssistant(InboxGlance.onScreenText(for: evidence), cards: evidence.cards)
        await speakDeskReply(evidence.text)
        logVoiceTurn(evidence: evidence, reply: evidence.text)
    }

    private func applyInboxGlance(_ evidence: ConversationPresence.DeskEvidence) async {
        let emails = evidence.cards.compactMap { card -> EmailItem? in
            if case .email(let item) = card { return item }
            return nil
        }
        // Cache-hot glance: first audio is the snapshot heuristic. Do not await
        // xAI’s five-line rewrite or a Gmail list refresh before speak.
        let plan = InboxGlanceSpeakPlan.fromCachedEmails(
            emails,
            ask: lastUserUtterance,
            fallbackText: evidence.text
        )
        let spoken = plan.spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? evidence.text
            : plan.spokenText
        // Cards are the list. Speak one short beat; don’t recite Name — topic lines.
        let onScreen = emails.isEmpty
            ? spoken
            : InboxGlance.onScreenText(compactCardCount: emails.count)
        appendAssistant(onScreen, cards: evidence.cards)
        await speakDeskReply(spoken)
        logVoiceTurn(
            evidence: evidence,
            reply: spoken,
            cards: evidence.cards,
            notes: plan.voiceLogNotes
        )
    }

    @discardableResult
    private func appendThinkingBeat() -> UUID {
        let turn = ConversationTurn(role: .assistant, text: ConversationPresence.thinkingStatusBeat)
        turns.append(turn)
        requestScroll(ConversationScrollPolicy.afterAssistant(turnID: turn.id, hasCards: false))
        return turn.id
    }

    private func searchGmail(_ query: String, plan: GmailSearchPlan?, ask: String?) async {
        guard google.isConnected, let token = google.accessToken else {
            appendAssistant(
                ConversationPresence.connectHowToReply,
                cards: [.connectGoogle(deskContext.connectItem)]
            )
            await speakDeskReply(ConversationPresence.connectHowToReply)
            return
        }
        let beatID = appendSearchingBeat()
        let variants = (plan?.variants.isEmpty == false) ? plan!.variants : [query]
        do {
            var found: [EmailItem] = []
            for variant in variants {
                found = try await sync.searchMessages(token: token, query: variant, now: Date())
                if !found.isEmpty { break }
            }
            let owner = deskContext.mailboxOwner
            let picked: GmailSearchPick
            if let plan {
                picked = GmailSearchQuery.pick(found, plan: plan, owner: owner)
            } else if let ask {
                picked = GmailSearchQuery.pick(found, ask: ask, owner: owner)
            } else if found.isEmpty {
                picked = .none
            } else if found.count == 1 {
                picked = .one(found[0])
            } else {
                picked = .several(Array(found.prefix(3)))
            }
            switch picked {
            case .none:
                replaceAssistant(id: beatID, text: ConversationPresence.gmailSearchEmptyReply)
                await speakDeskReply(ConversationPresence.gmailSearchEmptyReply)
            case .selfOnly:
                let reply = ConversationPresence.selfSenderClarifyReply(ask: ask ?? query, owner: owner)
                replaceAssistant(id: beatID, text: reply)
                await speakDeskReply(reply)
            case .one(let email):
                removeTurn(id: beatID)
                await applyLoadedEmail(email, mergeIntoInbox: false)
            case .several(let emails):
                let ranked = EmailRecency.newestFirst(emails)
                lastSearchMatches = ranked
                lastFocusedEmail = ranked.first
                pendingSearchClarify = true
                refreshPresence()
                scrubGrokDeskRefusals()
                replaceAssistant(
                    id: beatID,
                    text: ConversationPresence.gmailSearchSeveralReply,
                    cards: EmailItem.listCards(ranked)
                )
                await speakDeskReply(ConversationPresence.gmailSearchSeveralReply)
            }
        } catch {
            replaceAssistant(id: beatID, text: ConversationPresence.gmailSearchFailedReply)
            await speakDeskReply(ConversationPresence.gmailSearchFailedReply)
        }
    }

    @discardableResult
    private func appendSearchingBeat() -> UUID {
        let turn = ConversationTurn(role: .assistant, text: ConversationPresence.gmailSearchingBeat)
        turns.append(turn)
        requestScroll(ConversationScrollPolicy.afterAssistant(turnID: turn.id, hasCards: false))
        return turn.id
    }

    private func replaceAssistant(id: UUID, text: String, cards: [ContentCard] = []) {
        if let index = turns.firstIndex(where: { $0.id == id }) {
            turns[index].text = text
            turns[index].cards = cards
            requestScroll(ConversationScrollPolicy.afterAssistant(turnID: id, hasCards: !cards.isEmpty))
            return
        }
        appendAssistant(text, cards: cards)
    }

    private func removeTurn(id: UUID) {
        turns.removeAll { $0.id == id }
    }

    private func revealEmailBody(_ email: EmailItem) async {
        guard google.isConnected, let token = google.accessToken, let id = email.providerID, !id.isEmpty else {
            await applyLoadedEmail(email)
            return
        }
        do {
            let full = try await sync.fetchMessage(token: token, messageID: id, now: Date())
            await applyLoadedEmail(full)
        } catch {
            refreshEmailCards(email)
            if pendingThreadSummary || email.hasFullBody || email.hasEarlierMessages {
                await applyLoadedEmail(email)
            } else {
                let reply = ConversationPresence.emailBodySyncFailedReply(email)
                appendAssistant(reply, cards: [.email(email)])
                await speakDeskReply(reply)
            }
        }
    }

    private func applyLoadedEmail(_ email: EmailItem, mergeIntoInbox: Bool = true) async {
        if mergeIntoInbox {
            upsertSnapshotEmail(email)
            cache.save(deskSnapshot)
        }
        refreshPresence()
        refreshEmailCards(email)
        lastFocusedEmail = email
        if pendingThreadSummary {
            markExpandEarlier(for: email)
        }
        let includeEarlier = pendingThreadSummary
        pendingThreadSummary = false
        let xai = await emailSummarizer.summarize(
            EmailSummaryRequest.from(email, includeEarlier: includeEarlier)
        )
        let reply = DeskReplySpeech.spokenDeskHit(
            email,
            xaiSummarize: xai,
            includeEarlier: includeEarlier
        )
        scrubGrokDeskRefusals()
        // Card is the visual. Eve still speaks `reply`; do not reprint it in the bubble.
        appendAssistant(
            InboxGlance.onScreenTextHidingSpokenSummary(),
            cards: [.email(email.presented(as: .full))]
        )
        await speakDeskReply(reply)
    }

    private func speakDeskReplyLater(_ text: String) {
        Task { await speakDeskReply(text) }
    }

    /// Cards-only bubbles are empty. Dogfood `assistantReply` is what Eve spoke.
    private func spokenReplyForLog(fallback: String?) -> String {
        if let spoken = lastSpokenDeskReply, !spoken.isEmpty {
            return spoken
        }
        return fallback ?? ""
    }

    private func speakDeskReply(_ text: String) async {
        guard let spoken = DeskReplySpeech.textToSpeak(text, lastSpoken: lastSpokenDeskReply) else {
            return
        }
        lastSpokenDeskReply = spoken
        await voice.speak(spoken)
    }

    private func rememberUserTurn(_ text: String, source: String) {
        lastUserUtterance = text
        lastUserSource = source
        hadFocusedEmailAtTurnStart = lastFocusedEmail != nil
        focusedPersonAtTurnStart = lastFocusedEmail?.fromName
        pendingClarifyAtTurnStart = pendingSearchClarify
        pendingRefineAtTurnStart = pendingSenderRefine
        hadClarifyMatchesAtTurnStart = !lastSearchMatches.isEmpty
        pendingGeneralVoiceLog = false
    }

    private func finishGeneralVoiceLog(reply: String) {
        guard pendingGeneralVoiceLog else { return }
        pendingGeneralVoiceLog = false
        logVoiceTurn(
            intentHint: "general",
            reply: reply,
            cards: turns.last?.cards ?? [],
            notes: ["live Grok"]
        )
    }

    private func logVoiceTurn(
        evidence: ConversationPresence.DeskEvidence? = nil,
        intentHint: String? = nil,
        reply: String? = nil,
        cards: [ContentCard]? = nil,
        notes extraNotes: [String] = []
    ) {
        guard VoiceDogfoodGate.allowsLogging else {
            _ = evidence
            _ = intentHint
            _ = reply
            _ = cards
            _ = extraNotes
            return
        }
        let classified = VoiceInteractionLog.classify(
            utterance: lastUserUtterance,
            evidence: evidence,
            pendingSearchClarify: pendingClarifyAtTurnStart,
            hadFocusedEmail: hadFocusedEmailAtTurnStart,
            hasClarifyMatches: hadClarifyMatchesAtTurnStart,
            pendingSenderRefine: pendingRefineAtTurnStart
        )
        var notes = classified.notes + extraNotes
        if intentHint == "cancel" { notes.append("user stop") }
        if classified.intent == "inbox-overview" || classified.intent == "calendar",
           let age = GoogleSyncPolicy.cacheAgeNote(lastSyncedAt: deskSnapshot.lastSyncedAt) {
            notes.append(age)
        }
        var errors: [String] = []
        if let error = voice.lastError, !error.isEmpty {
            errors.append(error)
        }
        let voicePath: String
        if voice.usesLiveLoop {
            voicePath = "Eve realtime"
        } else {
            voicePath = "AVSpeech"
        }
        let focused = classified.focusedPerson
            ?? evidence?.focusedEmail?.fromName
            ?? (classified.sticky == .reused ? focusedPersonAtTurnStart : nil)
        let entry = VoiceInteractionEntry(
            source: lastUserSource,
            userTranscript: lastUserUtterance,
            intent: intentHint ?? classified.intent,
            sticky: classified.sticky,
            focusedPerson: focused,
            searchQuery: classified.searchQuery ?? evidence?.gmailQuery,
            routingNotes: notes,
            cardsAttached: VoiceInteractionLog.cardLabels(cards ?? evidence?.cards ?? []),
            assistantReply: reply ?? evidence?.text ?? "",
            voicePath: voicePath,
            errors: errors
        )
        VoiceInteractionLog.record(entry)
        #if DEBUG
        DebugVoiceLogFile.append(entry)
        #endif
        VoiceCloudDogfoodClient.shared.enqueue(entry)
    }

    private func upsertSnapshotEmail(_ email: EmailItem) {
        if let index = deskSnapshot.emails.firstIndex(where: { $0.providerID == email.providerID && $0.providerID != nil }) {
            deskSnapshot.emails[index] = email
        } else if let index = deskSnapshot.emails.firstIndex(where: { $0.id == email.id }) {
            deskSnapshot.emails[index] = email
        } else {
            deskSnapshot.emails.insert(email, at: 0)
        }
    }

    private func refreshEmailCards(_ email: EmailItem) {
        var updated = false
        for index in turns.indices {
            for cardIndex in turns[index].cards.indices {
                if case .email(let existing) = turns[index].cards[cardIndex],
                   existing.providerID == email.providerID || existing.id == email.id {
                    turns[index].cards[cardIndex] = .email(email.presented(as: existing.cardPresentation))
                    updated = true
                }
            }
        }
        _ = updated
    }

    private func offerConnectIfNeeded() {
        guard ConnectOfferPolicy.shouldShowFirstConnectOffer(
            playbookCompleted: hasCompletedPlaybook,
            hasSeenOffer: playbook.hasSeenConnectOffer,
            isConnected: google.isConnected
        ) else { return }
        playbook.hasSeenConnectOffer = true
        appendAssistant(
            ConversationPresence.connectCoach,
            cards: [.connectGoogle(deskContext.connectItem)],
            suggestions: [ConversationPresence.connectGoogleChip]
        )
    }

    /// After the first ConversationScreen frame. Cache was already loaded in `init`.
    /// Google restore + inbox refresh + live Grok warmup must not block first paint.
    func prepareAfterFirstPaint() async {
        async let restore: Void = restoreGoogleIfNeeded()
        async let warmup: Void = voice.warmUp()
        _ = await (restore, warmup)
    }

    func restoreGoogleIfNeeded() async {
        launchSyncPhase = .restoringGoogle
        await google.restoreSession()
        if google.isConnected {
            deskSnapshot = cache.load()
            if GoogleSyncPolicy.shouldRefreshOnRestore(
                isConnected: true,
                isOnline: isOnline,
                lastSyncedAt: deskSnapshot.lastSyncedAt
            ) {
                await syncDesk(announceLaunch: true)
            } else {
                launchSyncPhase = .idle
            }
            refreshPresence()
            refreshGoogleCards()
        } else {
            launchSyncPhase = .idle
        }
    }

    func syncDesk(announceLaunch: Bool = false) async {
        guard google.isConnected, let token = google.accessToken else {
            if announceLaunch { launchSyncPhase = .idle }
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        if announceLaunch {
            launchSyncPhase = .syncingInbox
        }
        let cachedIDs = Set(deskSnapshot.emails.compactMap(\.providerID).filter { !$0.isEmpty })
        do {
            let next = try await sync.sync(
                token: token,
                accountEmail: google.snapshot.email ?? "",
                now: Date()
            )
            let merged = DeskSnapshotMerge.applying(incoming: next, onto: deskSnapshot)
            deskSnapshot = merged
            cache.save(merged)
            refreshPresence()
            if announceLaunch {
                launchSyncPhase = LaunchSyncStatus.phaseAfterInboxIDs(
                    next.emails.compactMap(\.providerID),
                    cachedProviderIDs: cachedIDs
                )
                await finishLaunchStatus(success: true)
            }
        } catch {
            var cached = cache.load()
            cached.lastError = error.localizedDescription
            deskSnapshot = cached
            if cached.hasAnyReads {
                appendAssistant("Couldn’t refresh Google. Showing the last-synced cards. I won’t invent mail.")
            } else if !isOnline {
                appendAssistant("You’re offline and I don’t have a cached inbox yet.")
            }
            if announceLaunch {
                await finishLaunchStatus(success: false)
            }
        }
    }

    private func finishLaunchStatus(success: Bool) async {
        launchSyncPhase = success ? .inboxUpToDate : .refreshFailed
        if launchStatusHold > .zero {
            try? await Task.sleep(for: launchStatusHold)
        }
        launchSyncPhase = .idle
    }

    private func refreshPresence() {
        voice.updatePresenceInstructions(GrokRealtime.presenceInstructions(for: deskContext))
    }

    private func refreshGoogleCards() {
        for index in turns.indices {
            for cardIndex in turns[index].cards.indices {
                if case .connectGoogle = turns[index].cards[cardIndex] {
                    turns[index].cards[cardIndex] = .connectGoogle(deskContext.connectItem)
                }
            }
        }
    }

    // MARK: - Mutations

    private func appendUser(_ text: String) {
        userOwnsConversationScroll = false
        let turn = ConversationTurn(role: .user, text: text)
        turns.append(turn)
        requestScroll(ConversationScrollPolicy.afterUser(turnID: turn.id))
    }

    private func appendAssistant(_ text: String, cards: [ContentCard] = [], suggestions: [String] = []) {
        let turn = ConversationTurn(role: .assistant, text: text, cards: cards, suggestions: suggestions)
        turns.append(turn)
        requestScroll(ConversationScrollPolicy.afterAssistant(turnID: turn.id, hasCards: !cards.isEmpty))
    }

    func noteVisibleCardGrew() {
        // Card height growth (compact expand / HTML measure) must not jump the thread.
    }

    private func requestScroll(_ request: ConversationScrollRequest) {
        guard !userOwnsConversationScroll else { return }
        conversationScrollTarget = request.targetID
        conversationScrollAnchor = request.anchor
        conversationScrollReason = request.reason
        conversationScrollEpoch += 1
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
