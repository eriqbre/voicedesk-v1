import Foundation
import VoiceDeskLogic
#if canImport(AVFAudio)
@preconcurrency import AVFAudio
#endif

/// Mic on/off only. Never call from transcripts, Eve speak, or card attach.
/// Generated two-tone WAV through AVAudioPlayer (or the live Grok player node).
@MainActor
enum VoiceEarcon {
    /// Returns true when the live engine consumed the PCM (skip local player).
    static var playThroughLiveEngine: ((Data) -> Bool)?

    #if canImport(AVFAudio)
    private static var player: AVAudioPlayer?
    #endif

    static func listenStarted() {
        play(started: true)
    }

    static func listenEnded() {
        play(started: false)
    }

    private static func play(started: Bool) {
        let pcm = started ? VoiceEarconClick.startPCM16() : VoiceEarconClick.endPCM16()
        if playThroughLiveEngine?(pcm) == true {
            return
        }
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
        // Re-negotiating the category for a click is enough to detach a live
        // mic tap, and it would drop the Bluetooth and voice-processing options
        // the capture engine set up. If the session is already ours, leave it.
        guard session.category != .playAndRecord else {
            try? session.setActive(true)
            return
        }
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
