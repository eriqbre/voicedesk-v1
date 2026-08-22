import XCTest
@testable import VoiceDeskLogic

/// Linux-runnable UI fixture catalog. Simulator XCUITest covers launch on macOS CI.
final class UIFixtureTests: XCTestCase {
    func testConversationMountFixture() {
        var document = ConversationDocument()
        document.appendAssistant(
            "Hi — I’m VoiceDesk. Talk whenever you’re ready. Want a 30-second tour of how this works?",
            suggestions: ["Start the tour"]
        )
        XCTAssertEqual(document.turns.count, 1)
        XCTAssertEqual(document.turns[0].role, .assistant)
        XCTAssertTrue(document.turns[0].suggestions.contains("Start the tour"))
    }

    func testEachCardTypeHasConfirmOrPrimaryAffordance() {
        let draft = SampleData.draftReply()
        XCTAssertEqual(draft.status, .pending)
        XCTAssertEqual(draft.actionTitle, "Send reply")

        let connect = SampleData.connectGoogle()
        XCTAssertFalse(connect.isConnected)
        XCTAssertEqual(connect.headline, "Connect Google")
    }

    func testConfirmButtonCopyDoesNotClaimSent() {
        XCTAssertFalse(SampleData.draftReply().actionTitle.lowercased().contains("sent"))
    }

    func testStatuteFixtureExposesConfidenceMeterBinding() {
        let statute = SampleData.statute()
        let ui = ConfidencePresentation(statute: statute)
        XCTAssertEqual(ui.percent, 86)
        XCTAssertEqual(ui.tone, "Firm")
        XCTAssertTrue(ui.citationVisible)
    }
}
