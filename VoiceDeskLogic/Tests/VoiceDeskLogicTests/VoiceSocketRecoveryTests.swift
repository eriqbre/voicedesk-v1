import XCTest
@testable import VoiceDeskLogic

final class VoiceSocketRecoveryTests: XCTestCase {
    func testSocketNotConnectedIsADrop() {
        XCTAssertTrue(VoiceSocketRecovery.isSocketDrop("The operation couldn't be completed. Socket is not connected"))
        XCTAssertTrue(VoiceSocketRecovery.isSocketDrop("Grok disconnected"))
        XCTAssertTrue(VoiceSocketRecovery.isSocketDrop("WebSocket timeout"))
        XCTAssertTrue(VoiceSocketRecovery.isSocketDrop("The network connection was lost."))
        XCTAssertFalse(VoiceSocketRecovery.isSocketDrop("Microphone permission denied"))
    }

    func testTransientDropsRetryUpToTheBudget() {
        for used in 0..<VoiceSocketRecovery.maxAutomaticReconnects {
            XCTAssertTrue(
                VoiceSocketRecovery.shouldReconnect(kind: .transient, attemptsUsed: used),
                "attempt \(used) should still retry"
            )
        }
        XCTAssertFalse(
            VoiceSocketRecovery.shouldReconnect(
                kind: .transient,
                attemptsUsed: VoiceSocketRecovery.maxAutomaticReconnects
            )
        )
    }

    /// One retry left a real conversation dead on the second blip.
    func testBudgetSurvivesMoreThanOneBlip() {
        XCTAssertGreaterThan(VoiceSocketRecovery.maxAutomaticReconnects, 1)
    }

    func testUserStopNeverReconnects() {
        XCTAssertFalse(
            VoiceSocketRecovery.shouldReconnect(
                error: "Grok disconnected",
                alreadyTried: false,
                userWantsVoiceOff: true
            )
        )
        XCTAssertFalse(
            VoiceSocketRecovery.shouldReconnect(kind: .transient, attemptsUsed: 0, userWantsVoiceOff: true)
        )
        XCTAssertTrue(
            VoiceSocketRecovery.shouldReconnect(
                error: "Socket is not connected",
                alreadyTried: false,
                userWantsVoiceOff: false
            )
        )
    }

    /// `connect()` disconnects the previous socket first; that old task then
    /// reports "cancelled" after the replacement is already live.
    func testOurOwnDisconnectIsNotAFailure() {
        XCTAssertEqual(
            VoiceSocketRecovery.classify(error: "cancelled"),
            .intentionalCancel
        )
        XCTAssertEqual(
            VoiceSocketRecovery.classify(error: "The operation was canceled."),
            .intentionalCancel
        )
        XCTAssertFalse(
            VoiceSocketRecovery.shouldReconnect(kind: .intentionalCancel, attemptsUsed: 0)
        )
    }

    func testBadCredentialsAreNotRetried() {
        XCTAssertEqual(
            VoiceSocketRecovery.classify(error: "Unauthorized", httpStatus: 401),
            .authentication
        )
        XCTAssertEqual(
            VoiceSocketRecovery.classify(error: "Forbidden", httpStatus: 403),
            .authentication
        )
        XCTAssertFalse(
            VoiceSocketRecovery.shouldReconnect(kind: .authentication, attemptsUsed: 0)
        )
    }

    func testServerAndRateLimitErrorsAreTransient() {
        XCTAssertEqual(VoiceSocketRecovery.classify(error: "Too many requests", httpStatus: 429), .transient)
        XCTAssertEqual(VoiceSocketRecovery.classify(error: "Bad gateway", httpStatus: 502), .transient)
        XCTAssertEqual(VoiceSocketRecovery.classify(error: "Bad request", httpStatus: 400), .fatal)
    }

    func testUnlabelledMidConversationDropsRetry() {
        XCTAssertEqual(VoiceSocketRecovery.classify(error: "something odd happened"), .transient)
    }

    func testBackoffGrowsThenCaps() {
        XCTAssertEqual(VoiceSocketRecovery.reconnectDelay(attemptsUsed: 0), 0)
        XCTAssertEqual(VoiceSocketRecovery.reconnectDelay(attemptsUsed: 1), 0.5)
        XCTAssertEqual(VoiceSocketRecovery.reconnectDelay(attemptsUsed: 2), 1)
        XCTAssertEqual(VoiceSocketRecovery.reconnectDelay(attemptsUsed: 3), 2)
        XCTAssertEqual(VoiceSocketRecovery.reconnectDelay(attemptsUsed: 4), 4)
        XCTAssertEqual(
            VoiceSocketRecovery.reconnectDelay(attemptsUsed: 99),
            VoiceSocketRecovery.maxReconnectDelay
        )
    }
}
