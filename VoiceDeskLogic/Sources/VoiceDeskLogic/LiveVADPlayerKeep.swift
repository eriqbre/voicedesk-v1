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

    /// First-answer leftover is `alreadyBarged` (speech_started).
    /// Version ask is not a barge — Eve finishes.
    /// Next accepted command with PCM on the player drops playback.
    /// Ambient never reaches this — `shouldTakeLiveTurn` already filtered it.
    public static func shouldInterruptOnUserTranscript(
        alreadyBarged: Bool,
        hasPendingPlayback: Bool,
        ask: String = ""
    ) -> Bool {
        if alreadyBarged { return false }
        if !hasPendingPlayback { return false }
        if ConversationPresence.wantsVersionAsk(ask) { return false }
        return true
    }

    /// `session.update` while A is in flight cuts PCM and stalls print.
    public static func shouldSendPresenceSessionUpdate(responseInFlight: Bool) -> Bool {
        !responseInFlight
    }

    /// c1cd758 walk: `eve speaks identity` + empty assistantReply.
    /// 83a5c6a spoke the identity line via write→player.
    public static func isEmptyEveSpeaksIdentityLie(
        routingNotes: [String],
        assistantReply: String,
        wrotePlayerPCM: Bool
    ) -> Bool {
        let notes = routingNotes.joined(separator: " ").lowercased()
        guard notes.contains("eve speaks identity") else { return false }
        return assistantReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !wrotePlayerPCM
    }

    /// Production `GrokVoiceService.shouldPlayBargeAudio` body.
    /// Barge-only. Mute flags (`dropAssistantOutput` /
    /// `clientTTSInFlight`) hid Eve and stuck (8927c2d silence).
    public static func shouldPlayBargeAudio(
        bargeConsumed: Bool,
        deltaResponseID: String?,
        cancelledResponseID: String?,
        createdAwaitingAudioID: String?,
        lastCreatedResponseID: String?,
        playingResponseID: String?,
        lastScheduledResponseID: String?,
        hasPendingPlayback: Bool
    ) -> Bool {
        let answerID = GrokRealtime.interruptAnswerID(
            createdAwaitingAudioID: createdAwaitingAudioID,
            lastCreatedResponseID: lastCreatedResponseID,
            cancelledResponseID: cancelledResponseID
        )
        return GrokRealtime.shouldScheduleAfterBarge(
            bargeConsumed: bargeConsumed,
            deltaResponseID: deltaResponseID,
            cancelledResponseID: cancelledResponseID,
            interruptAnswerID: answerID,
            playingResponseID: playingResponseID,
            lastScheduledResponseID: lastScheduledResponseID,
            hasPendingPlayback: hasPendingPlayback
        )
    }

    /// Live Talk: Eve is the mouth. Desk PCM on a live VAD turn is
    /// the second mouth (a2727b1). Inbox stubs stay silent.
    public static func shouldWriteLiveDeskLineToPlayer(
        liveVADTurn: Bool,
        spoken: String,
        identityLine: String
    ) -> Bool {
        if liveVADTurn { return false }
        let line = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        return !line.isEmpty && !identityLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
