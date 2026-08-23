import Foundation
#if canImport(AudioToolbox)
import AudioToolbox
#endif

/// Local tap-to-talk click. DEBUG / Mock safe. Does not go through Grok.
enum VoiceEarcon {
    /// Begin-record tock.
    private static let listenOn: SystemSoundID = 1113
    /// Softer end-record tick.
    private static let listenOff: SystemSoundID = 1114

    static func listenStarted() {
        play(listenOn)
    }

    static func listenEnded() {
        play(listenOff)
    }

    private static func play(_ sound: SystemSoundID) {
        #if canImport(AudioToolbox)
        AudioServicesPlaySystemSound(sound)
        #endif
    }
}
