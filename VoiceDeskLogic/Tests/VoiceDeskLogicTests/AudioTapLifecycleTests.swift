import XCTest
@testable import VoiceDeskLogic

final class AudioTapLifecycleTests: XCTestCase {
    func testOwnSessionEchoDoesNotReinstall() {
        var interrupted = false
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .routeCategoryOrOverride, wantsCapture: true, isInterrupted: &interrupted),
            .none
        )
    }

    func testConfigurationChangeReinstallsTapOnTheSameEngine() {
        var interrupted = false
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .engineConfigurationChanged, wantsCapture: true, isInterrupted: &interrupted),
            .reinstallTap
        )
    }

    func testMediaResetRebuildsGraph() {
        var interrupted = false
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .mediaServicesWereReset, wantsCapture: true, isInterrupted: &interrupted),
            .rebuildGraph
        )
    }

    func testInterruptionBeganLeavesTapDeadWhileRunning() {
        var interrupted = false
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .interruptionBegan, wantsCapture: true, isInterrupted: &interrupted),
            .none
        )
        XCTAssertTrue(interrupted)
    }

    func testInterruptionEndedIsNotARebuild() {
        var interrupted = true
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .interruptionEnded, wantsCapture: true, isInterrupted: &interrupted),
            .none
        )
        XCTAssertFalse(interrupted)
    }

    func testRouteDeviceChangeIsNotARebuild() {
        var interrupted = false
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .routeDeviceChanged, wantsCapture: true, isInterrupted: &interrupted),
            .none
        )
        interrupted = true
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .routeDeviceChanged, wantsCapture: true, isInterrupted: &interrupted),
            .none
        )
        XCTAssertTrue(interrupted)
    }

    func testAppBecameActiveIsNotARebuild() {
        var interrupted = true
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .appBecameActive, wantsCapture: true, isInterrupted: &interrupted),
            .none
        )
        XCTAssertFalse(interrupted)
    }

    func testVoiceOffIsANoOp() {
        var interrupted = false
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .engineConfigurationChanged, wantsCapture: false, isInterrupted: &interrupted),
            .none
        )
    }
}
