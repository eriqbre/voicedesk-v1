import Foundation

/// Live Talk has one mouth: Eve PCM on the one player.
/// Desk write-TTS drain + Eve path on the same turn is two mouths.
/// A live VAD response plus a verbatim `response.create` (client stub)
/// is the same two-mouth lie. Skipped-glance stub first-audio is too.
public struct LiveTalkMouth: Equatable, Sendable {
    public var afterDeskTTSDrain: Bool
    public var eveVoicePath: Bool
    public var skippedGlanceStubFirstAudio: Bool
    public var clientVoiceSpeechWrite: Bool
    public var liveVADResponse: Bool
    public var sentVerbatimCreate: Bool

    public init(
        afterDeskTTSDrain: Bool,
        eveVoicePath: Bool,
        skippedGlanceStubFirstAudio: Bool,
        clientVoiceSpeechWrite: Bool,
        liveVADResponse: Bool = false,
        sentVerbatimCreate: Bool = false
    ) {
        self.afterDeskTTSDrain = afterDeskTTSDrain
        self.eveVoicePath = eveVoicePath
        self.skippedGlanceStubFirstAudio = skippedGlanceStubFirstAudio
        self.clientVoiceSpeechWrite = clientVoiceSpeechWrite
        self.liveVADResponse = liveVADResponse
        self.sentVerbatimCreate = sentVerbatimCreate
    }

    /// Desk drain + Eve path, or a second `response.create` on a live VAD turn.
    public var stacksSecondCreate: Bool {
        liveVADResponse && sentVerbatimCreate
    }

    public var isDualMouth: Bool {
        (afterDeskTTSDrain && eveVoicePath)
            || (clientVoiceSpeechWrite && eveVoicePath)
            || stacksSecondCreate
    }

    /// Device fact: version / inbox / person desk drains aligned with
    /// local replies while voicePath stayed Eve. Inbox skipped glance
    /// and played the stub as first audio. No Eve PCM at that instant.
    public static func deskDrainAlignedWithEvePathAndSkippedGlanceStub() -> LiveTalkMouth {
        LiveTalkMouth(
            afterDeskTTSDrain: true,
            eveVoicePath: true,
            skippedGlanceStubFirstAudio: true,
            clientVoiceSpeechWrite: true
        )
    }

    /// 83a5c6a hole: server VAD already created A; client then sent
    /// session.update + fake user text + `response.create` (B) with a stub.
    public static func liveVADPlusVerbatimStub() -> LiveTalkMouth {
        LiveTalkMouth(
            afterDeskTTSDrain: false,
            eveVoicePath: true,
            skippedGlanceStubFirstAudio: true,
            clientVoiceSpeechWrite: false,
            liveVADResponse: true,
            sentVerbatimCreate: true
        )
    }

    /// 4f4f4da first ask: write→player identity while Eve A still speaks.
    public static func firstAskDeskIdentityPlusEve() -> LiveTalkMouth {
        LiveTalkMouth(
            afterDeskTTSDrain: false,
            eveVoicePath: true,
            skippedGlanceStubFirstAudio: false,
            clientVoiceSpeechWrite: true,
            liveVADResponse: true,
            sentVerbatimCreate: false
        )
    }

    /// Version / first identity ask: desk write is the only mouth.
    public static func firstAskDeskIdentityOnly() -> LiveTalkMouth {
        LiveTalkMouth(
            afterDeskTTSDrain: false,
            eveVoicePath: false,
            skippedGlanceStubFirstAudio: false,
            clientVoiceSpeechWrite: true,
            liveVADResponse: true,
            sentVerbatimCreate: false
        )
    }

    public static func liveTalkEveOnly() -> LiveTalkMouth {
        LiveTalkMouth(
            afterDeskTTSDrain: false,
            eveVoicePath: true,
            skippedGlanceStubFirstAudio: false,
            clientVoiceSpeechWrite: false,
            liveVADResponse: true,
            sentVerbatimCreate: false
        )
    }

    public static func offlineClientTTS() -> LiveTalkMouth {
        LiveTalkMouth(
            afterDeskTTSDrain: true,
            eveVoicePath: false,
            skippedGlanceStubFirstAudio: false,
            clientVoiceSpeechWrite: true
        )
    }

    public static func speaksViaEve(
        liveSessionArmed: Bool,
        socketConnected: Bool,
        userWantsVoiceOff: Bool
    ) -> Bool {
        GrokRealtime.shouldSpeakViaRealtime(
            usesLiveLoop: true,
            isConnected: liveSessionArmed && socketConnected,
            userWantsVoiceOff: userWantsVoiceOff
        )
    }
}
