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
    var deskSnapshot = DeskSnapshot.empty
    var isOnline = true
    var isSyncing = false

    let voice: VoiceBox
    let google: GoogleSession
    let wakeWord: WakeWordPlaceholder
    let sendClient: RecordingSendClient
    let playbook: PlaybookStoring
    let cache: DeskCaching
    /// Main-actor `GoogleSyncing` — never hop this existential off `@MainActor`.
    let sync: any GoogleSyncing

    private var liveAssistantID: UUID?
    private var pendingDeskTopic: ConversationPresence.Topic?
    private var userDedupe = TranscriptDedupe()
    private var waitingToOfferConnectAfterTalk = false
    /// After we script Connect / email-body locally, drop Grok’s spoken contradiction.
    private var suppressLiveAssistant = false
    /// Last email the local path attached, for “show it to me” / full-thread follow-ups.
    private var lastFocusedEmail: EmailItem?
    private var pendingThreadSummary = false
    private var expandEarlierEmailIDs: Set<UUID> = []
    private var expandEarlierProviderIDs: Set<String> = []
    var expandEarlierEpoch: Int = 0

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
        isOnline: Bool = true
    ) {
        self.voice = VoiceBox(service: voice ?? VoiceRuntime.makeService())
        self.google = google ?? GoogleSession.mock()
        self.wakeWord = wakeWord ?? WakeWordPlaceholder()
        self.sendClient = sendClient ?? RecordingSendClient(isOnline: isOnline)
        self.playbook = playbook ?? InMemoryPlaybookStore(completed: false)
        self.cache = cache ?? MemoryDeskCache()
        self.sync = sync ?? MockGoogleSync()
        self.isOnline = isOnline
        self.hasCompletedPlaybook = self.playbook.hasCompleted
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
            sync: uiTesting ? MockGoogleSync() : LiveGoogleSync()
        )
    }

    func applyUserTurn(_ text: String) async {
        await handleUserText(text)
    }

    var lastTurnID: UUID? { turns.last?.id }
    /// Bumps when cards are appended or refreshed so ConversationScreen can scroll them on-screen.
    var conversationScrollEpoch: Int = 0
    var conversationScrollTarget: UUID?

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

    func connectGoogle() {
        Task {
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
        if phase == .welcome {
            phase = .ready
        }
        if ConversationPresence.wantsDeskPreview(text) {
            appendDeskPreview()
            return
        }
        if surfaceConnectGoogleIfAsked(text) {
            return
        }
        if let evidence = ConversationPresence.deskEvidence(
            for: text,
            context: deskContext,
            focusedEmail: lastFocusedEmail
        ) {
            claimLocalAssistantReply()
            surfaceDeskEvidence(evidence)
            return
        }
        suppressLiveAssistant = false
        pendingDeskTopic = ConversationPresence.plan(for: text, context: deskContext).topic
        if ConversationPresence.wantsTour(text) {
            Task { await runTour() }
        }
        offerConnectIfNeeded()
    }

    private func upsertLiveAssistant(_ text: String, isFinal: Bool) {
        if suppressLiveAssistant {
            return
        }
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
        turns[index].cards = ConversationPresence.cards(for: topic, context: deskContext)
        pendingDeskTopic = nil
        requestScrollToLatestCards(preferring: turns[index].cards.last?.id ?? turns[index].id)
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
            offerConnectIfNeeded()
            return
        }

        if ConversationPresence.wantsDeskPreview(text) {
            appendDeskPreview()
            return
        }

        if ConversationPresence.wantsTour(text) {
            await runTour()
            return
        }
        if phase == .welcome {
            phase = .ready
        }

        if surfaceConnectGoogleIfAsked(text) {
            return
        }

        if let evidence = ConversationPresence.deskEvidence(
            for: text,
            context: deskContext,
            focusedEmail: lastFocusedEmail
        ) {
            claimLocalAssistantReply()
            await applyDeskEvidence(evidence)
            return
        }

        if voice.usesLiveLoop {
            pendingDeskTopic = ConversationPresence.plan(for: text, context: deskContext).topic
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
    }

    /// Stop Grok from contradicting a local Connect / email-body reply on the thread.
    private func claimLocalAssistantReply() {
        suppressLiveAssistant = true
        voice.interruptResponse()
        if let id = liveAssistantID, let index = turns.firstIndex(where: { $0.id == id }) {
            turns.remove(at: index)
        }
        liveAssistantID = nil
        pendingDeskTopic = nil
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
        if let email = evidence.focusedEmail {
            lastFocusedEmail = email
        }
        pendingThreadSummary = evidence.expandEarlierMessages
        if evidence.expandEarlierMessages, let email = evidence.focusedEmail {
            markExpandEarlier(for: email)
        }
    }

    private func surfaceDeskEvidence(_ evidence: ConversationPresence.DeskEvidence) {
        rememberEvidence(evidence)
        if evidence.shouldSearchGmail || (evidence.shouldFetchBody && evidence.focusedEmail != nil) {
            Task { await applyDeskEvidence(evidence) }
            return
        }
        appendAssistant(evidence.text, cards: evidence.cards)
    }

    private func applyDeskEvidence(_ evidence: ConversationPresence.DeskEvidence) async {
        rememberEvidence(evidence)
        if evidence.shouldSearchGmail, let query = evidence.gmailQuery, !query.isEmpty {
            await searchGmail(query)
            return
        }
        if evidence.shouldFetchBody, let email = evidence.focusedEmail {
            await revealEmailBody(email)
            return
        }
        appendAssistant(evidence.text, cards: evidence.cards)
    }

    private func searchGmail(_ query: String) async {
        guard google.isConnected, let token = google.accessToken else {
            appendAssistant(
                ConversationPresence.connectHowToReply,
                cards: [.connectGoogle(deskContext.connectItem)]
            )
            return
        }
        do {
            let found = try await sync.searchMessages(token: token, query: query, now: Date())
            if found.isEmpty {
                appendAssistant(ConversationPresence.gmailSearchEmptyReply)
                return
            }
            if found.count == 1 {
                applyLoadedEmail(found[0])
                return
            }
            let top = Array(found.prefix(3))
            for email in top {
                upsertSnapshotEmail(email)
            }
            cache.save(deskSnapshot)
            refreshPresence()
            lastFocusedEmail = top.first
            appendAssistant(
                ConversationPresence.gmailSearchSeveralReply,
                cards: top.map { .email($0) }
            )
        } catch {
            appendAssistant(ConversationPresence.gmailSearchFailedReply)
        }
    }

    private func revealEmailBody(_ email: EmailItem) async {
        guard google.isConnected, let token = google.accessToken, let id = email.providerID, !id.isEmpty else {
            applyLoadedEmail(email)
            return
        }
        do {
            let full = try await sync.fetchMessage(token: token, messageID: id, now: Date())
            applyLoadedEmail(full)
        } catch {
            refreshEmailCards(email)
            if pendingThreadSummary || email.hasFullBody || email.hasEarlierMessages {
                applyLoadedEmail(email)
            } else {
                appendAssistant(
                    ConversationPresence.emailBodySyncFailedReply(email),
                    cards: [.email(email)]
                )
            }
        }
    }

    private func applyLoadedEmail(_ email: EmailItem) {
        upsertSnapshotEmail(email)
        cache.save(deskSnapshot)
        refreshPresence()
        refreshEmailCards(email)
        lastFocusedEmail = email
        if pendingThreadSummary {
            markExpandEarlier(for: email)
        }
        let reply = pendingThreadSummary
            ? ConversationPresence.emailThreadReply(email)
            : ConversationPresence.emailBodyReply(email)
        pendingThreadSummary = false
        appendAssistant(reply, cards: [.email(email)])
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
                    turns[index].cards[cardIndex] = .email(email)
                    updated = true
                }
            }
        }
        if updated {
            requestScrollToLatestCards(preferring: email.id)
        }
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

    func restoreGoogleIfNeeded() async {
        await google.restoreSession()
        if google.isConnected {
            deskSnapshot = cache.load()
            if deskSnapshot.accountEmail == nil {
                await syncDesk()
            } else {
                refreshPresence()
            }
            refreshGoogleCards()
        }
    }

    func syncDesk() async {
        guard google.isConnected, let token = google.accessToken else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let next = try await sync.sync(
                token: token,
                accountEmail: google.snapshot.email ?? "",
                now: Date()
            )
            deskSnapshot = next
            cache.save(next)
            refreshPresence()
        } catch {
            var cached = cache.load()
            cached.lastError = error.localizedDescription
            deskSnapshot = cached
            if cached.hasAnyReads {
                appendAssistant("Couldn’t refresh Google. Showing the last-synced cards. I won’t invent mail.")
            } else if !isOnline {
                appendAssistant("You’re offline and I don’t have a cached inbox yet.")
            }
        }
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
        turns.append(ConversationTurn(role: .user, text: text))
    }

    private func appendAssistant(_ text: String, cards: [ContentCard] = [], suggestions: [String] = []) {
        turns.append(ConversationTurn(role: .assistant, text: text, cards: cards, suggestions: suggestions))
        requestScrollToLatestCards(preferring: cards.last?.id)
    }

    func noteVisibleCardGrew() {
        requestScrollToLatestCards()
    }

    private func requestScrollToLatestCards(preferring id: UUID? = nil) {
        conversationScrollTarget = id ?? turns.last?.cards.last?.id ?? turns.last?.id
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
