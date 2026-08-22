import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

@MainActor
final class AppModelTests: XCTestCase {
    func testColdLaunchMountsConversation() {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        XCTAssertEqual(model.phase, .welcome)
        XCTAssertEqual(model.turns.first?.role, .assistant)
        XCTAssertEqual(model.turns.first?.text, ConversationPresence.welcomeText)
        XCTAssertTrue(model.turns.first?.suggestions.contains(ConversationPresence.tourOffer) == true)
        XCTAssertTrue(model.turns.first?.cards.isEmpty == true)
        XCTAssertTrue(model.sendClient.sentDrafts.isEmpty)
    }

    func testGeneralChatDoesNotForceCards() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn("What's for dinner?")
        XCTAssertTrue(model.turns.flatMap(\.cards).isEmpty)
        XCTAssertFalse((model.turns.last?.text ?? "").lowercased().contains("i can demo"))
    }

    func testTourInsertsRequiredCards() async {
        let model = AppModel(voice: MockVoiceService(label: "test", instant: true))
        await model.applyUserTurn(ConversationPresence.tourOffer)
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
}
