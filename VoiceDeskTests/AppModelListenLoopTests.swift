@preconcurrency import AVFAudio
import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

/// Live product path. Engine-only yank helpers can pass while AppModel
/// still talks to FakeLive and stayLive is fixture-only. Hear proof is
/// command PCM through the same tap `GrokVoiceService.speak()` owns.
@MainActor
final class AppModelListenLoopTests: XCTestCase {
    /// Honesty: version + glance write→player on `GrokVoiceService`,
    /// then a delayed HAL yank after `returnToListen`. Flag still true,
    /// no interruption. `AVAudioEngineConfigurationChange` on that live
    /// observer puts the same tap back. Third command PCM is the next
    /// turn. Transcript injects do not count. `startCount` stays 1.
    func testVersionThenGlanceLivePathDelayedYankConfigChangeThirdCommandIsATurn() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop")
        let snapshot = DeskSnapshot(emails: [SampleData.syncedEmail()])
        let model = AppModel(
            voice: voice,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot),
            buildIdentity: .fixture
        )

        let command3 = Self.speechShapedPCM(hertz: 180)
        var session = VoiceSession()
        session.apply(.tapTalk)
        let sink = LiveTapSink(session: session, command: command3)
        voice.onMicFrame = { pcm in
            sink.onFrame(pcm)
        }

        await model.applyUserTurn("what version are we on")
        let engine = voice.listenLoopEngine
        guard engine.isRunning else {
            throw XCTSkip("Simulator HAL did not start the one live engine")
        }
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive, "version write→player must stayLive on the live service")
        XCTAssertTrue(voice.listenLoopArmed)
        XCTAssertNotEqual(voice.listenLoopClose1000, .stayIdle, "close 1000 stayIdle after version is a fail")
        XCTAssertTrue(model.turns.contains { $0.text.contains("VoiceDesk") })

        await model.applyUserTurn("show me my emails")
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1, "glance write→player must not audio.start")
        XCTAssertTrue(voice.listenLoopStayLive, "glance write→player must stayLive on the live service")
        XCTAssertTrue(voice.listenLoopArmed)
        XCTAssertNotEqual(voice.listenLoopClose1000, .stayIdle, "close 1000 stayIdle after glance is a fail")
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "live speak() must drain before returnToListen")

        sink.tapLive = true
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.simulateHALTapYankLeavingInstalledFlagTrue()
        XCTAssertTrue(engine.isTapInstalled, "flag still says installed after delayed HAL yank")
        XCTAssertTrue(engine.isRunning, "415c955-class yank leaves isRunning true")
        XCTAssertEqual(engine.startCount, 1, "yank must not audio.start")
        XCTAssertFalse(
            FirstHearTapLoop.startAudioIfNeededWouldStart(engineRunning: engine.isRunning),
            "old loop no-ops here; a second start is not the repair"
        )
        XCTAssertTrue(voice.listenLoopStayLive)
        XCTAssertNotEqual(voice.listenLoopClose1000, .stayIdle)

        engine.feedTapPCM16(command3)
        XCTAssertTrue(sink.frames.isEmpty, "delayed yank after live returnToListen must not paper-green the third")
        XCTAssertTrue(sink.turns.isEmpty, "engine-only 415c955 would stay deaf here")

        await postEngineConfigurationChange()
        XCTAssertTrue(engine.isRunning)
        XCTAssertTrue(engine.isTapInstalled, "live configuration change must reinstall the same tap")
        XCTAssertEqual(engine.startCount, 1, "reinstall must not audio.start")
        sink.tapLive = true
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("live-path-delayed-yank-third.pcm")
        try command3.write(to: fileURL)
        let thirdFromFile = try Data(contentsOf: fileURL)
        engine.feedTapPCM16(thirdFromFile)
        XCTAssertEqual(sink.frames.last, thirdFromFile, "third command PCM must go through the live tap")
        XCTAssertEqual(sink.turns.last, thirdFromFile, "after live delayed yank + config change, that PCM is the next turn")
        XCTAssertEqual(sink.turns.count, 1)
        XCTAssertEqual(engine.startCount, 1, "if a second start would be required, fail")
        XCTAssertNotEqual(voice.listenLoopClose1000, .stayIdle)
        XCTAssertEqual(
            model.turns.filter { $0.role == .user }.map(\.text),
            ["what version are we on", "show me my emails"],
            "transcript injects do not count as the third turn"
        )

        voice.cancel()
    }

    /// Prevention: live write→player must not flicker the session.
    /// `usesApplicationAudioSession = true` let TTS flip category/mode
    /// or deactivate and yank the tap. After version + glance drain,
    /// the session stays playAndRecord + voiceChat. A delayed HAL yank
    /// with zero notifications is not recovered here — that is not
    /// paper-greened. Do not poll for a silent tap.
    func testVersionThenGlanceWritePlayerDoesNotFlickerAudioSession() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-session")
        let snapshot = DeskSnapshot(emails: [SampleData.syncedEmail()])
        let model = AppModel(
            voice: voice,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot),
            buildIdentity: .fixture
        )

        let command3 = Self.speechShapedPCM(hertz: 180)
        var session = VoiceSession()
        session.apply(.tapTalk)
        let sink = LiveTapSink(session: session, command: command3)
        voice.onMicFrame = { pcm in
            sink.onFrame(pcm)
        }

        await model.applyUserTurn("what version are we on")
        let engine = voice.listenLoopEngine
        guard engine.isRunning else {
            throw XCTSkip("Simulator HAL did not start the one live engine")
        }
        XCTAssertEqual(engine.startCount, 1)
        let afterVersion = Self.audioSessionSnapshot()
        XCTAssertEqual(afterVersion.category, .playAndRecord, "version write→player must not leave playAndRecord")
        XCTAssertEqual(afterVersion.mode, .voiceChat, "echoCancellation start is voiceChat")

        await model.applyUserTurn("show me my emails")
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1, "glance write→player must not audio.start")
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "live speak() must drain before returnToListen")
        let afterGlance = Self.audioSessionSnapshot()
        XCTAssertEqual(afterGlance.category, .playAndRecord, "glance TTS must not change category")
        XCTAssertEqual(afterGlance.mode, .voiceChat, "glance TTS must not change mode")
        XCTAssertEqual(afterGlance.category, afterVersion.category)
        XCTAssertEqual(afterGlance.mode, afterVersion.mode)
        XCTAssertNotEqual(voice.listenLoopClose1000, .stayIdle)

        sink.tapLive = true
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.simulateHALTapYankLeavingInstalledFlagTrue()
        XCTAssertTrue(engine.isTapInstalled, "flag still says installed after delayed HAL yank")
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(
            FirstHearTapLoop.startAudioIfNeededWouldStart(engineRunning: engine.isRunning),
            "zero-notification yank must not be repaired by a second start"
        )

        engine.feedTapPCM16(command3)
        XCTAssertTrue(sink.frames.isEmpty, "zero-notification yank must not be paper-greened")
        XCTAssertTrue(sink.turns.isEmpty, "no interruption and no configurationChange — third stays rejected")

        voice.cancel()
    }

    private func postEngineConfigurationChange() async {
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(80))
    }

    private static func pcm16(seconds: Double, hertz: Double) -> Data {
        let count = Int(GrokVoiceAudioEngine.sampleRate * seconds)
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / GrokVoiceAudioEngine.sampleRate
            samples[index] = Int16((sin(2 * .pi * hertz * t) * 0.25 * Double(Int16.max)).rounded())
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func speechShapedPCM(hertz: Double) -> Data {
        pcm16(seconds: 0.12, hertz: hertz)
    }

    private static func audioSessionSnapshot() -> (category: AVAudioSession.Category, mode: AVAudioSession.Mode) {
        let session = AVAudioSession.sharedInstance()
        return (session.category, session.mode)
    }
}

private final class LiveTapSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _frames: [Data] = []
    private var _turns: [Data] = []
    private var _session: VoiceSession
    private let command: Data
    var stayLive: Bool
    var startCount: Int
    var tapLive: Bool

    init(session: VoiceSession, command: Data) {
        _session = session
        self.command = command
        stayLive = true
        startCount = 1
        tapLive = true
    }

    var frames: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _frames
    }

    var turns: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _turns
    }

    func onFrame(_ pcm: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard pcm == command else { return }
        _frames.append(pcm)
        if let turn = FirstHearTapLoop.accept(
            pcm: pcm,
            tapLive: tapLive,
            session: _session,
            stayLive: stayLive,
            startCount: startCount
        ) {
            _turns.append(turn)
        }
    }
}
