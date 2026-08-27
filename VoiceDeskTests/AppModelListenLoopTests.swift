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

    /// Product path after Eve talks on a socket that stays open.
    /// 4dc589f armed send with attachListenLoopSendTaskForTests —
    /// a fake task. sendRaw is a no-op when the real task is nil.
    /// That is 415c955. Arm once via DidOpen + session.updated
    /// before command 1. Do not DidClose 1000. Do not attach.
    /// Command 2 after drain is a live append. `startCount` stays 1.
    func testLiveConversationLoopAfterDeskTTSWithoutSocketCloseNextCommandIsATurn() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-open-socket-after-desk-tts")
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

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        XCTAssertTrue(voice.listenLoopSocketHasSendTask, "DidOpen + session.updated arms the real client")
        XCTAssertEqual(voice.listenLoopRecoverCount, 0, "first arm is not a recover")

        engine.feedTapPCM16(command1)
        XCTAssertEqual(sink.turns, [command1], "command PCM 1 through the live tap is a turn")
        XCTAssertTrue(
            voice.listenLoopDeliveredAudioPCM.contains(command1),
            "command 1 must go out on the live send path"
        )
        XCTAssertEqual(engine.startCount, 1)

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "write→player must drain before the next tap turn")
        XCTAssertEqual(engine.startCount, 1, "answer must not audio.start")
        XCTAssertTrue(voice.listenLoopStayLive)
        XCTAssertTrue(
            voice.listenLoopSocketHasSendTask,
            "drain must not drop the live send task — 415c955 first-hear-then-deaf"
        )
        XCTAssertEqual(voice.listenLoopRecoverCount, 0, "open socket must not recover")
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2], "command PCM 2 after drain is the next turn")
        XCTAssertTrue(
            voice.listenLoopDeliveredAudioPCM.contains(command2),
            "command 2 must be a live append — 4dc589f attach paper-greened a dead client"
        )
        XCTAssertTrue(
            voice.listenLoopDeliveredSendTypes.contains("input_audio_buffer.append"),
            "command 2 is a live append, not a queued recover flush"
        )
        XCTAssertTrue(voice.listenLoopSocketHasSendTask, "send task stays live after the next command")
        XCTAssertEqual(engine.startCount, 1, "talk again must not audio.start")
        XCTAssertEqual(voice.listenLoopRecoverCount, 0)

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
        XCTAssertEqual(sink.turns.last, command3)
        XCTAssertEqual(sink.turns, [command1, command2, command3])
        XCTAssertEqual(engine.startCount, 1)
        await speaking.value
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)
        XCTAssertTrue(voice.listenLoopSocketHasSendTask)
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

    /// 415c955 / 18d5878 logged `session close code=1000 stayLive=false
    /// stayIdle` after version TTS. Current DidClose gates fire while
    /// stayLive is still true — they would not have failed that path.
    /// After write→player, idle the session (phone log). User did not
    /// tap stop. DidClose 1000 must recover. Command 2 must send and
    /// request a response. `startCount` stays 1.
    func testLiveConversationLoopDidClose1000StayLiveFalseIdleAfterDeskTTSRecoversNextCommand() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-close-1000-idle-phone-log")
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
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "write→player must drain before the phone-log idle")
        XCTAssertEqual(engine.startCount, 1, "answer must not audio.start")
        XCTAssertTrue(voice.listenLoopStayLive)

        voice.simulateListenLoopIdleAfterDeskTTSPhoneLog()
        XCTAssertFalse(voice.listenLoopArmed, "phone log: state=idle, listen not armed")
        XCTAssertFalse(
            voice.listenLoopPhoneStayLive,
            "415c955 stayLive was listen-armed — idle after TTS is stayLive=false"
        )
        XCTAssertNotEqual(
            voice.listenLoopClose1000,
            .stayIdle,
            "live conversation must reconnect on 1000 even if VoiceSession is idle"
        )
        XCTAssertEqual(voice.listenLoopRecoverCount, 0, "idle is not a close")

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning, "DidClose 1000 after desk TTS must not audio.stop")
        XCTAssertEqual(engine.startCount, 1, "reconnect must not audio.start")
        XCTAssertGreaterThan(
            voice.listenLoopRecoverCount,
            0,
            "415c955 stayLive=false stayIdle never recovered"
        )
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2], "command PCM 2 after the phone-log close is the next turn")
        XCTAssertEqual(engine.startCount, 1)

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        XCTAssertTrue(
            voice.listenLoopDeliveredAudioPCM.contains(command2),
            "command 2 must send after recover — 415c955 sendRaw was a no-op"
        )
        let types = voice.listenLoopDeliveredSendTypes
        let sends = voice.listenLoopDeliveredSends
        guard let firstUpdate = sends.first(where: { LiveGrokVoiceClient.typeOfSend($0) == "session.update" })
        else {
            XCTFail("recover must send listen-resume session.update")
            voice.cancel()
            return
        }
        XCTAssertEqual(
            GrokRealtime.createResponse(inSessionUpdate: firstUpdate),
            true,
            "recover must request a response"
        )
        XCTAssertTrue(types.contains("input_audio_buffer.append"))
        XCTAssertEqual(engine.startCount, 1)
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
        XCTAssertEqual(sink.turns.last, command3)
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

    /// After drain + DidClose 1000, command PCM 2 while the send task
    /// is dead, then the real DidOpen path. 19c1b33 flushed appends on
    /// notifyOpen before `session.update`. Those frames never become a
    /// Grok turn. Send order must be session-ready, then command 2.
    /// `startCount` stays 1. Ambient still must not cancel.
    func testLiveConversationLoopDidClose1000SessionReadyFlushSendsQueuedCommand() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-session-ready")
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
        XCTAssertFalse(voice.listenLoopSocketHasSendTask)

        engine.feedTapPCM16(command1)
        XCTAssertEqual(sink.turns, [command1])
        XCTAssertEqual(engine.startCount, 1)

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)
        XCTAssertNotEqual(voice.listenLoopClose1000, .stayIdle)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)
        XCTAssertGreaterThan(voice.listenLoopRecoverCount, 0)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask, "dead-socket window")
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2], "tap observer still hears command 2")
        XCTAssertFalse(
            voice.listenLoopDeliveredAudioPCM.contains(command2),
            "command 2 must still be queued until the session is ready"
        )
        XCTAssertEqual(engine.startCount, 1)

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        XCTAssertEqual(engine.startCount, 1, "DidOpen / session.updated must not audio.start")
        XCTAssertTrue(engine.isRunning)
        XCTAssertTrue(
            voice.listenLoopDeliveredAudioPCM.contains(command2),
            "19c1b33 delivered command 2 before session.update — Grok ignores those appends"
        )
        let types = voice.listenLoopDeliveredSendTypes
        guard let updateAt = types.firstIndex(of: "session.update"),
              let appendAt = types.firstIndex(of: "input_audio_buffer.append")
        else {
            XCTFail("DidOpen path must send session.update and the queued append")
            voice.cancel()
            return
        }
        XCTAssertLessThan(
            updateAt,
            appendAt,
            "19c1b33 flushed appends on notifyOpen before session.update"
        )
        XCTAssertTrue(types.contains("session.update"))

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

    /// After drain + DidClose 1000, command PCM 2 while the socket is
    /// dead, then DidOpen → session.updated flush. Do not feed more PCM
    /// after that. 48eb875 sent the appends and stopped. No trailing
    /// silence, no commit — VAD never closed the turn. One commit after
    /// the queued command is enough. The live tap may still append
    /// after that close — lastIndex(append) is not command 2.
    /// `startCount` stays 1.
    func testLiveConversationLoopDidClose1000FlushClosesQueuedTurn() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-flush-commit")
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
        XCTAssertEqual(sink.turns, [command1])

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask)
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2])
        XCTAssertFalse(voice.listenLoopDeliveredAudioPCM.contains(command2))

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        await voice.waitUntilListenLoopQueuedTurnClosed()
        XCTAssertEqual(engine.startCount, 1, "flush + commit must not audio.start")
        XCTAssertTrue(engine.isRunning)
        XCTAssertTrue(
            voice.listenLoopDeliveredAudioPCM.contains(command2),
            "queued command 2 must flush after session.updated"
        )
        let pcm = voice.listenLoopDeliveredAudioPCM
        let types = voice.listenLoopDeliveredSendTypes
        let appendSlots = types.enumerated().compactMap { $0.element == "input_audio_buffer.append" ? $0.offset : nil }
        let paired = Array(zip(appendSlots, pcm))
        guard let command2At = paired.last(where: { $0.1 == command2 })?.0,
              let commitAt = types.firstIndex(of: "input_audio_buffer.commit")
        else {
            XCTFail("48eb875 flushed appends only — no commit, no trailing silence, VAD never closed the turn")
            voice.cancel()
            return
        }
        XCTAssertLessThan(
            command2At,
            commitAt,
            "commit must follow the queued command, not precede it"
        )
        XCTAssertEqual(sink.turns, [command1, command2], "do not feed more PCM after the flush to close the turn")

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
        XCTAssertEqual(sink.turns.last, command3)
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

    /// Still talking when session.updated fires. 6b5f0ee committed
    /// between the queued command and the next speech-shaped PCM.
    /// That truncates the utterance. Commit only after the tap is quiet.
    /// The no-more-PCM sibling still requires a turn close.
    func testLiveConversationLoopDidClose1000StillTalkingDoesNotCommitMidUtterance() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-still-talking")
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
        let continued = Self.speechShapedPCM(hertz: 170)
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
        XCTAssertEqual(sink.turns, [command1])

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask)
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2])

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        XCTAssertTrue(voice.listenLoopDeliveredAudioPCM.contains(command2))
        engine.feedTapPCM16(continued)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(engine.isRunning)

        let pcm = voice.listenLoopDeliveredAudioPCM
        let types = voice.listenLoopDeliveredSendTypes
        let appendSlots = types.enumerated().compactMap { $0.element == "input_audio_buffer.append" ? $0.offset : nil }
        let paired = Array(zip(appendSlots, pcm))
        guard let command2At = paired.last(where: { $0.1 == command2 })?.0,
              let continuedAt = paired.first(where: { $0.1 == continued })?.0
        else {
            XCTFail("queued command 2 and the still-talking tail must both be sent")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, continuedAt)
        if let commitAt = types.firstIndex(of: "input_audio_buffer.commit") {
            XCTAssertFalse(
                command2At < commitAt && commitAt < continuedAt,
                "6b5f0ee committed mid-utterance — rest of the command is orphaned or dropped"
            )
        }

        await voice.waitUntilListenLoopQueuedTurnClosed()
        let after = voice.listenLoopDeliveredSendTypes
        guard let commitAt = after.firstIndex(of: "input_audio_buffer.commit") else {
            XCTFail("after the tap goes quiet, the queued command must still close")
            voice.cancel()
            return
        }
        XCTAssertGreaterThan(commitAt, continuedAt, "commit belongs after the still-talking tail")
        XCTAssertEqual(engine.startCount, 1)

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
        XCTAssertEqual(sink.turns.last, command3)
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

    /// Live tap never stops. After drain + DidClose 1000, command PCM 2
    /// while dead, DidOpen → session.updated flush, then keep feeding
    /// near-silent tap PCM. 00297ee treated those frames as still-talking
    /// and never sent `input_audio_buffer.commit`. Speech-shaped PCM
    /// still postpones. `startCount` stays 1.
    func testLiveConversationLoopDidClose1000SilenceTapStillClosesQueuedTurn() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-silence-tap")
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
        let continued = Self.speechShapedPCM(hertz: 170)
        let command3 = Self.speechShapedPCM(hertz: 180)
        let noise = Self.speechShapedPCM(hertz: 90)
        let silence = Self.nearSilentPCM()
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
        XCTAssertEqual(sink.turns, [command1])

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask)
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2])

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        XCTAssertTrue(voice.listenLoopDeliveredAudioPCM.contains(command2))
        engine.feedTapPCM16(continued)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(engine.isRunning)

        let pcm = voice.listenLoopDeliveredAudioPCM
        let types = voice.listenLoopDeliveredSendTypes
        let appendSlots = types.enumerated().compactMap { $0.element == "input_audio_buffer.append" ? $0.offset : nil }
        let paired = Array(zip(appendSlots, pcm))
        guard let command2At = paired.last(where: { $0.1 == command2 })?.0,
              let continuedAt = paired.first(where: { $0.1 == continued })?.0
        else {
            XCTFail("queued command 2 and the still-talking tail must both be sent")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, continuedAt)
        if let commitAt = types.firstIndex(of: "input_audio_buffer.commit") {
            XCTAssertFalse(
                command2At < commitAt && commitAt < continuedAt,
                "speech-shaped PCM must still postpone commit"
            )
        }

        var closedDuringSilence = false
        for _ in 0..<140 {
            engine.feedTapPCM16(silence)
            if voice.listenLoopDeliveredSendTypes.contains("input_audio_buffer.commit") {
                closedDuringSilence = true
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(
            closedDuringSilence,
            "00297ee treated silence frames as still-talking — commit never fired while the live tap kept delivering"
        )
        XCTAssertTrue(
            voice.listenLoopDeliveredAudioPCM.contains(silence),
            "silence frames must go out; quiet is energy dropped, not a stopped tap"
        )
        let after = voice.listenLoopDeliveredSendTypes
        guard let commitAt = after.firstIndex(of: "input_audio_buffer.commit") else {
            XCTFail("silence frames must still let the queued command close")
            voice.cancel()
            return
        }
        XCTAssertGreaterThan(commitAt, continuedAt, "commit belongs after the still-talking tail")
        XCTAssertEqual(engine.startCount, 1, "silence-tap commit must not audio.start")
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(sink.turns, [command1, command2], "silence PCM is not a turn")

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
        XCTAssertEqual(sink.turns.last, command3)
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

    /// Radio / other-room is speech-shaped energy. After drain + DidClose
    /// 1000, command PCM 2 while dead, DidOpen → session.updated flush,
    /// then keep feeding the same ambient PCM the conversation loop
    /// already treats as non-command. 2679792 postponed on RMS and never
    /// sent `input_audio_buffer.commit`. Command PCM still postpones.
    /// `startCount` stays 1.
    func testLiveConversationLoopDidClose1000AmbientTapStillClosesQueuedTurn() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-ambient-tap")
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
        let continued = Self.speechShapedPCM(hertz: 170)
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
        XCTAssertEqual(sink.turns, [command1])

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask)
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2])

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        XCTAssertTrue(voice.listenLoopDeliveredAudioPCM.contains(command2))
        engine.feedTapPCM16(continued)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(engine.isRunning)

        let pcm = voice.listenLoopDeliveredAudioPCM
        let types = voice.listenLoopDeliveredSendTypes
        let appendSlots = types.enumerated().compactMap { $0.element == "input_audio_buffer.append" ? $0.offset : nil }
        let paired = Array(zip(appendSlots, pcm))
        guard let command2At = paired.last(where: { $0.1 == command2 })?.0,
              let continuedAt = paired.first(where: { $0.1 == continued })?.0
        else {
            XCTFail("queued command 2 and the still-talking tail must both be sent")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, continuedAt)
        if let commitAt = types.firstIndex(of: "input_audio_buffer.commit") {
            XCTAssertFalse(
                command2At < commitAt && commitAt < continuedAt,
                "command-shaped PCM must still postpone commit"
            )
        }

        XCTAssertFalse(ListenInterrupt.isCommand("and now the weather"))
        XCTAssertFalse(ListenInterrupt.isCommand("Can you hear me?"))
        XCTAssertTrue(ListenInterrupt.isCommand("show me my emails"))

        var closedDuringAmbient = false
        for _ in 0..<140 {
            engine.feedTapPCM16(noise)
            if voice.listenLoopDeliveredSendTypes.contains("input_audio_buffer.commit") {
                closedDuringAmbient = true
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(
            closedDuringAmbient,
            "2679792 treated radio RMS as still-talking — commit never fired while ambient kept arriving"
        )
        XCTAssertTrue(
            voice.listenLoopDeliveredAudioPCM.contains(noise),
            "ambient frames must go out; radio is not a stopped tap"
        )
        XCTAssertEqual(sink.ambient.last, noise)
        let after = voice.listenLoopDeliveredSendTypes
        guard let commitAt = after.firstIndex(of: "input_audio_buffer.commit") else {
            XCTFail("ambient / radio must not block the queued turn close")
            voice.cancel()
            return
        }
        XCTAssertGreaterThan(commitAt, continuedAt, "commit belongs after the still-talking tail")
        XCTAssertEqual(engine.startCount, 1, "ambient-tap commit must not audio.start")
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(sink.turns, [command1, command2], "ambient / radio / other-room is not a turn")

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
        XCTAssertEqual(sink.turns.last, command3)
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

    /// After drain + DidClose 1000, command PCM 2 while dead, real
    /// DidOpen + session.updated recover. e89d443 flushed+committed on
    /// the no-flag session.update. Grok never answers. The first
    /// session.update must request a response before commit.
    /// `startCount` stays 1.
    func testLiveConversationLoopDidClose1000QueuedCommandRequestsResponse() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-request-response")
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
        XCTAssertEqual(sink.turns, [command1])

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask)
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2])

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        await voice.waitUntilListenLoopQueuedTurnClosed()
        XCTAssertEqual(engine.startCount, 1, "response-request recover must not audio.start")
        XCTAssertTrue(engine.isRunning)
        XCTAssertTrue(
            voice.listenLoopDeliveredAudioPCM.contains(command2),
            "queued command 2 must flush after session.updated"
        )

        let types = voice.listenLoopDeliveredSendTypes
        let sends = voice.listenLoopDeliveredSends
        guard let updateAt = types.firstIndex(of: "session.update"),
              let commitAt = types.firstIndex(of: "input_audio_buffer.commit"),
              let firstUpdate = sends.first(where: { LiveGrokVoiceClient.typeOfSend($0) == "session.update" })
        else {
            XCTFail("recover must send session.update and close the queued command")
            voice.cancel()
            return
        }
        XCTAssertLessThan(
            updateAt,
            commitAt,
            "session.update must precede commit"
        )
        XCTAssertEqual(
            GrokRealtime.createResponse(inSessionUpdate: firstUpdate),
            true,
            "e89d443 DidOpen sent sessionUpdateObject with create_response omitted — commit on a session that never asked for a response"
        )

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
        XCTAssertEqual(sink.turns.last, command3)
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

    /// Immediate tail after flush. 7350153 held the close until the
    /// last continued frame — that is a flush-clock. The queued
    /// utterance is already in the buffer. Close it on a short quiet.
    /// Continued frames may follow that close. Radio still must not block.
    func testLiveConversationLoopDidClose1000StillTalkingLongerThanQuietCommitDoesNotTruncate() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-still-talking-long")
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
        let continued = Self.speechShapedPCM(hertz: 170)
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
        XCTAssertEqual(sink.turns, [command1])

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask)
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2])

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        XCTAssertTrue(voice.listenLoopDeliveredAudioPCM.contains(command2))

        for _ in 0..<15 {
            engine.feedTapPCM16(continued)
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(engine.isRunning)

        let pcm = voice.listenLoopDeliveredAudioPCM
        let types = voice.listenLoopDeliveredSendTypes
        let appendSlots = types.enumerated().compactMap { $0.element == "input_audio_buffer.append" ? $0.offset : nil }
        let paired = Array(zip(appendSlots, pcm))
        guard let command2At = paired.last(where: { $0.1 == command2 })?.0,
              let lastContinuedAt = paired.last(where: { $0.1 == continued })?.0
        else {
            XCTFail("queued command 2 and the still-talking tail must both be sent")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, lastContinuedAt)
        XCTAssertGreaterThanOrEqual(
            paired.filter { $0.1 == continued }.count,
            12,
            "must keep feeding command-shaped PCM longer than quietCommitMs — 7350153 held until the last frame"
        )
        await voice.waitUntilListenLoopQueuedTurnClosed()
        let after = voice.listenLoopDeliveredSendTypes
        guard let commitAt = after.firstIndex(of: "input_audio_buffer.commit") else {
            XCTFail("the flushed queued command must still close")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, commitAt, "queued command must be in the buffer before commit")
        XCTAssertEqual(engine.startCount, 1)

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
        XCTAssertEqual(sink.turns.last, command3)
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

    /// 6264a07 only postponed 120–220 Hz sines. Real speech ZCR is
    /// not a 160 Hz tone. Same recover path, mixed-harmonic tail.
    /// The queued utterance is already in the buffer. Close it on
    /// a short quiet. Continued frames may follow that close.
    /// `startCount` stays 1.
    func testLiveConversationLoopDidClose1000RealSpeechStillTalkingDoesNotTruncate() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-real-speech-still-talking")
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
        let continued = Self.mixedHarmonicSpeechPCM()
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
        XCTAssertEqual(sink.turns, [command1])

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask)
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2])

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        XCTAssertTrue(voice.listenLoopDeliveredAudioPCM.contains(command2))

        for _ in 0..<15 {
            engine.feedTapPCM16(continued)
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(engine.isRunning)

        let pcm = voice.listenLoopDeliveredAudioPCM
        let types = voice.listenLoopDeliveredSendTypes
        let appendSlots = types.enumerated().compactMap { $0.element == "input_audio_buffer.append" ? $0.offset : nil }
        let paired = Array(zip(appendSlots, pcm))
        guard let command2At = paired.last(where: { $0.1 == command2 })?.0,
              let lastContinuedAt = paired.last(where: { $0.1 == continued })?.0
        else {
            XCTFail("queued command 2 and the real-speech tail must both be sent")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, lastContinuedAt)
        XCTAssertGreaterThanOrEqual(
            paired.filter { $0.1 == continued }.count,
            12,
            "must keep feeding real-speech PCM longer than quietCommitMs — 6264a07 was a sine detector"
        )
        await voice.waitUntilListenLoopQueuedTurnClosed()
        let after = voice.listenLoopDeliveredSendTypes
        guard let commitAt = after.firstIndex(of: "input_audio_buffer.commit") else {
            XCTFail("the flushed queued command must still close")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, commitAt, "queued command must be in the buffer before commit")
        XCTAssertEqual(engine.startCount, 1)

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
        XCTAssertEqual(sink.turns.last, command3)
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

    /// Immediate tail after flush. The queued utterance is already
    /// in the buffer. Close it on a short quiet. Continued frames
    /// may follow that close — a new server-VAD turn, not a reason
    /// to hold a flush-clock. `startCount` stays 1.
    func testLiveConversationLoopDidClose1000RealSpeechLongerThanMaxPostponeDoesNotTruncate() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-real-speech-longer-than-max-postpone")
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
        let continued = Self.mixedHarmonicSpeechPCM()
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
        XCTAssertEqual(sink.turns, [command1])

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask)
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2])

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        XCTAssertTrue(voice.listenLoopDeliveredAudioPCM.contains(command2))

        for _ in 0..<75 {
            engine.feedTapPCM16(continued)
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(engine.isRunning)

        let pcm = voice.listenLoopDeliveredAudioPCM
        let types = voice.listenLoopDeliveredSendTypes
        let appendSlots = types.enumerated().compactMap { $0.element == "input_audio_buffer.append" ? $0.offset : nil }
        let paired = Array(zip(appendSlots, pcm))
        guard let command2At = paired.last(where: { $0.1 == command2 })?.0,
              let lastContinuedAt = paired.last(where: { $0.1 == continued })?.0
        else {
            XCTFail("queued command 2 and the long real-speech tail must both be sent")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, lastContinuedAt)
        XCTAssertGreaterThanOrEqual(
            paired.filter { $0.1 == continued }.count,
            40,
            "must keep feeding real-speech PCM after the queued close — 3c7524b flush-clock is gone"
        )
        await voice.waitUntilListenLoopQueuedTurnClosed()
        let after = voice.listenLoopDeliveredSendTypes
        guard let commitAt = after.firstIndex(of: "input_audio_buffer.commit") else {
            XCTFail("the flushed queued command must still close")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, commitAt, "queued command must be in the buffer before commit")
        XCTAssertEqual(engine.startCount, 1)

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
        XCTAssertEqual(sink.turns.last, command3)
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

    /// 12a60a5 armed the quiet close at flush and gave up at 2500ms
    /// from that instant. ~2s of think / radio then a real command
    /// still got cut at 2.5s. Same recover path. Feed only 90 Hz
    /// radio for ~2s, then mixed-harmonic command PCM for ≥1s.
    /// The queued turn must close during the quiet / radio. The
    /// delayed command must not be cut mid-utterance. After it
    /// stops, a close may fire. `startCount` stays 1.
    func testLiveConversationLoopDidClose1000DelayedCommandAfterRecoverIsNotTruncated() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-delayed-command-after-recover")
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
        let delayed = Self.mixedHarmonicSpeechPCM()
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
        XCTAssertEqual(sink.turns, [command1])

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask)
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2])

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        XCTAssertTrue(voice.listenLoopDeliveredAudioPCM.contains(command2))

        for _ in 0..<110 {
            engine.feedTapPCM16(noise)
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(sink.turns, [command1, command2], "think / radio after flush is not a turn")
        XCTAssertEqual(engine.startCount, 1)

        for _ in 0..<50 {
            engine.feedTapPCM16(delayed)
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(engine.isRunning)

        let pcm = voice.listenLoopDeliveredAudioPCM
        let types = voice.listenLoopDeliveredSendTypes
        let appendSlots = types.enumerated().compactMap { $0.element == "input_audio_buffer.append" ? $0.offset : nil }
        let paired = Array(zip(appendSlots, pcm))
        guard let command2At = paired.last(where: { $0.1 == command2 })?.0,
              let firstDelayedAt = paired.first(where: { $0.1 == delayed })?.0,
              let lastDelayedAt = paired.last(where: { $0.1 == delayed })?.0
        else {
            XCTFail("queued command 2 and the delayed command must both be sent")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, firstDelayedAt)
        XCTAssertGreaterThanOrEqual(
            paired.filter { $0.1 == delayed }.count,
            40,
            "must keep feeding the delayed command for ≥1s"
        )
        XCTAssertGreaterThanOrEqual(
            paired.filter { $0.1 == noise }.count,
            80,
            "must feed think / radio for ~2s before the delayed command"
        )
        guard let commitAt = types.firstIndex(of: "input_audio_buffer.commit") else {
            XCTFail("queued turn must close during the quiet / radio after flush")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, commitAt, "commit must follow the queued command")
        XCTAssertLessThan(
            commitAt,
            firstDelayedAt,
            "12a60a5 flush-clock closed at 2.5s — mid delayed command"
        )
        XCTAssertFalse(
            firstDelayedAt < commitAt && commitAt < lastDelayedAt,
            "delayed command after recover must not be cut mid-utterance"
        )

        await voice.waitUntilListenLoopQueuedTurnClosed()
        XCTAssertEqual(engine.startCount, 1)
        let after = voice.listenLoopDeliveredSendTypes
        XCTAssertTrue(after.contains("input_audio_buffer.commit"))

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
        XCTAssertEqual(sink.turns.last, command3)
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

    /// 5078dff still used an 1800ms flush-clock. Think ~1s, then a
    /// 1.5s command, gets cut at 1.8s from flush. Same recover path.
    /// Feed only 90 Hz radio for ~1s, then ≥1.5s mixed-harmonic.
    /// That delayed command must not take a commit mid-utterance.
    /// The queued turn closes on a short quiet after flush.
    /// `startCount` stays 1.
    func testLiveConversationLoopDidClose1000ThinkThenTalkAfterRecoverIsNotTruncated() async throws {
        let voice = GrokVoiceService(apiKey: "test-listen-loop-think-then-talk-after-recover")
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
        let delayed = Self.mixedHarmonicSpeechPCM()
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
        XCTAssertEqual(sink.turns, [command1])

        await voice.speak(InboxGlance.spokenListAck())
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(voice.listenLoopStayLive)

        await voice.simulateListenLoopSocketClose1000()
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(voice.listenLoopSocketHasSendTask)
        sink.startCount = engine.startCount
        sink.stayLive = voice.listenLoopStayLive

        engine.feedTapPCM16(command2)
        XCTAssertEqual(sink.turns, [command1, command2])

        voice.simulateListenLoopSocketDidOpenThenSessionReady()
        XCTAssertTrue(voice.listenLoopDeliveredAudioPCM.contains(command2))

        for _ in 0..<50 {
            engine.feedTapPCM16(noise)
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(sink.turns, [command1, command2], "think / radio after flush is not a turn")
        XCTAssertEqual(engine.startCount, 1)

        for _ in 0..<75 {
            engine.feedTapPCM16(delayed)
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(engine.isRunning)

        let pcm = voice.listenLoopDeliveredAudioPCM
        let types = voice.listenLoopDeliveredSendTypes
        let appendSlots = types.enumerated().compactMap { $0.element == "input_audio_buffer.append" ? $0.offset : nil }
        let paired = Array(zip(appendSlots, pcm))
        guard let command2At = paired.last(where: { $0.1 == command2 })?.0,
              let firstDelayedAt = paired.first(where: { $0.1 == delayed })?.0,
              let lastDelayedAt = paired.last(where: { $0.1 == delayed })?.0
        else {
            XCTFail("queued command 2 and the think-then-talk command must both be sent")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, firstDelayedAt)
        XCTAssertGreaterThanOrEqual(
            paired.filter { $0.1 == delayed }.count,
            60,
            "must keep feeding the delayed command for ≥1.5s"
        )
        XCTAssertGreaterThanOrEqual(
            paired.filter { $0.1 == noise }.count,
            40,
            "must feed think / radio for ~1s before the delayed command"
        )
        guard let commitAt = types.firstIndex(of: "input_audio_buffer.commit") else {
            XCTFail("queued turn must close on a short quiet after flush")
            voice.cancel()
            return
        }
        XCTAssertLessThan(command2At, commitAt, "commit must follow the queued command")
        XCTAssertLessThan(
            commitAt,
            firstDelayedAt,
            "5078dff 1800ms flush-clock closed mid think-then-talk"
        )
        XCTAssertFalse(
            firstDelayedAt < commitAt && commitAt < lastDelayedAt,
            "think-then-talk after recover must not be cut mid-utterance"
        )

        await voice.waitUntilListenLoopQueuedTurnClosed()
        XCTAssertEqual(engine.startCount, 1)
        let after = voice.listenLoopDeliveredSendTypes
        XCTAssertTrue(after.contains("input_audio_buffer.commit"))

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
        XCTAssertEqual(sink.turns.last, command3)
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

    /// Broadband command tail. Mixed formants + deterministic noise.
    /// Zero-crossing is ~1.3 kHz — outside the 6264a07 120–220 Hz sine band.
    private static func mixedHarmonicSpeechPCM() -> Data {
        let seconds = 0.12
        let rate = GrokVoiceAudioEngine.sampleRate
        let count = Int(rate * seconds)
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / rate
            let harmonic =
                0.12 * sin(2 * .pi * 180 * t) +
                0.10 * sin(2 * .pi * 650 * t) +
                0.07 * sin(2 * .pi * 2200 * t) +
                0.05 * sin(2 * .pi * 3500 * t)
            let noise = Double((index * 17 + 31) % 200) / 200.0 * 0.04 - 0.02
            let value = (harmonic + noise) * Double(Int16.max)
            samples[index] = Int16(
                max(Double(Int16.min), min(Double(Int16.max), value.rounded()))
            )
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Live-tap silence: frames still arrive. RMS stays far below speech.
    private static func nearSilentPCM() -> Data {
        let count = Int(GrokVoiceAudioEngine.sampleRate * 0.04)
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            samples[index] = Int16(index.isMultiple(of: 2) ? 12 : -12)
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
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
