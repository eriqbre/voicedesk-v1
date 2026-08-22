import XCTest

final class LaunchSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testColdLaunchShowsConversationAndTalk() {
        XCTAssertTrue(app.navigationBars["VoiceDesk"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["suggestion.tour"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["voice.talk"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["voice.coach"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["voice.setup"].exists)
    }

    func testTourRendersRequiredCards() {
        XCTAssertTrue(app.buttons["suggestion.tour"].waitForExistence(timeout: 5))
        app.buttons["suggestion.tour"].tap()

        waitForCard("card.email")
        waitForCard("card.listing")
        waitForCard("card.person")
        waitForCard("card.draftConfirm")
        waitForCard("card.statute")
        waitForCard("card.connectGoogle")
        XCTAssertTrue(app.staticTexts["Saturday showing at Beach Drive?"].exists)
        XCTAssertTrue(app.staticTexts["86%"].exists)
        XCTAssertTrue(app.staticTexts["Firm"].exists)
    }

    func testDraftConfirmDoesNotFakeSend() {
        XCTAssertTrue(app.buttons["suggestion.tour"].waitForExistence(timeout: 5))
        app.buttons["suggestion.tour"].tap()
        XCTAssertTrue(app.buttons["draft.confirm"].waitForExistence(timeout: 10))
        app.buttons["draft.confirm"].tap()
        let notSent = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Not sent'")).firstMatch
        XCTAssertTrue(notSent.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Delivered."].exists)
    }

    private func waitForCard(_ id: String) {
        let node = app.descendants(matching: .any)[id]
        if node.waitForExistence(timeout: 8) { return }
        for _ in 0..<5 {
            app.swipeUp()
            if node.waitForExistence(timeout: 2) { return }
        }
        XCTAssertTrue(node.waitForExistence(timeout: 2), "Missing \(id)")
    }
}
