import Foundation

/// System events that invalidate a running `AVAudioEngine` mic tap.
///
/// Each of these silently kills capture: the engine keeps reporting a graph,
/// but no buffer ever reaches the tap again. Without an explicit restart the
/// user is simply never heard again for the rest of the session.
public enum AudioLifecycleEvent: Equatable, Sendable {
    /// Phone call, Siri, alarm, another app taking the session.
    case interruptionBegan
    /// `shouldResume` is the system's hint; a voice agent the user switched on
    /// still wants its mic back either way.
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(RouteChangeReason)
    /// `AVAudioEngine.configurationChangeNotification` — the graph was rebuilt
    /// underneath us and every installed tap is now detached.
    case engineConfigurationChanged
    /// The media daemon died. Session, engine, and player must all be recreated.
    case mediaServicesWereReset
    case appBecameActive
    /// The liveness watchdog saw no mic buffers for longer than the stall budget.
    case micFramesStalled
}

public enum RouteChangeReason: String, Equatable, Sendable, CaseIterable {
    case newDeviceAvailable
    case oldDeviceUnavailable
    case categoryChange
    case override
    case wakeFromSleep
    case noSuitableRouteForCategory
    case routeConfigurationChange
    case unknown
}

/// Ordered by severity so callers can coalesce several events into one repair.
public enum MicRecoveryAction: Int, Comparable, Sendable {
    case none = 0
    /// Interruption is active. Stand down and wait — restarting now just fails.
    case suspend = 1
    /// Restart only if capture is not actually delivering audio.
    case verify = 2
    /// Reinstall the tap and restart the engine.
    case restart = 3
    /// Reconfigure the audio session too, not just the engine.
    case rebuild = 4

    public static func < (lhs: MicRecoveryAction, rhs: MicRecoveryAction) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Pure policy for "did we just lose the mic, and how hard do we have to
/// restart it?". Kept free of AVFoundation so it runs in Linux CI.
public struct MicCaptureRecovery: Equatable, Sendable {
    /// The user has voice on. When false every event is a no-op.
    public var wantsCapture: Bool
    public private(set) var isInterrupted: Bool

    public init(wantsCapture: Bool = false, isInterrupted: Bool = false) {
        self.wantsCapture = wantsCapture
        self.isInterrupted = isInterrupted
    }

    public mutating func action(for event: AudioLifecycleEvent) -> MicRecoveryAction {
        switch event {
        case .interruptionBegan:
            isInterrupted = true
            return wantsCapture ? .suspend : .none
        case .interruptionEnded:
            let wasInterrupted = isInterrupted
            isInterrupted = false
            guard wantsCapture else { return .none }
            // The session was deactivated under us, so this is always a real
            // restart — never a cheap verify.
            return wasInterrupted ? .restart : .verify
        case .mediaServicesWereReset:
            isInterrupted = false
            return wantsCapture ? .rebuild : .none
        case .engineConfigurationChanged:
            guard wantsCapture, !isInterrupted else { return .none }
            return .restart
        case .routeChanged(let reason):
            guard wantsCapture, !isInterrupted else { return .none }
            return Self.needsRestart(for: reason) ? .restart : .none
        case .appBecameActive:
            guard wantsCapture, !isInterrupted else { return .none }
            return .verify
        case .micFramesStalled:
            guard wantsCapture, !isInterrupted else { return .none }
            return .restart
        }
    }

    /// `categoryChange` and `override` are usually *our own* session setup
    /// echoing back. Restarting on those loops the engine forever.
    static func needsRestart(for reason: RouteChangeReason) -> Bool {
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .wakeFromSleep, .noSuitableRouteForCategory:
            return true
        case .categoryChange, .override, .routeConfigurationChange, .unknown:
            return false
        }
    }
}

/// Watches that mic buffers are still arriving. An `AVAudioEngine` whose tap
/// was detached keeps reporting `isRunning == true`, so "is the engine up?" is
/// not a usable health check — only buffer arrival is.
public struct MicLivenessMonitor: Equatable, Sendable {
    /// A 4096-frame tap at 24–48 kHz fires every ~85–170 ms. Two seconds of
    /// silence from the tap itself (not silence from the user) is a dead tap.
    public static let defaultStallTimeout: TimeInterval = 2.0
    /// The engine needs a moment to deliver its first buffer after start.
    public static let defaultStartGrace: TimeInterval = 3.0

    public private(set) var startedAt: Date?
    public private(set) var lastFrameAt: Date?

    public init(startedAt: Date? = nil, lastFrameAt: Date? = nil) {
        self.startedAt = startedAt
        self.lastFrameAt = lastFrameAt
    }

    public var isCapturing: Bool { startedAt != nil }

    public mutating func captureStarted(at now: Date = Date()) {
        startedAt = now
        lastFrameAt = nil
    }

    public mutating func captureStopped() {
        startedAt = nil
        lastFrameAt = nil
    }

    public mutating func frameArrived(at now: Date = Date()) {
        lastFrameAt = now
    }

    public func isStalled(
        now: Date = Date(),
        timeout: TimeInterval = defaultStallTimeout,
        startGrace: TimeInterval = defaultStartGrace
    ) -> Bool {
        guard let startedAt else { return false }
        guard let lastFrameAt else {
            // Never delivered a single buffer — the tap never attached.
            return now.timeIntervalSince(startedAt) > startGrace
        }
        return now.timeIntervalSince(lastFrameAt) > timeout
    }
}
