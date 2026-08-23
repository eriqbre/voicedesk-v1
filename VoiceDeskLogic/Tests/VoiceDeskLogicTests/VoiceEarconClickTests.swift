import XCTest
@testable import VoiceDeskLogic

final class VoiceEarconClickTests: XCTestCase {
    func testStartAndEndClicksAreAudiblePCMNotEmpty() {
        let start = VoiceEarconClick.startPCM16()
        let end = VoiceEarconClick.endPCM16()
        XCTAssertGreaterThan(start.count, 24_000 * 2 / 40, "start click must be more than a few ms")
        XCTAssertGreaterThan(end.count, 24_000 * 2 / 50)
        XCTAssertNotEqual(start, end)

        let startPeak = maxAbsSample(start)
        XCTAssertGreaterThan(startPeak, 4_000, "start chirp must be audible")
        XCTAssertLessThan(startPeak, 18_000, "start chirp must stay polite")
        XCTAssertGreaterThan(maxAbsSample(end), 2_500)
        XCTAssertLessThan(maxAbsSample(end), startPeak)

        let startMs = Double(start.count / 2) / 24.0
        let endMs = Double(end.count / 2) / 24.0
        XCTAssertGreaterThan(startMs, 50)
        XCTAssertLessThan(startMs, 130)
        XCTAssertGreaterThan(endMs, 50)
        XCTAssertLessThan(endMs, 140)
    }

    func testWAVHeaderIsPCM16MonoAtEngineRate() {
        let wav = VoiceEarconClick.startWAV()
        XCTAssertGreaterThan(wav.count, 44)
        XCTAssertEqual(String(bytes: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(bytes: wav.dropFirst(8).prefix(4), encoding: .ascii), "WAVE")
        let channels = wav.uint16LE(at: 22)
        let rate = wav.uint32LE(at: 24)
        let bits = wav.uint16LE(at: 34)
        XCTAssertEqual(channels, 1)
        XCTAssertEqual(rate, 24_000)
        XCTAssertEqual(bits, 16)
    }

    private func maxAbsSample(_ pcm: Data) -> Int {
        pcm.withUnsafeBytes { raw -> Int in
            let samples = raw.bindMemory(to: Int16.self)
            return samples.reduce(0) { max($0, Int(abs(Int32($1)))) }
        }
    }

}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
