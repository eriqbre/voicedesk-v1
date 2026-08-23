import Foundation
import VoiceDeskLogic
#if canImport(AVFAudio)
@preconcurrency import AVFAudio
#endif

/// Mic on/off only. Never call from transcripts, Eve speak, or card attach.
/// Generated two-tone WAV through AVAudioPlayer (or the live Grok player node).
@MainActor
enum VoiceEarcon {
    /// Optional extra path through the live player node. Never replaces AVAudioPlayer —
    /// teardown swallows engine-scheduled PCM on mic-off.
    static var playThroughLiveEngine: ((Data) -> Bool)?
    /// Test hook: `true` = listen started, `false` = listen ended.
    static var playLog: [Bool] = []

    #if canImport(AVFAudio)
    private static var player: AVAudioPlayer?
    #endif
    private static var lastPlayAt: Date?
    private static var lastStarted: Bool?

    static func resetPlayLog() {
        playLog = []
        lastPlayAt = nil
        lastStarted = nil
    }

    static func listenStarted() {
        play(started: true)
    }

    static func listenEnded() {
        play(started: false)
    }

    private static func play(started: Bool) {
        if lastStarted == started, let lastPlayAt, Date().timeIntervalSince(lastPlayAt) < 0.25 {
            return
        }
        lastStarted = started
        lastPlayAt = Date()
        playLog.append(started)
        let pcm = started ? VoiceEarconClick.startPCM16() : VoiceEarconClick.endPCM16()
        _ = playThroughLiveEngine?(pcm)
        playLocally(wav: started ? VoiceEarconClick.startWAV() : VoiceEarconClick.endWAV())
    }

    private static func playLocally(wav: Data) {
        #if canImport(AVFAudio)
        prepareSessionForClick()
        do {
            let next = try AVAudioPlayer(data: wav)
            next.volume = 0.82
            next.prepareToPlay()
            player = next
            next.play()
        } catch {
            // Best-effort local click; listening visual still works.
        }
        #endif
    }

    #if canImport(AVFAudio)
    private static func prepareSessionForClick() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: session.mode,
                options: [.defaultToSpeaker, .mixWithOthers]
            )
            try session.overrideOutputAudioPort(.speaker)
            try session.setActive(true)
        } catch {
            // Playback may still succeed on the current session.
        }
    }
    #endif
}
