import XCTest
@testable import VoiceDeskLogic

final class VoiceEarconClickTests: XCTestCase {
    func testListenAndStopAreADistinctShortPair() {
        let start = VoiceEarconClick.startPCM16()
        let end = VoiceEarconClick.endPCM16()
        XCTAssertNotEqual(start, end)

        let startMs = VoiceEarconClick.durationMilliseconds(start)
        let endMs = VoiceEarconClick.durationMilliseconds(end)
        XCTAssertGreaterThan(startMs, 80)
        XCTAssertLessThan(startMs, 200)
        XCTAssertGreaterThan(endMs, 80)
        XCTAssertLessThan(endMs, 200)

        let startPeak = maxAbsSample(start)
        XCTAssertGreaterThan(startPeak, 3_500, "listen arm must be audible on repeat taps")
        XCTAssertLessThan(startPeak, 16_000, "must stay polite — Horizon-style repeatable")
        XCTAssertGreaterThan(maxAbsSample(end), 2_000)
        XCTAssertLessThan(maxAbsSample(end), startPeak, "stop is the softer disarm")
    }

    func testNotesStayBelowSpeechFightBand() {
        let all = VoiceEarconClick.listenNotesHz + VoiceEarconClick.stopNotesHz
        XCTAssertEqual(VoiceEarconClick.listenNotesHz.count, 2)
        XCTAssertEqual(VoiceEarconClick.stopNotesHz.count, 2)
        XCTAssertLessThan(VoiceEarconClick.listenNotesHz[0], VoiceEarconClick.listenNotesHz[1], "listen ascends")
        XCTAssertGreaterThan(VoiceEarconClick.stopNotesHz[0], VoiceEarconClick.stopNotesHz[1], "stop descends")
        for hz in all {
            XCTAssertGreaterThan(hz, 400, "too low gets lost on phone speakers")
            XCTAssertLessThan(hz, 1_200, "stay out of the 2–4 kHz harsh / speech band")
        }
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
