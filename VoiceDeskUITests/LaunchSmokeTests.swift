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
        XCTAssertTrue(app.staticTexts["Saturday showing at Beach Drive?"].exists)
        let sample = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'samples'")).firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'live Gmail is connected'")).firstMatch.exists)
    }

    func testSamplePreviewOffersConnectGoogle() {
        XCTAssertTrue(app.buttons["suggestion.tour"].waitForExistence(timeout: 5))
        app.buttons["suggestion.tour"].tap()
        waitForCard("card.email")
        waitForCard("card.connectGoogle")
        XCTAssertTrue(app.buttons["google.connect"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["suggestion.connectGoogle"].waitForExistence(timeout: 5))
        // Matches `ConversationPresence.connectCoach`. The old assertion looked
        // for copy that only ever existed in the README, so it could not pass.
        let coach = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Tap Connect Google on the card below'")).firstMatch
        XCTAssertTrue(coach.waitForExistence(timeout: 5))
    }

    func testDraftConfirmDoesNotFakeSend() {
        XCTAssertTrue(app.buttons["suggestion.draft"].waitForExistence(timeout: 5))
        app.buttons["suggestion.draft"].tap()
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
