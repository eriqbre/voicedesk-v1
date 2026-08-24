import Foundation

public enum FirstListenDecision: Equatable, Sendable {
    /// Socket / audio session is not up — wait, then listen. Do not go idle.
    case waitForReady
    /// Live session can hear. Start (or keep) listening.
    case listen
    /// First listen produced nothing and this launch never connected — retry once.
    case retryConnectThenListen
    /// Empty listen after a connect or after the one allowed retry.
    case acceptEmpty
}

/// First tap-to-talk after a cold launch must not drop the utterance because
/// Grok WS / AVAudioSession were not ready. Pure so Linux tests can run it.
public enum FirstListenPolicy: Sendable {
    public static func isReady(socketConnected: Bool, audioSessionReady: Bool) -> Bool {
        socketConnected && audioSessionReady
    }

    public static func beforeListen(isReady: Bool) -> FirstListenDecision {
        isReady ? .listen : .waitForReady
    }

    /// After a listen attempt that produced no transcript.
    /// Retry once only if this launch never got a live connection.
    public static func afterEmptyListen(
        didConnectThisLaunch: Bool,
        alreadyRetried: Bool
    ) -> FirstListenDecision {
        if !didConnectThisLaunch && !alreadyRetried {
            return .retryConnectThenListen
        }
        return .acceptEmpty
    }
}
