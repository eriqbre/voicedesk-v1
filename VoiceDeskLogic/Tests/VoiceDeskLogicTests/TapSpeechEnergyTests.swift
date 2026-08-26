import XCTest
@testable import VoiceDeskLogic

final class TapSpeechEnergyTests: XCTestCase {
    func testQuietIsSpeechEnergyDroppedNotMissingFrames() {
        XCTAssertTrue(
            TapSpeechEnergy.isSpeech(sinePCM(amplitude: 0.25, hertz: 160)),
            "speech-shaped PCM must postpone a flushed commit"
        )
        XCTAssertFalse(
            TapSpeechEnergy.isSpeech(Data(count: 2_400)),
            "zero frames from a live tap are not still-talking"
        )
        XCTAssertFalse(
            TapSpeechEnergy.isSpeech(sinePCM(amplitude: 0.005, hertz: 160)),
            "near-silent tap PCM must let the queued command close"
        )
    }

    private func sinePCM(amplitude: Double, hertz: Double) -> Data {
        let count = 2_880
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / 24_000
            samples[index] = Int16((sin(2 * .pi * hertz * t) * amplitude * Double(Int16.max)).rounded())
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
