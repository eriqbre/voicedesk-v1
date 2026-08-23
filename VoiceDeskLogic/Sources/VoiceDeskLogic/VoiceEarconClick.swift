import Foundation

/// Mic on/off earcons only. Siri-style two-tone pair:
/// listen = short bright ascending arm; stop = softer descending disarm.
///
/// Research notes applied:
/// - 100–200ms total so they stay easy to hear on every tap (Horizon).
/// - Fundamentals stay under 1 kHz — never the 2–4 kHz band that fights speech.
/// - Warm sine + light odd harmonic (triangle), gentle attack/decay. Not square.
/// - Kenney-style: on = soft rollover; off = softer switch.
/// Generated PCM so Linux can test it and the live `.playAndRecord` path can play it.
public enum VoiceEarconClick: Sendable {
    public static let sampleRate: Double = 24_000

    /// D5 → G5. Bright enough to notice, well below the 2 kHz speech-fight band.
    public static let listenNotesHz: [Double] = [587, 784]
    /// F5 → A4. Distinct falling pair, quieter than listen.
    public static let stopNotesHz: [Double] = [698, 440]

    /// Soft two-tone arm. Play only when tap-to-talk turns the mic on.
    public static func startPCM16() -> Data {
        twoTone(notesHz: listenNotesHz, noteMs: 52, gapMs: 10, peak: 0.26)
    }

    /// Softer descending disarm. Play only when tap-to-talk turns the mic off.
    public static func endPCM16() -> Data {
        twoTone(notesHz: stopNotesHz, noteMs: 48, gapMs: 8, peak: 0.16)
    }

    public static func startWAV() -> Data {
        wav(fromPCM16: startPCM16())
    }

    public static func endWAV() -> Data {
        wav(fromPCM16: endPCM16())
    }

    public static func durationMilliseconds(_ pcm: Data) -> Double {
        Double(pcm.count / 2) / (sampleRate / 1_000)
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

    private static func twoTone(notesHz: [Double], noteMs: Int, gapMs: Int, peak: Float) -> Data {
        var pcm = Data()
        for (index, hz) in notesHz.enumerated() {
            if index > 0, gapMs > 0 {
                pcm.append(silence(milliseconds: gapMs))
            }
            pcm.append(tone(hz: hz, milliseconds: noteMs, peak: peak))
        }
        return pcm
    }

    private static func silence(milliseconds: Int) -> Data {
        let count = max(0, Int(sampleRate * Double(milliseconds) / 1_000))
        return Data(count: count * MemoryLayout<Int16>.size)
    }

    /// Sine + light 3rd harmonic (triangle warmth). Attack/release avoid a square click.
    private static func tone(hz: Double, milliseconds: Int, peak: Float) -> Data {
        let count = max(1, Int(sampleRate * Double(milliseconds) / 1_000))
        var samples = [Int16](repeating: 0, count: count)
        let duration = Double(count) / sampleRate
        let attack = min(0.010, duration * 0.22)
        let release = min(0.022, duration * 0.42)
        let twoPi = 2 * Double.pi
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let phase = twoPi * hz * time
            let envelope = adsr(time: time, duration: duration, attack: attack, release: release)
            let sine = sin(phase)
            let triangleWarmth = (1.0 / 9.0) * sin(3 * phase)
            let sample = (sine + triangleWarmth) * Double(peak) * envelope
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
