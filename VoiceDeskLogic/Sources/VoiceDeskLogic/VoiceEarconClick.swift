import Foundation

/// Mic on/off earcons only. Soft sine chirps with ADSR — not a square blip,
/// not a system sound ID. Audible under `.playAndRecord` via AVAudioPlayer.
public enum VoiceEarconClick: Sendable {
    public static let sampleRate: Double = 24_000

    /// Soft ascending arm (~95ms). Play only when tap-to-talk turns the mic on.
    public static func startPCM16() -> Data {
        chirp(startHz: 680, endHz: 920, milliseconds: 95, peak: 0.30)
    }

    /// Softer descending disarm (~110ms). Play only when tap-to-talk turns the mic off.
    public static func endPCM16() -> Data {
        chirp(startHz: 780, endHz: 520, milliseconds: 110, peak: 0.20)
    }

    public static func startWAV() -> Data {
        wav(fromPCM16: startPCM16())
    }

    public static func endWAV() -> Data {
        wav(fromPCM16: endPCM16())
    }

    public static func wav(fromPCM16 pcm: Data, sampleRate: Double = sampleRate) -> Data {
        let rate = UInt32(sampleRate.rounded())
        let dataSize = UInt32(pcm.count)
        let byteRate = rate * 2
        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.append(littleEndian: 36 + dataSize)
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.append(littleEndian: UInt32(16))
        header.append(littleEndian: UInt16(1))
        header.append(littleEndian: UInt16(1))
        header.append(littleEndian: rate)
        header.append(littleEndian: byteRate)
        header.append(littleEndian: UInt16(2))
        header.append(littleEndian: UInt16(16))
        header.append(contentsOf: Array("data".utf8))
        header.append(littleEndian: dataSize)
        header.append(pcm)
        return header
    }

    /// Two-tone-ish sine glide with a tiny 2nd harmonic (warm, not square).
    private static func chirp(startHz: Double, endHz: Double, milliseconds: Int, peak: Float) -> Data {
        let count = max(1, Int(sampleRate * Double(milliseconds) / 1_000))
        var samples = [Int16](repeating: 0, count: count)
        let duration = Double(count) / sampleRate
        let attack = min(0.014, duration * 0.16)
        let release = min(0.032, duration * 0.34)
        var phase = 0.0
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let progress = duration > 0 ? time / duration : 0
            let hz = startHz + (endHz - startHz) * progress
            phase += (2 * Double.pi * hz) / sampleRate
            let envelope = adsr(time: time, duration: duration, attack: attack, release: release)
            let fundamental = sin(phase)
            let warmth = 0.12 * sin(2 * phase)
            let sample = (fundamental + warmth) * Double(peak) * envelope
            let clipped = max(-1, min(1, sample))
            samples[index] = Int16((clipped * Double(Int16.max)).rounded())
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func adsr(time: Double, duration: Double, attack: Double, release: Double) -> Double {
        if time < attack {
            return time / max(attack, 0.0001)
        }
        if time > duration - release {
            return max(0, (duration - time) / max(release, 0.0001))
        }
        return 1
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var next = value.littleEndian
        Swift.withUnsafeBytes(of: &next) { append(contentsOf: $0) }
    }
}
