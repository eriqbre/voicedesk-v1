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
    }

    /// A suspended app can miss `.ended` entirely. Without this the session
    /// stays flagged as interrupted and the mic never comes back at all.
    func testForegroundingRecoversFromAMissedInterruptionEnd() {
        var recovery = live()
        _ = recovery.action(for: .interruptionBegan)
        XCTAssertEqual(recovery.action(for: .appBecameActive), .restart)
        XCTAssertFalse(recovery.isInterrupted)
        XCTAssertEqual(recovery.action(for: .micFramesStalled), .restart)
    }

    /// The whole point of the type, walked end to end.
    func testCallThenHeadphonesThenForegroundAllLeaveTheMicLive() {
        var recovery = live()
        XCTAssertEqual(recovery.action(for: .interruptionBegan), .suspend)
        XCTAssertEqual(recovery.action(for: .interruptionEnded(shouldResume: true)), .restart)
        XCTAssertEqual(recovery.action(for: .routeChanged(.oldDeviceUnavailable)), .restart)
        XCTAssertEqual(recovery.action(for: .engineConfigurationChanged), .restart)
        XCTAssertEqual(recovery.action(for: .appBecameActive), .verify)
        XCTAssertFalse(recovery.isInterrupted)
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

    func testTurningVoiceBackOnResumesRepairs() {
        var recovery = MicCaptureRecovery(wantsCapture: false)
        XCTAssertEqual(recovery.action(for: .engineConfigurationChanged), .none)
        recovery.wantsCapture = true
        XCTAssertEqual(recovery.action(for: .engineConfigurationChanged), .restart)
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

final class MicRepairBackoffTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 3_000)

    func testFirstRepairIsImmediate() {
        XCTAssertTrue(
            MicRepairBackoff.shouldRepair(now: now, lastRepairAt: nil, consecutiveRepairs: 0)
        )
    }

    func testRepeatedRepairsAreThrottled() {
        XCTAssertFalse(
            MicRepairBackoff.shouldRepair(
                now: now.addingTimeInterval(1),
                lastRepairAt: now,
                consecutiveRepairs: 1
            )
        )
        XCTAssertTrue(
            MicRepairBackoff.shouldRepair(
                now: now.addingTimeInterval(2.5),
                lastRepairAt: now,
                consecutiveRepairs: 1
            )
        )
    }

    func testBackoffGrowsThenCaps() {
        XCTAssertEqual(MicRepairBackoff.interval(consecutiveRepairs: 0), 2)
        XCTAssertEqual(MicRepairBackoff.interval(consecutiveRepairs: 1), 2)
        XCTAssertEqual(MicRepairBackoff.interval(consecutiveRepairs: 2), 4)
        XCTAssertEqual(MicRepairBackoff.interval(consecutiveRepairs: 3), 8)
        XCTAssertEqual(MicRepairBackoff.interval(consecutiveRepairs: 99), MicRepairBackoff.maxInterval)
    }

    /// A media-services reset is rare and unrecoverable without a rebuild.
    func testForcedRepairsSkipTheThrottle() {
        XCTAssertTrue(
            MicRepairBackoff.shouldRepair(
                now: now,
                lastRepairAt: now,
                consecutiveRepairs: 20,
                forced: true
            )
        )
    }

    /// Backing off is not the same as giving up.
    func testThrottleNeverBecomesPermanent() {
        XCTAssertTrue(
            MicRepairBackoff.shouldRepair(
                now: now.addingTimeInterval(MicRepairBackoff.maxInterval),
                lastRepairAt: now,
                consecutiveRepairs: 500
            )
        )
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
