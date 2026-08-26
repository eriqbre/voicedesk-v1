import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

/// No-user first-hear at the tap boundary. Does not start AVAudioEngine.
/// Two PCM chunks land, mock write→player leaves the tap installed,
/// third chunk lands without a second start().
@MainActor
final class GrokVoiceAudioEngineListenResumeTests: XCTestCase {
    func testThirdPCMLandsAfterMockTTSRearmWithoutSecondStart() {
        let tap = MicTapDouble()
        var landed: [Data] = []
        tap.start { base64 in
            if let data = Data(base64Encoded: base64) {
                landed.append(data)
            }
        }
        XCTAssertEqual(tap.startCount, 1)

        tap.injectPCM(Self.chunk(tag: 1))
        tap.injectPCM(Self.chunk(tag: 2))
        XCTAssertEqual(landed.count, 2, "first two PCM chunks must land")

        tap.mockClientTTS()
        XCTAssertEqual(tap.startCount, 1, "mock TTS must not call start() again")

        tap.injectPCM(Self.chunk(tag: 3))
        XCTAssertEqual(landed.count, 3, "third chunk after TTS must land; tap stayed")
        XCTAssertEqual(tap.startCount, 1)
        XCTAssertNotEqual(landed[0], landed[2])
        XCTAssertNotEqual(landed[1], landed[2])
    }

    func testProductClientTTSDoesNotStartOrRearmTheEngine() throws {
        var url = URL(fileURLWithPath: #filePath)
        var source: String?
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("VoiceDesk/Voice/GrokVoiceService.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                source = try? String(contentsOf: candidate, encoding: .utf8)
                break
            }
        }
        let speak = try XCTUnwrap(source)
        XCTAssertTrue(speak.contains("playPCM16"), speak)
        XCTAssertFalse(speak.contains("keepListeningAfterClientTTS"), speak)
        XCTAssertFalse(speak.contains("echoGate"), speak)
        XCTAssertFalse(speak.contains("resumeCaptureAfterDeskSpeak"), speak)
        XCTAssertFalse(speak.contains("armListenIfSessionLive(reason: \"client tts\")"), speak)
        XCTAssertFalse(
            speak.contains("echoGate.beginSpeaking(trimmed)\n        apply(.speakStarted)"),
            speak
        )
        let engine = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceAudioEngine.swift"))
        XCTAssertFalse(engine.contains("func resumeCapture"), engine)
        XCTAssertFalse(engine.contains("func rearmTap"), engine)
    }

    private func repoFile(_ relative: String) -> String? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try? String(contentsOf: candidate, encoding: .utf8)
            }
        }
        return nil
    }

    private static func chunk(tag: Int16) -> [Float] {
        [Float(tag) / Float(Int16.max), 0, Float(-tag) / Float(Int16.max)]
    }
}

/// Tap stand-in. write→player leaves the tap installed. No AVAudioEngine.start.
@MainActor
private final class MicTapDouble {
    private(set) var startCount = 0
    private var onMicAudio: ((String) -> Void)?
    private var tapInstalled = false

    func start(onMicAudio: @escaping (String) -> Void) {
        startCount += 1
        self.onMicAudio = onMicAudio
        tapInstalled = true
    }

    func injectPCM(_ samples: [Float]) {
        guard tapInstalled, let onMicAudio else { return }
        guard let data = GrokVoiceAudioEngine.int16Data(
            samples: samples,
            sourceRate: GrokVoiceAudioEngine.sampleRate
        ) else { return }
        onMicAudio(data.base64EncodedString())
    }

    /// write→player. Tap stays. Must not increment startCount.
    func mockClientTTS() {}
}
