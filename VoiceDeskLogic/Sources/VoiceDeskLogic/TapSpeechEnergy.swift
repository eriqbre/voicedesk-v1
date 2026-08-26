import Foundation

/// Quiet after a dead-socket flush is speech energy dropped, not
/// missing HAL frames. A live tap keeps delivering silence PCM.
/// Not a barge-in. Not a second listen loop.
public enum TapSpeechEnergy: Sendable {
    /// Speech-shaped 0.25 sine is ~5800 RMS. Near-silent tap is tens.
    public static let rmsThreshold: Double = 800

    public static func isSpeech(_ pcm: Data) -> Bool {
        let count = pcm.count / MemoryLayout<Int16>.size
        guard count > 0 else { return false }
        var sumSquares = 0.0
        pcm.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for sample in samples {
                let value = Double(sample)
                sumSquares += value * value
            }
        }
        return (sumSquares / Double(count)).squareRoot() >= rmsThreshold
    }
}
