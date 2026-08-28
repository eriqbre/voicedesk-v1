import Foundation

/// Official rebuilds only: configuration change and media-services reset.
/// TTS drain is not a rebuild. Ignore our own session echo.
/// Not a watchdog and not a TTS rearm.
public enum AudioTapLifecycle: Sendable {
    public enum Event: Equatable, Sendable {
        case interruptionBegan
        case interruptionEnded
        case engineConfigurationChanged
        case mediaServicesWereReset
        case routeCategoryOrOverride
        case routeDeviceChanged
        case appBecameActive
    }

    public enum Action: Equatable, Sendable {
        case none
        /// Same engine. Do not increment startCount.
        case reinstallTap
        /// Media daemon died. Recreate the graph. Do not increment startCount.
        case rebuildGraph
    }

    public static func action(
        for event: Event,
        wantsCapture: Bool,
        isInterrupted: inout Bool
    ) -> Action {
        guard wantsCapture else { return .none }
        switch event {
        case .interruptionBegan:
            isInterrupted = true
            return .none
        case .interruptionEnded:
            isInterrupted = false
            return .none
        case .engineConfigurationChanged:
            return isInterrupted ? .none : .reinstallTap
        case .mediaServicesWereReset:
            isInterrupted = false
            return .rebuildGraph
        case .routeCategoryOrOverride:
            return .none
        case .routeDeviceChanged:
            return .none
        case .appBecameActive:
            if isInterrupted {
                isInterrupted = false
            }
            return .none
        }
    }
}
