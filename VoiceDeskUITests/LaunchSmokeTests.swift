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
    }

    func testTourRendersRequiredCards() {
        XCTAssertTrue(app.buttons["suggestion.tour"].waitForExistence(timeout: 5))
        app.buttons["suggestion.tour"].tap()

        XCTAssertTrue(element("card.email").waitForExistence(timeout: 12))
        XCTAssertTrue(element("card.listing").exists)
        XCTAssertTrue(element("card.person").exists)
        XCTAssertTrue(element("card.draftConfirm").waitForExistence(timeout: 12))
        XCTAssertTrue(element("card.statute").waitForExistence(timeout: 12))
        XCTAssertTrue(element("card.connectGoogle").waitForExistence(timeout: 12))
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

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }
}
