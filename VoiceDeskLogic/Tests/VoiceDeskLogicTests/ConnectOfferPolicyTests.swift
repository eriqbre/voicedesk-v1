import XCTest
@testable import VoiceDeskLogic

final class ConnectOfferPolicyTests: XCTestCase {
    func testFirstOfferAfterPlaybookOnce() {
        XCTAssertTrue(
            ConnectOfferPolicy.shouldShowFirstConnectOffer(
                playbookCompleted: true,
                hasSeenOffer: false,
                isConnected: false
            )
        )
        XCTAssertFalse(
            ConnectOfferPolicy.shouldShowFirstConnectOffer(
                playbookCompleted: false,
                hasSeenOffer: false,
                isConnected: false
            )
        )
        XCTAssertFalse(
            ConnectOfferPolicy.shouldShowFirstConnectOffer(
                playbookCompleted: true,
                hasSeenOffer: true,
                isConnected: false
            )
        )
        XCTAssertFalse(
            ConnectOfferPolicy.shouldShowFirstConnectOffer(
                playbookCompleted: true,
                hasSeenOffer: false,
                isConnected: true
            )
        )
    }

    func testReturningSoftPromptIsNotANagWall() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(
            ConnectOfferPolicy.shouldSoftPrompt(isConnected: false, lastSoftPromptAt: nil, now: now)
        )
        XCTAssertFalse(
            ConnectOfferPolicy.shouldSoftPrompt(
                isConnected: false,
                lastSoftPromptAt: now.addingTimeInterval(-3_600),
                now: now
            )
        )
        XCTAssertTrue(
            ConnectOfferPolicy.shouldSoftPrompt(
                isConnected: false,
                lastSoftPromptAt: now.addingTimeInterval(-ConnectOfferPolicy.softPromptCooldown),
                now: now
            )
        )
        XCTAssertFalse(
            ConnectOfferPolicy.shouldSoftPrompt(isConnected: true, lastSoftPromptAt: nil, now: now)
        )
    }
}
