import Foundation

/// Live Talk has one mouth: Eve PCM on the one player.
/// Desk write-TTS drain + Eve path on the same turn is two mouths.
/// Skipped-glance stub first-audio while voicePath is Eve is the same lie.
public struct LiveTalkMouth: Equatable, Sendable {
    public var afterDeskTTSDrain: Bool
    public var eveVoicePath: Bool
    public var skippedGlanceStubFirstAudio: Bool
    public var clientVoiceSpeechWrite: Bool

    public init(
        afterDeskTTSDrain: Bool,
        eveVoicePath: Bool,
        skippedGlanceStubFirstAudio: Bool,
        clientVoiceSpeechWrite: Bool
    ) {
        self.afterDeskTTSDrain = afterDeskTTSDrain
        self.eveVoicePath = eveVoicePath
        self.skippedGlanceStubFirstAudio = skippedGlanceStubFirstAudio
        self.clientVoiceSpeechWrite = clientVoiceSpeechWrite
    }

    /// Desk drain timestamp-aligned with an Eve-path local reply, or a
    /// ClientVoiceSpeech write while voicePath stays Eve.
    public var isDualMouth: Bool {
        (afterDeskTTSDrain && eveVoicePath) || (clientVoiceSpeechWrite && eveVoicePath)
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

    public static func liveTalkEveOnly() -> LiveTalkMouth {
        LiveTalkMouth(
            afterDeskTTSDrain: false,
            eveVoicePath: true,
            skippedGlanceStubFirstAudio: false,
            clientVoiceSpeechWrite: false
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
