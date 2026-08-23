import Foundation

/// PCM16 click used by the tap-to-talk earcon. Generated so it stays audible
/// under `.playAndRecord` — system sound IDs go silent on that session.
public enum VoiceEarconClick: Sendable {
    public static let sampleRate: Double = 24_000

    /// Begin-listen click. Must be hearable on a phone speaker over Grok.
    public static func startPCM16() -> Data {
        tone(frequency: 1_580, milliseconds: 72, peak: 0.72)
    }

    /// End-listen click. Softer, still a real sample — not a system sound ID.
    public static func endPCM16() -> Data {
        tone(frequency: 980, milliseconds: 48, peak: 0.42)
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

    private static func tone(frequency: Double, milliseconds: Int, peak: Float) -> Data {
        let count = max(1, Int(sampleRate * Double(milliseconds) / 1_000))
        var samples = [Int16](repeating: 0, count: count)
        let duration = Double(count) / sampleRate
        let attack = min(0.006, duration / 4)
        let release = min(0.016, duration / 3)
        let twoPi = 2 * Double.pi
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let envelope: Double
            if time < attack {
                envelope = time / attack
            } else if time > duration - release {
                envelope = max(0, (duration - time) / release)
            } else {
                envelope = 1
            }
            let sample = sin(twoPi * frequency * time) * Double(peak) * envelope
            let clipped = max(-1, min(1, sample))
            samples[index] = Int16((clipped * Double(Int16.max)).rounded())
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var next = value.littleEndian
        Swift.withUnsafeBytes(of: &next) { append(contentsOf: $0) }
    }
}
