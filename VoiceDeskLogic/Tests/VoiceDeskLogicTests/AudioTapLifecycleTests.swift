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

    func testInterruptionEndedReinstallsSameEngineTap() {
        var interrupted = true
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .interruptionEnded, wantsCapture: true, isInterrupted: &interrupted),
            .reinstallTap
        )
        XCTAssertFalse(interrupted)
    }

    func testRouteDeviceChangeReinstallsUnlessInterrupted() {
        var interrupted = false
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .routeDeviceChanged, wantsCapture: true, isInterrupted: &interrupted),
            .reinstallTap
        )
        interrupted = true
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .routeDeviceChanged, wantsCapture: true, isInterrupted: &interrupted),
            .none
        )
    }

    func testVoiceOffIsANoOp() {
        var interrupted = false
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .engineConfigurationChanged, wantsCapture: false, isInterrupted: &interrupted),
            .none
        )
    }
}
