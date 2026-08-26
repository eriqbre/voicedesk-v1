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

    func testVoiceOffIsANoOp() {
        var interrupted = false
        XCTAssertEqual(
            AudioTapLifecycle.action(for: .engineConfigurationChanged, wantsCapture: false, isInterrupted: &interrupted),
            .none
        )
    }
}
