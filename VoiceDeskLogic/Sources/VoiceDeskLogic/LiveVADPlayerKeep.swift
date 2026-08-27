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
    /// Version identity write is the exception: desk is the mouth,
    /// so drop Eve or ask 1 is two voices.
    public static func shouldInterruptOnUserTranscript(
        alreadyBarged: Bool,
        hasPendingPlayback: Bool,
        deskWritesIdentity: Bool = false
    ) -> Bool {
        if alreadyBarged { return false }
        if deskWritesIdentity { return true }
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

    /// a2727b1: claimLocal set `dropAssistantTranscript` only.
    /// Eve `output_audio.delta` still hit the player while
    /// `speak()` wrote identity. Two mouths. Suppress and the
    /// identity write must both mute Eve PCM during the write.
    /// After drain, `returnToListenAfterDeskTTS` clears both flags.
    /// 8927c2d leftover cleared `clientTTSInFlight` only — drop
    /// stayed true and later Eve was silent.
    public static func shouldPlayEveAudio(
        dropAssistantOutput: Bool,
        clientTTSInFlight: Bool
    ) -> Bool {
        !dropAssistantOutput && !clientTTSInFlight
    }

    /// Production `GrokVoiceService.shouldPlayBargeAudio` body.
    /// a2727b1 leftover was `shouldScheduleAfterBarge` only — Eve
    /// still played after identity write. The Eve mute is this
    /// `shouldPlayEveAudio` guard. Wrapper only increments reject count.
    public static func shouldPlayBargeAudio(
        dropAssistantOutput: Bool,
        clientTTSInFlight: Bool,
        bargeConsumed: Bool,
        deltaResponseID: String?,
        cancelledResponseID: String?,
        createdAwaitingAudioID: String?,
        lastCreatedResponseID: String?,
        playingResponseID: String?,
        lastScheduledResponseID: String?,
        hasPendingPlayback: Bool
    ) -> Bool {
        guard shouldPlayEveAudio(
            dropAssistantOutput: dropAssistantOutput,
            clientTTSInFlight: clientTTSInFlight
        ) else { return false }
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

    /// Live VAD may write the identity line to the one player.
    /// Inbox stubs stay silent — no client “Here they are.”
    public static func shouldWriteLiveDeskLineToPlayer(
        liveVADTurn: Bool,
        spoken: String,
        identityLine: String
    ) -> Bool {
        guard liveVADTurn else { return true }
        let line = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !identityLine.isEmpty else { return false }
        return line == identityLine
    }

    /// Flag-clear body of `GrokVoiceService.returnToListenAfterDeskTTS`.
    /// 8927c2d leftover: `clientTTSInFlight = false` only. Drop stayed
    /// true — following Eve delta is `shouldPlayBargeAudio` false.
    public static func returnToListenAfterDeskTTS(
        dropAssistantOutput: inout Bool,
        clientTTSInFlight: inout Bool
    ) {
        clientTTSInFlight = false
        dropAssistantOutput = false
    }
}
