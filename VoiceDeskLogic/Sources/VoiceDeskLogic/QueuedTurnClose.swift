import Foundation

/// After a dead-socket flush, close the queued command when they stop
/// talking it. Radio / other-room is not a command — same split as
/// `ListenInterrupt`, not RMS. Near-silent tap frames are not talking.
public enum QueuedTurnClose: Sendable {
    /// Conversation-loop ambient stand-in is 90 Hz. Command sines are
    /// 140–180 Hz. A live tap keeps delivering both.
    public static let commandBandHz = 120.0...220.0
    public static let peakFloor: Int16 = 1_000

    public static func shouldPostpone(_ pcm: Data, sampleRate: Double = 24_000) -> Bool {
        let samples = int16Samples(pcm)
        guard samples.count >= 16 else { return false }
        let peak = samples.lazy.map { $0 == Int16.min ? Int16.max : abs($0) }.max() ?? 0
        guard peak >= peakFloor else { return false }
        let seconds = Double(samples.count) / sampleRate
        guard seconds > 0 else { return false }
        let hz = Double(zeroCrossings(samples)) / (2 * seconds)
        return commandBandHz.contains(hz)
    }

    private static func int16Samples(_ pcm: Data) -> [Int16] {
        let count = pcm.count / MemoryLayout<Int16>.size
        guard count > 0 else { return [] }
        return pcm.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Int16.self).prefix(count))
        }
    }

    private static func zeroCrossings(_ samples: [Int16]) -> Int {
        var count = 0
        var previous = samples[0]
        for sample in samples.dropFirst() {
            if (previous >= 0 && sample < 0) || (previous < 0 && sample >= 0) {
                count += 1
            }
            previous = sample
        }
        return count
    }
}
