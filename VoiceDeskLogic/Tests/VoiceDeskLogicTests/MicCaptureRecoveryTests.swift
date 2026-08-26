import XCTest
@testable import VoiceDeskLogic

final class MicCaptureRecoveryTests: XCTestCase {
    private func live() -> MicCaptureRecovery {
        MicCaptureRecovery(wantsCapture: true)
    }

    func testEngineConfigurationChangeRestartsTheTap() {
        var recovery = live()
        XCTAssertEqual(recovery.action(for: .engineConfigurationChanged), .restart)
    }

    func testInterruptionSuspendsThenRestarts() {
        var recovery = live()
        XCTAssertEqual(recovery.action(for: .interruptionBegan), .suspend)
        XCTAssertTrue(recovery.isInterrupted)
        XCTAssertEqual(recovery.action(for: .interruptionEnded(shouldResume: true)), .restart)
        XCTAssertFalse(recovery.isInterrupted)
    }

    /// A voice agent the user explicitly switched on still wants its mic back
    /// even when the system does not volunteer `shouldResume`.
    func testInterruptionEndedWithoutResumeHintStillRestarts() {
        var recovery = live()
        _ = recovery.action(for: .interruptionBegan)
        XCTAssertEqual(recovery.action(for: .interruptionEnded(shouldResume: false)), .restart)
    }

    func testEventsDuringAnInterruptionAreIgnored() {
        var recovery = live()
        _ = recovery.action(for: .interruptionBegan)
        XCTAssertEqual(recovery.action(for: .engineConfigurationChanged), .none)
        XCTAssertEqual(recovery.action(for: .routeChanged(.oldDeviceUnavailable)), .none)
        XCTAssertEqual(recovery.action(for: .micFramesStalled), .none)
        XCTAssertEqual(recovery.action(for: .appBecameActive), .none)
    }

    func testMediaServicesResetRebuildsEverythingEvenMidInterruption() {
        var recovery = live()
        _ = recovery.action(for: .interruptionBegan)
        XCTAssertEqual(recovery.action(for: .mediaServicesWereReset), .rebuild)
        XCTAssertFalse(recovery.isInterrupted)
    }

    func testHeadphoneAndBluetoothChangesRestartCapture() {
        var recovery = live()
        XCTAssertEqual(recovery.action(for: .routeChanged(.oldDeviceUnavailable)), .restart)
        XCTAssertEqual(recovery.action(for: .routeChanged(.newDeviceAvailable)), .restart)
        XCTAssertEqual(recovery.action(for: .routeChanged(.wakeFromSleep)), .restart)
        XCTAssertEqual(recovery.action(for: .routeChanged(.noSuitableRouteForCategory)), .restart)
    }

    /// Our own `setCategory` / `overrideOutputAudioPort` echo back as route
    /// changes. Restarting on those spins the engine in a loop.
    func testOurOwnSessionSetupDoesNotRestartCapture() {
        var recovery = live()
        XCTAssertEqual(recovery.action(for: .routeChanged(.categoryChange)), .none)
        XCTAssertEqual(recovery.action(for: .routeChanged(.override)), .none)
        XCTAssertEqual(recovery.action(for: .routeChanged(.routeConfigurationChange)), .none)
        XCTAssertEqual(recovery.action(for: .routeChanged(.unknown)), .none)
    }

    func testForegroundingOnlyVerifies() {
        var recovery = live()
        XCTAssertEqual(recovery.action(for: .appBecameActive), .verify)
    }

    func testStalledFramesForceARestart() {
        var recovery = live()
        XCTAssertEqual(recovery.action(for: .micFramesStalled), .restart)
    }

    func testVoiceOffMakesEveryEventANoOp() {
        var recovery = MicCaptureRecovery(wantsCapture: false)
        for event: AudioLifecycleEvent in [
            .interruptionBegan,
            .interruptionEnded(shouldResume: true),
            .engineConfigurationChanged,
            .mediaServicesWereReset,
            .appBecameActive,
            .micFramesStalled
        ] + RouteChangeReason.allCases.map({ AudioLifecycleEvent.routeChanged($0) }) {
            XCTAssertEqual(recovery.action(for: event), .none, "\(event)")
        }
    }

    func testActionsAreOrderedBySeverity() {
        XCTAssertTrue(MicRecoveryAction.none < .suspend)
        XCTAssertTrue(MicRecoveryAction.suspend < .verify)
        XCTAssertTrue(MicRecoveryAction.verify < .restart)
        XCTAssertTrue(MicRecoveryAction.restart < .rebuild)
    }
}

final class MicLivenessMonitorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testIdleMonitorIsNeverStalled() {
        let monitor = MicLivenessMonitor()
        XCTAssertFalse(monitor.isCapturing)
        XCTAssertFalse(monitor.isStalled(now: start.addingTimeInterval(600)))
    }

    func testStartGraceCoversTheFirstBuffer() {
        var monitor = MicLivenessMonitor()
        monitor.captureStarted(at: start)
        XCTAssertFalse(monitor.isStalled(now: start.addingTimeInterval(1)))
        XCTAssertFalse(monitor.isStalled(now: start.addingTimeInterval(2.9)))
    }

    /// The tap never attached: engine "running", zero buffers, user unheard.
    func testTapThatNeverDeliversIsStalledAfterTheGrace() {
        var monitor = MicLivenessMonitor()
        monitor.captureStarted(at: start)
        XCTAssertTrue(monitor.isStalled(now: start.addingTimeInterval(3.1)))
    }

    func testFlowingFramesAreHealthy() {
        var monitor = MicLivenessMonitor()
        monitor.captureStarted(at: start)
        monitor.frameArrived(at: start.addingTimeInterval(0.1))
        monitor.frameArrived(at: start.addingTimeInterval(0.2))
        XCTAssertFalse(monitor.isStalled(now: start.addingTimeInterval(1.5)))
    }

    func testFramesThatStopArrivingAreStalled() {
        var monitor = MicLivenessMonitor()
        monitor.captureStarted(at: start)
        monitor.frameArrived(at: start.addingTimeInterval(5))
        XCTAssertFalse(monitor.isStalled(now: start.addingTimeInterval(6.9)))
        XCTAssertTrue(monitor.isStalled(now: start.addingTimeInterval(7.1)))
    }

    func testStoppingClearsLiveness() {
        var monitor = MicLivenessMonitor()
        monitor.captureStarted(at: start)
        monitor.frameArrived(at: start)
        monitor.captureStopped()
        XCTAssertFalse(monitor.isCapturing)
        XCTAssertFalse(monitor.isStalled(now: start.addingTimeInterval(600)))
    }

    func testRestartClearsTheStaleFrameTimestamp() {
        var monitor = MicLivenessMonitor()
        monitor.captureStarted(at: start)
        monitor.frameArrived(at: start.addingTimeInterval(1))
        monitor.captureStarted(at: start.addingTimeInterval(100))
        XCTAssertNil(monitor.lastFrameAt)
        XCTAssertFalse(monitor.isStalled(now: start.addingTimeInterval(101)))
        XCTAssertTrue(monitor.isStalled(now: start.addingTimeInterval(104)))
    }
}
