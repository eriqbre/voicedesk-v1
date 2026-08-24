import XCTest
@testable import VoiceDeskLogic

final class FirstListenPolicyTests: XCTestCase {
    func testReadyRequiresSocketAndAudioSession() {
        XCTAssertFalse(FirstListenPolicy.isReady(socketConnected: false, audioSessionReady: false))
        XCTAssertFalse(FirstListenPolicy.isReady(socketConnected: true, audioSessionReady: false))
        XCTAssertFalse(FirstListenPolicy.isReady(socketConnected: false, audioSessionReady: true))
        XCTAssertTrue(FirstListenPolicy.isReady(socketConnected: true, audioSessionReady: true))
    }

    func testFirstTapWaitsWhenNotReadyThenListens() {
        XCTAssertEqual(FirstListenPolicy.beforeListen(isReady: false), .waitForReady)
        XCTAssertEqual(FirstListenPolicy.beforeListen(isReady: true), .listen)
    }

    func testEmptyListenRetriesOnceIfNeverConnectedThisLaunch() {
        XCTAssertEqual(
            FirstListenPolicy.afterEmptyListen(didConnectThisLaunch: false, alreadyRetried: false),
            .retryConnectThenListen
        )
        XCTAssertEqual(
            FirstListenPolicy.afterEmptyListen(didConnectThisLaunch: false, alreadyRetried: true),
            .acceptEmpty
        )
        XCTAssertEqual(
            FirstListenPolicy.afterEmptyListen(didConnectThisLaunch: true, alreadyRetried: false),
            .acceptEmpty
        )
        XCTAssertEqual(
            FirstListenPolicy.afterEmptyListen(didConnectThisLaunch: true, alreadyRetried: true),
            .acceptEmpty
        )
    }
}
