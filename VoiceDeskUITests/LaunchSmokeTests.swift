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
        XCTAssertTrue(app.buttons["suggestion.Start the tour"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["voice.talk"].exists)
    }

    func testTourRendersRequiredCards() {
        XCTAssertTrue(app.buttons["suggestion.Start the tour"].waitForExistence(timeout: 5))
        app.buttons["suggestion.Start the tour"].tap()

        XCTAssertTrue(app.otherElements["card.email"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["card.listing"].exists)
        XCTAssertTrue(app.otherElements["card.person"].exists)
        XCTAssertTrue(app.otherElements["card.draftConfirm"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["card.statute"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["card.connectGoogle"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["86%"].exists)
        XCTAssertTrue(app.staticTexts["Firm"].exists)
    }

    func testDraftConfirmDoesNotFakeSend() {
        XCTAssertTrue(app.buttons["suggestion.Start the tour"].waitForExistence(timeout: 5))
        app.buttons["suggestion.Start the tour"].tap()
        XCTAssertTrue(app.buttons["draft.confirm"].waitForExistence(timeout: 10))
        app.buttons["draft.confirm"].tap()
        let notSent = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Not sent'")).firstMatch
        XCTAssertTrue(notSent.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Delivered."].exists)
    }
}
