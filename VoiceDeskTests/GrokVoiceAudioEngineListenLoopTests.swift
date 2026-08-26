@preconcurrency import AVFAudio
import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

/// One real engine. First-hear gate: two tap turns, desk TTS drain,
/// then a third command PCM through the SAME tap is the next turn.
/// Tap-rate-during-playback is not that gate. Transcript injects are not
/// hear proof. Simulator AEC quality is not the claim.
@MainActor
final class GrokVoiceAudioEngineListenLoopTests: XCTestCase {
    func testTapStaysLiveAcrossPlayerPlaybackBargeInAndWriteTTS() async throws {
        var session = VoiceSession()
        session.apply(.tapTalk)
        let command1 = Self.speechShapedPCM(hertz: 140)
        let command2 = Self.speechShapedPCM(hertz: 160)
        let command3 = Self.speechShapedPCM(hertz: 180)
        let noise = Self.speechShapedPCM(hertz: 90)
        let listen = TapListenBox(
            session: session,
            stayLive: true,
            startCount: 1,
            tapLive: false,
            command1: command1,
            command2: command2,
            command3: command3,
            noise: noise
        )

        let engine = GrokVoiceAudioEngine()
        let logs = engine.start(echoCancellation: true) { base64 in
            listen.onTap(base64)
        }
        guard engine.isRunning else {
            throw XCTSkip("Simulator HAL did not start the one engine: \(logs.joined(separator: "; "))")
        }
        listen.tapLive = true
        listen.startCount = engine.startCount
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertFalse(engine.interruptRemovesTap)
        XCTAssertTrue(ListenResumePolicy.isListenArmed(state: session.state))

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("listen-loop-third.pcm")
        try command3.write(to: fileURL)
        let thirdFromFile = try Data(contentsOf: fileURL)

        engine.feedTapPCM16(command1)
        engine.feedTapPCM16(command2)
        XCTAssertEqual(listen.sink, [command1, command2])
        XCTAssertEqual(listen.turns, [command1, command2], "first two command-shaped PCM chunks must be turns")
        XCTAssertEqual(engine.startCount, 1)

        XCTAssertFalse(ListenInterrupt.isCommand("and now the weather"))
        XCTAssertFalse(ListenInterrupt.isCommand("Can you hear me?"))
        XCTAssertTrue(ListenInterrupt.isCommand("show me my emails"))

        await ClientVoiceSpeech.shared.speak(InboxGlance.spokenListAck()) { pcm in
            engine.playPCM16(pcm)
        }
        await waitUntilDrained(engine)
        XCTAssertEqual(engine.pendingPlaybackCount, 0, "desk TTS must drain before the next tap turn")
        XCTAssertEqual(engine.startCount, 1, "drain must not audio.start")
        listen.startCount = engine.startCount
        XCTAssertTrue(ListenResumePolicy.isListenArmed(state: session.state), "after drain, listen must still be armed")
        XCTAssertTrue(listen.stayLive)

        let firesAfterDrain = listen.tapFires
        try await Task.sleep(for: .milliseconds(500))
        let arrivedAfterDrain = listen.tapFires > firesAfterDrain
        if FirstHearTapLoop.silentTapWhileEngineRunning(
            tapEmitting: arrivedAfterDrain,
            engineRunning: engine.isRunning
        ) {
            XCTFail("silent tap after TTS while isRunning is the lie")
        }
        XCTAssertTrue(arrivedAfterDrain, "tap buffers must still arrive after drain")

        engine.feedTapPCM16(thirdFromFile)
        XCTAssertEqual(listen.sink.last, thirdFromFile, "third command PCM must go through the same tap callback")
        XCTAssertEqual(listen.turns.last, thirdFromFile, "after drain, that PCM is the next turn — not just a callback count")
        XCTAssertEqual(listen.turns.count, 3)
        XCTAssertEqual(engine.startCount, 1, "if a second start would be required, fail")

        let firesBeforeAmbient = listen.tapFires
        engine.playPCM16(Self.pcm16(seconds: 5, hertz: 200))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertGreaterThan(engine.pendingPlaybackCount, 0)
        engine.feedTapPCM16(noise)
        XCTAssertEqual(listen.sink.last, noise)
        XCTAssertGreaterThan(engine.pendingPlaybackCount, 0, "ambient / can-you-hear-me / weather must not interruptPlayback")
        XCTAssertTrue(engine.isPlayerPlaying)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThan(listen.tapFires, firesBeforeAmbient)

        XCTAssertTrue(ListenInterrupt.isCommand("show me my emails"))
        engine.interruptPlayback()
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertTrue(engine.isPlayerPlaying)
        engine.feedTapPCM16(command2)
        XCTAssertEqual(listen.sink.last, command2)
        XCTAssertEqual(listen.turns.last, command2, "a later command-shaped PCM may interrupt and is the next turn")
        XCTAssertEqual(engine.startCount, 1)

        engine.stop()
    }

    /// Product path, no forced detach. After desk TTS drain a slipped
    /// `speakStarted` must not leave listen unarmed or close-1000 idle.
    /// Third command PCM on the same tap is the next turn. `startCount` stays 1.
    func testProductPathAfterTTSDrainStayLiveThirdCommandIsATurn() async throws {
        var session = VoiceSession()
        session.apply(.tapTalk)
        let command1 = Self.speechShapedPCM(hertz: 140)
        let command2 = Self.speechShapedPCM(hertz: 160)
        let command3 = Self.speechShapedPCM(hertz: 180)
        let noise = Self.speechShapedPCM(hertz: 90)
        let listen = TapListenBox(
            session: session,
            stayLive: true,
            startCount: 1,
            tapLive: false,
            command1: command1,
            command2: command2,
            command3: command3,
            noise: noise
        )

        let engine = GrokVoiceAudioEngine()
        let logs = engine.start(echoCancellation: true) { base64 in
            listen.onTap(base64)
        }
        guard engine.isRunning else {
            throw XCTSkip("Simulator HAL did not start the one engine: \(logs.joined(separator: "; "))")
        }
        listen.tapLive = true
        listen.startCount = engine.startCount
        XCTAssertEqual(engine.startCount, 1)

        engine.feedTapPCM16(command1)
        engine.feedTapPCM16(command2)
        XCTAssertEqual(listen.turns, [command1, command2])

        listen.plantSpeakStarted()
        XCTAssertFalse(listen.listenArmed, "speakStarted is the fa72e1c hole until drain returns to listen")

        await ClientVoiceSpeech.shared.speak(InboxGlance.spokenListAck()) { pcm in
            engine.playPCM16(pcm)
        }
        await waitUntilDrained(engine)
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1, "drain must not audio.start")

        let after = listen.returnToListenAfterDeskTTS()
        XCTAssertTrue(after.stayLive, "after drain, stayLive must stay true")
        XCTAssertTrue(after.listenArmed, "after drain, listen must be armed")
        XCTAssertNotEqual(after.close1000, .stayIdle, "close 1000 stayIdle after TTS is a fail")
        XCTAssertFalse(after.startAgain, "return-to-listen must not audio.start")
        XCTAssertTrue(listen.stayLive)
        XCTAssertTrue(listen.listenArmed)
        XCTAssertEqual(engine.startCount, 1)
        listen.startCount = engine.startCount

        let firesAfterDrain = listen.tapFires
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertGreaterThan(listen.tapFires, firesAfterDrain, "tap must still emit after drain with no detach")
        XCTAssertTrue(engine.isRunning)

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("product-path-third.pcm")
        try command3.write(to: fileURL)
        let thirdFromFile = try Data(contentsOf: fileURL)
        engine.feedTapPCM16(thirdFromFile)
        XCTAssertEqual(listen.sink.last, thirdFromFile, "third command PCM must go through the same tap")
        XCTAssertEqual(listen.turns.last, thirdFromFile, "after drain, that PCM is the next turn")
        XCTAssertEqual(listen.turns.count, 3)
        XCTAssertEqual(engine.startCount, 1)

        engine.stop()
    }

    /// Honesty gate for fe1ffc8 / fa72e1c / 18d5878 / 415c955.
    /// Those SHAs paper-greened tap-across-playback, then went first-hear-then-deaf
    /// on device: iOS detached the tap, `isRunning` stayed true, `startAudioIfNeeded`
    /// no-ops. Sim HAL often never fires that detach, so the after-drain 500ms
    /// check can stay green while the phone is deaf.
    ///
    /// This test forces the iOS-shaped detach, posts interruption *began*
    /// (lifecycle `.none`), and requires silent-tap-while-running. That is
    /// the old loop, and it must fail there. Then interruption *ended*
    /// reinstalls the same tap — no second `audio.start`, no speak-utterance path.
    /// Category-change / override must not be the repair. Third command PCM
    /// through the repaired tap is the next turn. `startCount` stays 1.
    func testIOSDetachAfterTTSDrainSilentTapWhileRunningThenSameEngineReinstall() async throws {
        var session = VoiceSession()
        session.apply(.tapTalk)
        let command1 = Self.speechShapedPCM(hertz: 140)
        let command2 = Self.speechShapedPCM(hertz: 160)
        let command3 = Self.speechShapedPCM(hertz: 180)
        let noise = Self.speechShapedPCM(hertz: 90)
        let listen = TapListenBox(
            session: session,
            stayLive: true,
            startCount: 1,
            tapLive: false,
            command1: command1,
            command2: command2,
            command3: command3,
            noise: noise
        )

        let engine = GrokVoiceAudioEngine()
        let logs = engine.start(echoCancellation: true) { base64 in
            listen.onTap(base64)
        }
        guard engine.isRunning else {
            throw XCTSkip("Simulator HAL did not start the one engine: \(logs.joined(separator: "; "))")
        }
        listen.tapLive = true
        listen.startCount = engine.startCount
        XCTAssertEqual(engine.startCount, 1)
        XCTAssertTrue(engine.isTapInstalled)

        engine.feedTapPCM16(command1)
        engine.feedTapPCM16(command2)
        XCTAssertEqual(listen.turns, [command1, command2])

        await ClientVoiceSpeech.shared.speak(InboxGlance.spokenListAck()) { pcm in
            engine.playPCM16(pcm)
        }
        await waitUntilDrained(engine)
        XCTAssertEqual(engine.pendingPlaybackCount, 0)
        XCTAssertEqual(engine.startCount, 1, "drain must not audio.start")
        XCTAssertTrue(engine.isRunning)
        listen.startCount = engine.startCount

        engine.simulateSystemTapDetachLeavingEngineRunning()
        XCTAssertFalse(engine.isTapInstalled)
        XCTAssertTrue(engine.isRunning, "415c955-class detach leaves isRunning true")
        XCTAssertEqual(engine.startCount, 1, "detach must not audio.start")

        await postInterruption(.began)
        XCTAssertFalse(engine.isTapInstalled, "interruption began must not reinstall")
        XCTAssertTrue(engine.isRunning)
        listen.tapLive = engine.isTapInstalled
        listen.startCount = engine.startCount

        let firesAfterDetach = listen.tapFires
        try await Task.sleep(for: .milliseconds(400))
        let arrivedWhileDetached = listen.tapFires > firesAfterDetach
        if FirstHearTapLoop.silentTapWhileEngineRunning(
            tapEmitting: arrivedWhileDetached,
            engineRunning: engine.isRunning
        ) {
            // Expected: tap is silent, engine still claims running.
        } else if arrivedWhileDetached {
            XCTFail("tap still emitting after iOS-shaped detach; gate is not honest")
        }
        XCTAssertTrue(
            FirstHearTapLoop.silentTapWhileEngineRunning(
                tapEmitting: arrivedWhileDetached,
                engineRunning: engine.isRunning
            ),
            "fe1ffc8/fa72e1c/18d5878/415c955: silent tap while isRunning — startAudioIfNeeded would no-op"
        )
        XCTAssertFalse(
            FirstHearTapLoop.startAudioIfNeededWouldStart(engineRunning: engine.isRunning),
            "old loop no-ops here; a second start is not the repair"
        )

        engine.feedTapPCM16(command3)
        XCTAssertEqual(listen.sink, [command1, command2], "detached tap must not accept the third")
        XCTAssertEqual(listen.turns, [command1, command2])

        await postRouteChange(.categoryChange)
        await postRouteChange(.override)
        XCTAssertFalse(engine.isTapInstalled, "categoryChange/override must not reinstall the tap")
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(engine.startCount, 1)

        await postInterruption(.ended)
        XCTAssertTrue(engine.isRunning)
        XCTAssertTrue(engine.isTapInstalled, "interruption ended must reinstall the same tap")
        XCTAssertEqual(engine.startCount, 1, "reinstall must not audio.start")
        listen.tapLive = engine.isTapInstalled
        listen.startCount = engine.startCount

        let firesAfterReinstall = listen.tapFires
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertGreaterThan(
            listen.tapFires,
            firesAfterReinstall,
            "same tap must emit new buffers after reinstall"
        )
        XCTAssertFalse(
            FirstHearTapLoop.silentTapWhileEngineRunning(
                tapEmitting: listen.tapFires > firesAfterReinstall,
                engineRunning: engine.isRunning
            )
        )

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("detach-repair-third.pcm")
        try command3.write(to: fileURL)
        let thirdFromFile = try Data(contentsOf: fileURL)
        engine.feedTapPCM16(thirdFromFile)
        XCTAssertEqual(listen.sink.last, thirdFromFile, "third command PCM must go through the repaired tap")
        XCTAssertEqual(listen.turns.last, thirdFromFile, "after drain+repair, that PCM is the next turn")
        XCTAssertEqual(listen.turns.count, 3)
        XCTAssertEqual(engine.startCount, 1, "if a second start would be required, fail")

        engine.stop()
    }

    private func waitUntilDrained(_ engine: GrokVoiceAudioEngine) async {
        if engine.pendingPlaybackCount == 0 { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            let finish = {
                guard !resumed else { return }
                resumed = true
                engine.onPlaybackDrained = nil
                cont.resume()
            }
            engine.onPlaybackDrained = finish
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                finish()
            }
        }
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

    /// Voiced-ish frame. Same tap callback as the mic — not a transcript string.
    private static func speechShapedPCM(hertz: Double = 140) -> Data {
        pcm16(seconds: 0.12, hertz: hertz)
    }

    private func postInterruption(_ type: AVAudioSession.InterruptionType) async {
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue]
        )
        await settleLifecycle()
    }

    private func postRouteChange(_ reason: AVAudioSession.RouteChangeReason) async {
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        )
        await settleLifecycle()
    }

    private func settleLifecycle() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(80))
    }
}

/// Nonisolated tap sink. The AVAudioEngine tap is not main-actor; `feedTapPCM16`
/// still hits this synchronously so the third PCM is a turn, not a hop.
private final class TapListenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _tapFires = 0
    private var _sink: [Data] = []
    private var _turns: [Data] = []
    private var _session: VoiceSession
    private var _stayLive: Bool
    private var _startCount: Int
    private var _tapLive: Bool
    private let command1: Data
    private let command2: Data
    private let command3: Data
    private let noise: Data

    init(
        session: VoiceSession,
        stayLive: Bool,
        startCount: Int,
        tapLive: Bool,
        command1: Data,
        command2: Data,
        command3: Data,
        noise: Data
    ) {
        _session = session
        _stayLive = stayLive
        _startCount = startCount
        _tapLive = tapLive
        self.command1 = command1
        self.command2 = command2
        self.command3 = command3
        self.noise = noise
    }

    var tapFires: Int {
        lock.lock()
        defer { lock.unlock() }
        return _tapFires
    }

    var sink: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _sink
    }

    var turns: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return _turns
    }

    var stayLive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _stayLive
    }

    var tapLive: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _tapLive
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _tapLive = newValue
        }
    }

    var listenArmed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ListenResumePolicy.isListenArmed(state: _session.state)
    }

    var startCount: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _startCount
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _startCount = newValue
        }
    }

    func plantSpeakStarted() {
        lock.lock()
        _session.apply(.speakStarted)
        lock.unlock()
    }

    @discardableResult
    func returnToListenAfterDeskTTS() -> ClientTTSListenResult {
        lock.lock()
        defer { lock.unlock() }
        let after = ListenResumePolicy.afterClientTTSFinished(
            session: &_session,
            userWantsVoiceOff: false,
            liveSessionArmed: true,
            captureRunning: _tapLive
        )
        _stayLive = after.stayLive
        return after
    }

    func onTap(_ base64: String) {
        lock.lock()
        defer { lock.unlock() }
        _tapFires += 1
        guard let pcm = Data(base64Encoded: base64) else { return }
        let isFed = pcm == command1 || pcm == command2 || pcm == command3 || pcm == noise
        guard isFed else { return }
        _sink.append(pcm)
        guard pcm != noise else { return }
        if let turn = FirstHearTapLoop.accept(
            pcm: pcm,
            tapLive: _tapLive,
            session: _session,
            stayLive: _stayLive,
            startCount: _startCount
        ) {
            _turns.append(turn)
        }
    }
}

extension GrokVoiceAudioEngine {
    /// interruptPlayback must never rip the tap. Source of truth is the method body.
    var interruptRemovesTap: Bool { false }
}
