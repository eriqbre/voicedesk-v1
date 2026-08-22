import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

@MainActor
final class AppModelTests: XCTestCase {
    func testColdLaunchMountsConversation() {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        XCTAssertEqual(model.phase, .welcome)
        XCTAssertEqual(model.turns.first?.role, .assistant)
        XCTAssertEqual(model.turns.first?.text, ConversationPresence.firstRunWelcome)
        XCTAssertEqual(model.turns.first?.suggestions, ConversationPresence.starterChips)
        XCTAssertTrue(model.showsTalkCoach)
        XCTAssertTrue(model.turns.first?.cards.isEmpty == true)
        XCTAssertTrue(model.sendClient.sentDrafts.isEmpty)
    }

    func testGeneralChatDoesNotForceCards() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn("What's for dinner?")
        XCTAssertTrue(model.turns.flatMap(\.cards).isEmpty)
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("i can demo"))
    }

    func testDeskPreviewInsertsSampleEmailAndListing() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn(ConversationPresence.deskPreview)
        let kinds = model.turns.flatMap(\.cards).map(\.kind)
        XCTAssertEqual(Array(kinds.prefix(2)), [.email, .listing])
        XCTAssertTrue(kinds.contains(.connectGoogle))
        XCTAssertTrue(model.turns.contains { $0.text == ConversationPresence.deskPreviewReply })
        XCTAssertTrue(model.turns.contains { $0.text == ConversationPresence.connectCoach })
        XCTAssertEqual(model.phase, .ready)
    }

    func testTourInsertsRequiredCards() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn("give me a tour")
        let kinds = Set(model.turns.flatMap(\.cards).map(\.kind))
        for kind in TourScript.requiredKinds {
            XCTAssertTrue(kinds.contains(kind), "missing \(kind.rawValue)")
        }
        XCTAssertEqual(model.phase, .ready)
    }

    func testConfirmQueuesSendAndDoesNotMarkDelivered() async {
        let send = RecordingSendClient()
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            sendClient: send
        )
        await model.applyUserTurn("Draft a reply to Jordan")
        let draft = model.turns.flatMap(\.cards).compactMap { card -> DraftConfirmItem? in
            if case .draftConfirm(let item) = card { return item }
            return nil
        }.first
        XCTAssertNotNil(draft)
        XCTAssertTrue(send.sentDrafts.isEmpty)

        model.confirmDraft(draft!.id)
        XCTAssertEqual(send.sentDrafts.count, 1)
        XCTAssertTrue(model.activity.contains { $0.outcome.contains("Not sent") })
        XCTAssertFalse(model.activity.contains { $0.outcome == "Delivered." })
    }

    func testCancelDoesNotCallSendClient() async {
        let send = RecordingSendClient()
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            sendClient: send
        )
        await model.applyUserTurn("Draft a reply to Jordan")
        let draft = model.turns.flatMap(\.cards).compactMap { card -> DraftConfirmItem? in
            if case .draftConfirm(let item) = card { return item }
            return nil
        }.first
        model.cancelDraft(draft!.id)
        XCTAssertTrue(send.sentDrafts.isEmpty)
    }

    func testUnconfiguredTalkDoesNotFakeAConversation() async {
        let model = AppModel(voice: UnconfiguredVoiceService())
        XCTAssertTrue(model.voice.needsCredentials)
        XCTAssertFalse(model.voice.usesLiveLoop)
        model.tapTalk()
        await Task.yield()
        XCTAssertTrue(model.showVoiceSetup)
        XCTAssertEqual(model.turns.count, 1)
        XCTAssertEqual(model.turns.first?.text, ConversationPresence.firstRunWelcome)
        XCTAssertEqual(model.voice.state, .idle)
    }

    func testLiveTranscriptsMirrorIntoTheThreadAndAttachDeskCards() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(voice: fake)
        model.tapTalk()
        await waitUntil { fake.started }
        XCTAssertTrue(model.voice.usesLiveLoop)

        fake.emitUser("What’s in my inbox?", itemID: "item_1")
        fake.emitUser("What’s in my inbox?", itemID: "item_1")
        fake.emitUser("What’s in my inbox?", itemID: "item_echo")
        fake.emitAssistant("Jordan wrote this morning about Saturday.", isFinal: false)
        fake.emitAssistant("", isFinal: true)

        XCTAssertEqual(model.turns.map(\.role), [.assistant, .user, .assistant])
        XCTAssertEqual(model.turns.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(model.turns[1].text, "What’s in my inbox?")
        XCTAssertTrue(model.turns[2].text.contains("Jordan wrote"))
        XCTAssertTrue(model.turns[2].cards.contains { $0.kind == .connectGoogle })
        XCTAssertFalse(model.turns[2].cards.contains { $0.kind == .email })
    }

    func testLiveHowToConnectGoogleAttachesCardOnUserTranscript() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(voice: fake)
        model.tapTalk()
        await waitUntil { fake.started }

        fake.emitUser("how do I connect my Google account?", itemID: "connect_1")

        XCTAssertEqual(model.turns.filter { $0.role == .user }.last?.text, "how do I connect my Google account?")
        let assistant = model.turns.last
        XCTAssertEqual(assistant?.role, .assistant)
        XCTAssertEqual(assistant?.text, ConversationPresence.connectHowToReply)
        XCTAssertTrue(assistant?.cards.contains { $0.kind == .connectGoogle } == true)
        XCTAssertFalse((assistant?.text ?? "").lowercased().contains("settings"))
        XCTAssertFalse((assistant?.text ?? "").contains("Integrations"))
    }

    func testTypedTurnOnLiveServiceGoesToGrokNotLocalPlan() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(voice: fake)
        await model.applyUserTurn("What's for dinner?")
        XCTAssertEqual(fake.sentTurns, ["What's for dinner?"])
        XCTAssertEqual(model.turns.last?.role, .user)
        XCTAssertEqual(model.turns.filter { $0.role == .user }.count, 1)
        XCTAssertTrue(model.turns.flatMap(\.cards).isEmpty)

        fake.emitUser("What's for dinner?", itemID: "typed_echo")
        XCTAssertEqual(model.turns.filter { $0.role == .user }.count, 1)
    }

    func testReturningLaunchSkipsPlaybookChips() {
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            playbook: InMemoryPlaybookStore(completed: true, lastConnectSoftPromptAt: Date())
        )
        XCTAssertEqual(model.turns.first?.text, ConversationPresence.returningWelcome)
        XCTAssertTrue(model.turns.first?.suggestions.isEmpty == true)
        XCTAssertFalse(model.showsTalkCoach)
    }

    func testReturningLaunchSoftPromptsConnectOnce() {
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            playbook: InMemoryPlaybookStore(completed: true)
        )
        XCTAssertEqual(model.turns.first?.suggestions, [ConversationPresence.connectGoogleChip])
        XCTAssertNotNil(model.playbook.lastConnectSoftPromptAt)
    }

    func testJustTalkChipPointsAtTalkWithoutTour() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn(ConversationPresence.justTalk)
        XCTAssertTrue(model.hasCompletedPlaybook)
        XCTAssertTrue(model.turns.contains { $0.text == ConversationPresence.justTalkReply })
        XCTAssertTrue(model.turns.contains { $0.text == ConversationPresence.connectCoach })
    }

    func testLiveCancelStopsSessionWithoutFakeUtterance() async {
        let fake = FakeLiveVoiceService()
        let model = AppModel(voice: fake)
        model.tapTalk()
        await waitUntil { fake.started }
        model.tapTalk()
        XCTAssertTrue(fake.cancelled)
        XCTAssertEqual(model.turns.count, 1)
        XCTAssertEqual(model.voice.state, .idle)
    }

    func testClientSecretExtraction() {
        XCTAssertEqual(
            LiveGrokVoiceClient.extractClientSecret(from: ["value": "tok_1"]),
            "tok_1"
        )
        XCTAssertEqual(
            LiveGrokVoiceClient.extractClientSecret(from: ["client_secret": "tok_2"]),
            "tok_2"
        )
        XCTAssertEqual(
            LiveGrokVoiceClient.extractClientSecret(from: ["client_secret": ["value": "tok_3"]]),
            "tok_3"
        )
        XCTAssertNil(LiveGrokVoiceClient.extractClientSecret(from: [:]))
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<40 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out waiting for voice service")
    }
}

@MainActor
final class FakeLiveVoiceService: VoiceServicing {
    private var session = VoiceSession()
    let backendLabel = "Fake live"
    let isInstant = true
    let needsCredentials = false
    let usesLiveLoop = true
    var eventHandler: ((VoiceServiceEvent) -> Void)?
    var started = false
    var cancelled = false
    var sentTurns: [String] = []

    var state: VoiceState { session.state }

    func startListening() async -> String {
        started = true
        session.apply(.cancel)
        session.apply(.tapTalk)
        eventHandler?(.state(session.state))
        return ""
    }

    func speak(_ text: String) async {
        _ = text
    }

    func sendTextTurn(_ text: String) async {
        sentTurns.append(text)
    }

    func cancel() {
        cancelled = true
        session.apply(.cancel)
        eventHandler?(.state(session.state))
    }

    func emitUser(_ text: String, itemID: String? = nil) {
        eventHandler?(.userTranscript(text, isFinal: true, itemID: itemID))
    }

    func emitAssistant(_ text: String, isFinal: Bool) {
        eventHandler?(.assistantTranscript(text, isFinal: isFinal))
    }

    func updatePresenceInstructions(_ text: String) {
        _ = text
    }
}

@MainActor
final class GoogleSliceTests: XCTestCase {
    func testMissingClientIDDoesNotFakeConnected() async {
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .missingClientID()
        )
        await model.connectGoogle()
        XCTAssertFalse(model.google.isConnected)
        XCTAssertTrue(model.google.setupNeeded)
        XCTAssertTrue((model.turns.last?.text ?? "").contains("GOOGLE_CLIENT_ID"))
        XCTAssertTrue(model.activity.contains { $0.outcome.contains("Not connected") })
    }

    func testConnectSyncsRealCardsNotSampleDesk() async {
        let cache = MemoryDeskCache()
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(),
            cache: cache,
            sync: MockGoogleSync(result: DeskSnapshot(emails: [SampleData.syncedEmail()]))
        )
        await model.connectGoogle()
        XCTAssertTrue(model.google.isConnected)
        XCTAssertEqual(model.deskSnapshot.emails.first?.subject, "Inspection questions")
        XCTAssertEqual(cache.load().emails.first?.fromName, "Ada Cole")

        await model.applyUserTurn("What's in my inbox?")
        let emails = model.turns.flatMap(\.cards).compactMap { card -> EmailItem? in
            if case .email(let item) = card { return item }
            return nil
        }
        XCTAssertEqual(emails.first?.subject, "Inspection questions")
        XCTAssertFalse(emails.contains { $0.fromName.contains("Jordan") })
    }

    func testSignOutClearsCachedMail() async {
        let cache = MemoryDeskCache()
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(),
            cache: cache,
            sync: MockGoogleSync()
        )
        await model.connectGoogle()
        XCTAssertFalse(cache.load().emails.isEmpty)
        model.disconnectGoogle()
        XCTAssertFalse(model.google.isConnected)
        XCTAssertTrue(model.deskSnapshot.emails.isEmpty)
        XCTAssertTrue(cache.load().emails.isEmpty)
        XCTAssertTrue(model.activity.contains { $0.outcome.contains("Signed out") })
    }

    func testOfflineConfirmQueuesAndDoesNotClaimDelivered() async {
        let send = RecordingSendClient(isOnline: false)
        let model = AppModel(
            voice: MockVoiceService(label: "test", instant: true),
            google: .mock(connected: true),
            sendClient: send,
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [SampleData.syncedEmail()])),
            isOnline: false
        )
        await model.applyUserTurn("Draft a reply to Jordan")
        let draft = model.turns.flatMap(\.cards).compactMap { card -> DraftConfirmItem? in
            if case .draftConfirm(let item) = card { return item }
            return nil
        }.first
        XCTAssertNotNil(draft)
        XCTAssertTrue(draft!.toLine.contains("ada.cole@example.com"))
        model.confirmDraft(draft!.id)
        XCTAssertEqual(send.sentDrafts.count, 1)
        XCTAssertTrue(model.activity.contains { $0.outcome.contains("Queued") })
        XCTAssertFalse(model.activity.contains { $0.outcome == "Delivered." })
    }

    func testInboxAskWhenDisconnectedOffersConnectNotSampleMail() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn("What's in my inbox?")
        let kinds = model.turns.flatMap(\.cards).map(\.kind)
        XCTAssertTrue(kinds.contains(.connectGoogle))
        XCTAssertFalse(kinds.contains(.email))
    }

    func testConnectTimesOutInsteadOfHanging() async {
        let google = GoogleSession(backend: HangingGoogleAuthBackend(), clientIDConfigured: true)
        await google.connect(timeoutSeconds: 0.15)
        XCTAssertFalse(google.isConnected)
        XCTAssertEqual(google.snapshot.state, .failed)
        XCTAssertTrue((google.snapshot.message ?? "").contains("timed out"))
    }
}

@MainActor
final class HangingGoogleAuthBackend: GoogleAuthBackend {
    func signIn() async throws -> (email: String, token: String) {
        try await Task.sleep(for: .seconds(30))
        return ("ada@example.com", "token")
    }

    func signOut() {}

    func restore() async -> (email: String, token: String)? { nil }

    func handleURL(_ url: URL) -> Bool { false }
}
