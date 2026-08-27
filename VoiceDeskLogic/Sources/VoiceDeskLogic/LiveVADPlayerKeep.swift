import Foundation

/// c1cd758 vs 83a5c6a: live VAD first-answer PCM must reach the one
/// player for the full reply. Same-turn `interruptResponse` after the
/// first delta cancelled A; deleting the second create left no mouth.
/// Mid-reply `session.update` (prefetch presence) cut the rest and
/// stalled transcripts. Cards must land on the streaming Eve turn.
public struct LiveVADPlayerKeep: Equatable, Sendable {
    public var firstDeltaOnPlayer: Bool
    public var sameTurnInterruptCancelledFirstAnswer: Bool
    public var sentSecondCreate: Bool
    public var presenceUpdateWhileInFlight: Bool
    public var liveTurnCardCount: Int
    public var toolsGateTranscript: Bool

    public init(
        firstDeltaOnPlayer: Bool,
        sameTurnInterruptCancelledFirstAnswer: Bool,
        sentSecondCreate: Bool,
        presenceUpdateWhileInFlight: Bool,
        liveTurnCardCount: Int,
        toolsGateTranscript: Bool
    ) {
        self.firstDeltaOnPlayer = firstDeltaOnPlayer
        self.sameTurnInterruptCancelledFirstAnswer = sameTurnInterruptCancelledFirstAnswer
        self.sentSecondCreate = sentSecondCreate
        self.presenceUpdateWhileInFlight = presenceUpdateWhileInFlight
        self.liveTurnCardCount = liveTurnCardCount
        self.toolsGateTranscript = toolsGateTranscript
    }

    /// Split-second voice then silence. A was latched cancelled; no B.
    public var voiceCutsAfterFirstDelta: Bool {
        firstDeltaOnPlayer && sameTurnInterruptCancelledFirstAnswer && !sentSecondCreate
    }

    public var remainingDeltasReachPlayer: Bool {
        !voiceCutsAfterFirstDelta && !presenceUpdateWhileInFlight
    }

    /// Eve transcript with no cards — show-latest-emails as a blob.
    public var isCardlessBlob: Bool {
        liveTurnCardCount == 0
    }

    public var dumpsTranscriptLate: Bool {
        presenceUpdateWhileInFlight || toolsGateTranscript
    }

    public var isOneMouthFullReply: Bool {
        remainingDeltasReachPlayer
            && !sentSecondCreate
            && !isCardlessBlob
            && !dumpsTranscriptLate
    }

    /// Device hole on c1cd758: first delta played, interrupt cancelled A,
    /// prefetch `session.update` mid-A, glance never attached to the
    /// live turn (yield skipped fulfill / delayed append).
    public static func c1cd758Regression() -> LiveVADPlayerKeep {
        LiveVADPlayerKeep(
            firstDeltaOnPlayer: true,
            sameTurnInterruptCancelledFirstAnswer: true,
            sentSecondCreate: false,
            presenceUpdateWhileInFlight: true,
            liveTurnCardCount: 0,
            toolsGateTranscript: true
        )
    }

    public static func oneMouthFullReply(cardCount: Int) -> LiveVADPlayerKeep {
        LiveVADPlayerKeep(
            firstDeltaOnPlayer: true,
            sameTurnInterruptCancelledFirstAnswer: false,
            sentSecondCreate: false,
            presenceUpdateWhileInFlight: false,
            liveTurnCardCount: cardCount,
            toolsGateTranscript: false
        )
    }

    /// First-answer PCM on the player is this turn's mouth. Do not
    /// latch it cancelled. speech_started already dropped leftover.
    public static func shouldInterruptOnUserTranscript(
        alreadyBarged: Bool,
        hasPendingPlayback: Bool
    ) -> Bool {
        if alreadyBarged { return false }
        if hasPendingPlayback { return false }
        return true
    }

    /// `session.update` while A is in flight cuts PCM and stalls print.
    public static func shouldSendPresenceSessionUpdate(responseInFlight: Bool) -> Bool {
        !responseInFlight
    }

    /// Cards on the first assistant delta — not after glanceInbox.
    public static func shouldAttachCardsOnFirstTranscriptDelta(liveVADTurn: Bool) -> Bool {
        liveVADTurn
    }

    public static func shouldBufferTranscriptUntilToolsFinish() -> Bool {
        false
    }
}
