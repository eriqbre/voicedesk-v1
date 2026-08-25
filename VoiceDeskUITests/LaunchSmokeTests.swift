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
        let coach = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Connect Google so I can see'")).firstMatch
        XCTAssertTrue(coach.waitForExistence(timeout: 5))
    }

    func testTourEmailCardTapExpandsThenCollapses() {
        XCTAssertTrue(app.buttons["suggestion.tour"].waitForExistence(timeout: 5))
        app.buttons["suggestion.tour"].tap()
        waitForCard("card.email")

        let full = app.descendants(matching: .any)["card.email.full"]
        let compact = app.descendants(matching: .any)["card.email.compact"]
        XCTAssertTrue(full.waitForExistence(timeout: 8), "tour email starts open")
        XCTAssertFalse(compact.exists)

        full.tap()
        XCTAssertTrue(compact.waitForExistence(timeout: 5), "tap open card → compact")
        XCTAssertFalse(full.exists)

        compact.tap()
        XCTAssertTrue(full.waitForExistence(timeout: 5), "tap compact → open")
        XCTAssertFalse(compact.exists)

        full.tap()
        XCTAssertTrue(compact.waitForExistence(timeout: 5), "tap-expanded then tap-again is compact")
        XCTAssertFalse(full.exists)
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
