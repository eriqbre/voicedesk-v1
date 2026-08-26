import XCTest
@testable import VoiceDeskLogic

final class QueuedTurnCloseTests: XCTestCase {
    func testCommandSinePostponesRadioAndSilenceDoNot() {
        XCTAssertTrue(
            QueuedTurnClose.shouldPostpone(sinePCM(amplitude: 0.25, hertz: 170)),
            "command-shaped PCM must postpone a flushed commit"
        )
        XCTAssertTrue(QueuedTurnClose.shouldPostpone(sinePCM(amplitude: 0.25, hertz: 140)))
        XCTAssertTrue(QueuedTurnClose.shouldPostpone(sinePCM(amplitude: 0.25, hertz: 160)))
        XCTAssertFalse(
            QueuedTurnClose.shouldPostpone(sinePCM(amplitude: 0.25, hertz: 90)),
            "conversation-loop radio / other-room must not postpone"
        )
        XCTAssertFalse(
            QueuedTurnClose.shouldPostpone(nearSilentPCM()),
            "near-silent tap frames must still close"
        )
    }

    private func sinePCM(amplitude: Double, hertz: Double) -> Data {
        let count = Int(24_000 * 0.12)
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / 24_000
            samples[index] = Int16((sin(2 * .pi * hertz * t) * amplitude * Double(Int16.max)).rounded())
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func nearSilentPCM() -> Data {
        let count = Int(24_000 * 0.04)
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            samples[index] = Int16(index.isMultiple(of: 2) ? 12 : -12)
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
