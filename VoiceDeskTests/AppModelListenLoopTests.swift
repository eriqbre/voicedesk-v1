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

    /// Conversation loop on the live service. 415c955 first-hear-then-deaf
    /// heard PCM 1, answered, then never heard PCM 2. Talk, Eve answers
    /// intent on write→player, talk again without repeating. Ambient
    /// during TTS must not drop playback. Only a command cancels her
    /// and is the next turn. Transcript injects do not count.
    func testLiveConversationLoopTalkAnswerTalkAgainWithoutRepeat() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-conversation")
        let snapshot = DeskSnapshot(emails: [SampleData.syncedEmail()])
        let model = AppModel(
            voice: voice,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot),
            buildIdentity: .fixture
        )

        let command1 = Self.speechShapedPCM(hertz: 140)
        let command2 = Self.speechShapedPCM(hertz: 160)
        let command3 = Self.speechShapedPCM(hertz: 180)
        let noise = Self.speechShapedPCM(hertz: 90)
        var session = VoiceSession()
        session.apply(.tapTalk)
        let sink = LiveTapSink(
            session: session,
            commands: [command1, command2, command3],
            noise: noise
        )
        voice.onMicFrame = { pcm in
            sink.onFrame(pcm)
        }

        voice.startListenLoopAudioForTests()
        let engine = voice.listenLoopEngine
        guard engine.isRunning else {
            throw XCTSkip("Simulator HAL did not start the one live engine")
        }
        XCTAssertEqual(engine.startCount, 1)
        sink.tapLive = true
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command1)
        XCTAssertEqual(sink.turns, [command1], "command PCM 1 through the live tap is a turn")
        XCTAssertEqual(engine.startCount, 1)

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "write→player must drain before the next tap turn")
        XCTAssertEqual(engine.startCount, 1, "answer must not audio.start")
        XCTAssertTrue(voice.listenLoopStayLive, "415c955 first-hear-then-deaf left stayLive false after TTS")
        XCTAssertTrue(voice.listenLoopArmed)
        XCTAssertNotEqual(voice.listenLoopClose1000, .stayIdle, "close 1000 stayIdle after the answer is a fail")
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2], "command PCM 2 after drain is the next turn — 415c955 required a repeat")
        XCTAssertEqual(engine.startCount, 1, "talk again must not audio.start")

        XCTAssertFalse(ListenInterrupt.isCommand("and now the weather"))
        XCTAssertFalse(ListenInterrupt.isCommand("Can you hear me?"))
        XCTAssertTrue(ListenInterrupt.isCommand("show me my emails"))
        XCTAssertTrue(ListenInterrupt.isCommand("what's on my calendar"))

        let speaking = Task { await voice.speak(Self.laterDeskReply) }
        await waitUntilPending(engine)
        XCTAssertGreaterThan(engine.pendingPlaybackCount, 0)
        engine.feedTapPCM16(noise)
        XCTAssertEqual(sink.ambient.last, noise)
        XCTAssertEqual(sink.turns, [command1, command2], "ambient / radio / other-room is not a turn")
        XCTAssertGreaterThan(engine.pendingPlaybackCount, 0, "ambient must not cancel write→player")
        XCTAssertTrue(engine.isPlayerPlaying)

        model.voice.interruptResponse()
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "command intent drops playback")
        XCTAssertTrue(engine.isPlayerPlaying, "interruptPlayback must not rip the player")
        XCTAssertTrue(engine.isRunning)
        sink.startCount = engine.startCount
        engine.feedTapPCM16(command3)
        XCTAssertEqual(sink.turns.last, command3, "command-shaped PCM during TTS is the next turn")
        XCTAssertEqual(sink.turns, [command1, command2, command3])
        XCTAssertEqual(engine.startCount, 1)
        await speaking.value
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)
        XCTAssertEqual(
            model.turns.filter { $0.role == .user }.count,
            0,
            "transcript injects do not count"
        )

        voice.cancel()
    }

    /// Same live conversation loop, plus the close the phone logged.
    /// After write→player drain, fire the live DidClose 1000 hook.
    /// 18d5878 / 415c955 parked stayIdle and left sendRaw a no-op.
    /// Today's recover-then-teardown killed the one engine. Either
    /// path fails this. PCM 2 through the same tap is the next turn.
    func testLiveConversationLoopDidClose1000AfterDrainNextCommandIsATurn() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-close-1000")
        let snapshot = DeskSnapshot(emails: [SampleData.syncedEmail()])
        let model = AppModel(
            voice: voice,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot),
            buildIdentity: .fixture
        )

        let command1 = Self.speechShapedPCM(hertz: 140)
        let command2 = Self.speechShapedPCM(hertz: 160)
        let command3 = Self.speechShapedPCM(hertz: 180)
        let noise = Self.speechShapedPCM(hertz: 90)
        var session = VoiceSession()
        session.apply(.tapTalk)
        let sink = LiveTapSink(
            session: session,
            commands: [command1, command2, command3],
            noise: noise
        )
        voice.onMicFrame = { pcm in
            sink.onFrame(pcm)
        }

        voice.startListenLoopAudioForTests()
        let engine = voice.listenLoopEngine
        guard engine.isRunning else {
            throw XCTSkip("Simulator HAL did not start the one live engine")
        }
        XCTAssertEqual(engine.startCount, 1)
        sink.tapLive = true
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command1)
        XCTAssertEqual(sink.turns, [command1], "command PCM 1 through the live tap is a turn")
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask, "startListenLoopAudioForTests does not open Grok")

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "write→player must drain before DidClose")
        XCTAssertEqual(engine.startCount, 1, "answer must not audio.start")
        XCTAssertTrue(voice.listenLoopStayLive, "stayLive after drain must be armed+running, not a stuck TTS flag")
        XCTAssertTrue(voice.listenLoopArmed)
        XCTAssertNotEqual(voice.listenLoopClose1000, .stayIdle, "policy close 1000 stayIdle after the answer is a fail")

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning, "DidClose 1000 after desk TTS must not audio.stop")
        XCTAssertEqual(engine.startCount, 1, "reconnect must not audio.start")
        XCTAssertTrue(voice.listenLoopStayLive, "18d5878 / 415c955 logged stayLive=false stayIdle")
        XCTAssertTrue(voice.listenLoopArmed)
        XCTAssertNotEqual(voice.listenLoopClose1000, .stayIdle, "DidClose 1000 after drain is not user-stop")
        XCTAssertGreaterThan(
            voice.listenLoopRecoverCount,
            0,
            "close left the socket dead without tearing the tap — 415c955 stayIdle never recovered"
        )
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive
        XCTAssertTrue(sink.stayLive, "PCM 2 must not be accepted on a stayIdle sink")

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2], "command PCM 2 after DidClose 1000 is the next turn")
        XCTAssertEqual(engine.startCount, 1, "talk again must not audio.start")
        XCTAssertTrue(engine.isRunning)

        XCTAssertFalse(ListenInterrupt.isCommand("and now the weather"))
        XCTAssertFalse(ListenInterrupt.isCommand("Can you hear me?"))
        XCTAssertTrue(ListenInterrupt.isCommand("show me my emails"))
        XCTAssertTrue(ListenInterrupt.isCommand("what's on my calendar"))

        let speaking = Task { await voice.speak(Self.laterDeskReply) }
        await waitUntilPending(engine)
        XCTAssertGreaterThan(engine.pendingPlaybackCount, 0)
        engine.feedTapPCM16(noise)
        XCTAssertEqual(sink.ambient.last, noise)
        XCTAssertEqual(sink.turns, [command1, command2], "ambient / radio / other-room is not a turn")
        XCTAssertGreaterThan(engine.pendingPlaybackCount, 0, "ambient must not cancel write→player")
        XCTAssertTrue(engine.isPlayerPlaying)

        model.voice.interruptResponse()
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "command intent drops playback")
        XCTAssertTrue(engine.isPlayerPlaying, "interruptPlayback must not rip the player")
        XCTAssertTrue(engine.isRunning)
        sink.startCount = engine.startCount
        engine.feedTapPCM16(command3)
        XCTAssertEqual(sink.turns.last, command3, "command-shaped PCM during TTS is the next turn")
        XCTAssertEqual(sink.turns, [command1, command2, command3])
        XCTAssertEqual(engine.startCount, 1)
        await speaking.value
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)
        XCTAssertEqual(
            model.turns.filter { $0.role == .user }.count,
            0,
            "transcript injects do not count"
        )

        voice.cancel()
    }

    /// After drain + DidClose 1000, command PCM 2 through the same tap
    /// while the send task is still nil. 15dcc7d accepted that on the
    /// tap observer and `sendRaw` dropped it. Attach-send-task then
    /// flushes the short dead-socket queue. Delivered must include
    /// command 2. `startCount` stays 1. Ambient still must not cancel.
    func testLiveConversationLoopDidClose1000DeadSocketWindowSendsQueuedCommand() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-dead-socket")
        let snapshot = DeskSnapshot(emails: [SampleData.syncedEmail()])
        let model = AppModel(
            voice: voice,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: snapshot),
            sync: MockGoogleSync(result: snapshot),
            buildIdentity: .fixture
        )

        let command1 = Self.speechShapedPCM(hertz: 140)
        let command2 = Self.speechShapedPCM(hertz: 160)
        let command3 = Self.speechShapedPCM(hertz: 180)
        let noise = Self.speechShapedPCM(hertz: 90)
        var session = VoiceSession()
        session.apply(.tapTalk)
        let sink = LiveTapSink(
            session: session,
            commands: [command1, command2, command3],
            noise: noise
        )
        voice.onMicFrame = { pcm in
            sink.onFrame(pcm)
        }

        voice.startListenLoopAudioForTests()
        let engine = voice.listenLoopEngine
        guard engine.isRunning else {
            throw XCTSkip("Simulator HAL did not start the one live engine")
        }
        XCTAssertEqual(engine.startCount, 1)
        sink.tapLive = true
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive
        XCTAssertFalse(voice.listenLoopSocketHasSendTask, "startListenLoopAudioForTests does not open Grok")

        engine.feedTapPCM16(command1)
        XCTAssertEqual(sink.turns, [command1], "command PCM 1 through the live tap is a turn")
        XCTAssertEqual(engine.startCount, 1)

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "write→player must drain before DidClose")
        XCTAssertEqual(engine.startCount, 1, "answer must not audio.start")
        XCTAssertTrue(voice.listenLoopStayLive)
        XCTAssertNotEqual(voice.listenLoopClose1000, .stayIdle)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning, "DidClose 1000 after desk TTS must not audio.stop")
        XCTAssertEqual(engine.startCount, 1, "reconnect must not audio.start")
        XCTAssertTrue(voice.listenLoopStayLive)
        XCTAssertGreaterThan(voice.listenLoopRecoverCount, 0)
        XCTAssertFalse(
            voice.listenLoopSocketHasSendTask,
            "recover on sim cannot mint a live send task — this is the dead-socket window"
        )
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2], "tap observer still hears command 2")
        XCTAssertFalse(
            voice.listenLoopDeliveredAudioPCM.contains(command2),
            "command 2 must still be queued — 15dcc7d dropped it here"
        )
        XCTAssertEqual(engine.startCount, 1)

        voice.attachListenLoopSendTaskForTests()
        XCTAssertTrue(voice.listenLoopSocketHasSendTask, "attach-send-task is the live send path")
        XCTAssertTrue(
            voice.listenLoopDeliveredAudioPCM.contains(command2),
            "15dcc7d vanish-after-close: tap accepted command 2, sendRaw never delivered it"
        )
        XCTAssertGreaterThan(voice.listenLoopDeliveredSendCount, 0)
        XCTAssertEqual(engine.startCount, 1, "attach-send-task must not audio.start")
        XCTAssertTrue(engine.isRunning)

        XCTAssertFalse(ListenInterrupt.isCommand("and now the weather"))
        XCTAssertTrue(ListenInterrupt.isCommand("show me my emails"))

        let speaking = Task { await voice.speak(Self.laterDeskReply) }
        await waitUntilPending(engine)
        XCTAssertGreaterThan(engine.pendingPlaybackCount, 0)
        engine.feedTapPCM16(noise)
        XCTAssertEqual(sink.ambient.last, noise)
        XCTAssertEqual(sink.turns, [command1, command2], "ambient / radio / other-room is not a turn")
        XCTAssertGreaterThan(engine.pendingPlaybackCount, 0, "ambient must not cancel write→player")
        XCTAssertTrue(engine.isPlayerPlaying)

        model.voice.interruptResponse()
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "command intent drops playback")
        XCTAssertTrue(engine.isRunning)
        sink.startCount = engine.startCount
        engine.feedTapPCM16(command3)
        XCTAssertEqual(sink.turns.last, command3, "command-shaped PCM during TTS is the next turn")
        XCTAssertEqual(sink.turns, [command1, command2, command3])
        XCTAssertEqual(engine.startCount, 1)
        await speaking.value
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)
        XCTAssertEqual(
            model.turns.filter { $0.role == .user }.count,
            0,
            "transcript injects do not count"
        )

        voice.cancel()
    }

    private func waitUntilPending(_ engine: GrokVoiceAudioEngine) async {
        for _ in 0..<50 {
            if engine.pendingPlaybackCount > 0 { return }
            try? await Task.sleep(for: .milliseconds(40))
        }
        XCTFail("write→player never scheduled buffers")
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

    private static let laterDeskReply = "Here they are. Murray's note is on the screen. I'll keep listening."

    private static func audioSessionSnapshot() -> (category: AVAudioSession.Category, mode: AVAudioSession.Mode) {
        let session = AVAudioSession.sharedInstance()
        return (session.category, session.mode)
    }
}

private final class LiveTapSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _frames: [Data] = []
    private var _turns: [Data] = []
    private var _ambient: [Data] = []
    private var _session: VoiceSession
    private let commands: [Data]
    private let noise: Data?
    var stayLive: Bool
    var startCount: Int
    var tapLive: Bool

    convenience init(session: VoiceSession, command: Data) {
        self.init(session: session, commands: [command], noise: nil)
    }

    init(session: VoiceSession, commands: [Data], noise: Data?) {
        _session = session
        self.commands = commands
        self.noise = noise
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

    var ambient: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _ambient
    }

    func onFrame(_ pcm: Data) {
        lock.lock()
        defer { lock.unlock() }
        if let noise, pcm == noise {
            _ambient.append(pcm)
            return
        }
        guard commands.contains(pcm) else { return }
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
