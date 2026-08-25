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
        let coach = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Tap Connect Google'")).firstMatch
        XCTAssertTrue(coach.waitForExistence(timeout: 5))
    }

    func testTourEmailCardTapExpandsThenCollapses() {
        XCTAssertTrue(app.buttons["suggestion.tour"].waitForExistence(timeout: 5))
        app.buttons["suggestion.tour"].tap()
        waitForCard("card.email")

        let card = app.descendants(matching: .any)["card.email"]
        XCTAssertTrue(card.waitForExistence(timeout: 2))

        // Same control. Tour wrapper id is `card.email` (inner `.full` / `.compact` is not
        // in the XCUITest tree). Start from whatever state the tour actually shows.
        if emailCardIsCompact() {
            card.tap()
            XCTAssertTrue(waitForEmailCardState("full"), "tap compact → open")
        }
        XCTAssertTrue(emailCardIsFull(), "need an open card before the collapse proof")

        card.tap()
        XCTAssertTrue(waitForEmailCardState("compact"), "tap open card → compact")

        card.tap()
        XCTAssertTrue(waitForEmailCardState("full"), "tap compact → open")

        card.tap()
        XCTAssertTrue(waitForEmailCardState("compact"), "tap-expanded then tap-again is compact")
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

    private func emailCardIsCompact() -> Bool {
        emailCardState() == "compact"
    }

    private func emailCardIsFull() -> Bool {
        emailCardState() == "full"
    }

    /// Presentation on the `card.email` node XCUITest actually exposes.
    private func emailCardState() -> String? {
        if app.descendants(matching: .any)["card.email.compact"].exists { return "compact" }
        if app.descendants(matching: .any)["card.email.full"].exists { return "full" }
        let card = app.descendants(matching: .any)["card.email"]
        guard card.exists else { return nil }
        let blobs = [card.value as? String, card.label].compactMap { $0 }.joined(separator: " ")
        if blobs == "compact" || blobs.hasPrefix("compact") || blobs.contains("Opens the full email") {
            return "compact"
        }
        if blobs == "full" || blobs.hasPrefix("full") || blobs.contains("Collapses the email") {
            return "full"
        }
        return nil
    }

    private func waitForEmailCardState(_ expected: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if emailCardState() == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return emailCardState() == expected
    }
}
