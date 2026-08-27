@preconcurrency import AVFAudio
import Foundation
import VoiceDeskLogic
#if canImport(UIKit)
import UIKit
#endif

/// Simultaneous mic capture + playback at 24 kHz PCM16.
/// Liveness is buffer arrival. `isRunning` can stay true after the tap dies.
@MainActor
final class GrokVoiceAudioEngine {
    nonisolated static let sampleRate: Double = 24_000

    nonisolated static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    nonisolated static let captureFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: true
    )!

    var isRunning: Bool { engine?.isRunning ?? false }
    var hasPendingPlayback: Bool { pendingPlaybackBuffers > 0 }
    var pendingPlaybackCount: Int { pendingPlaybackBuffers }
    var isPlayerPlaying: Bool { playerNode?.isPlaying ?? false }
    private(set) var startCount = 0

    /// Fires on the main actor when the last scheduled desk-TTS buffer ends.
    var onPlaybackDrained: (() -> Void)?

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var tap: MicFrameTap?
    private var onMicAudio: (@Sendable (String) -> Void)?
    private var echoCancellation = true
    private var tapInstalled = false
    /// SET only when we `removeTap` keeping the Swift object. Cleared
    /// on leftover-safe install/reinstall/teardown. Not on leftover-hot
    /// feed. A leftover-hot install-block token raced leftover composed
    /// (6483513 55s, created!=scheduled, deltas=0).
    private var removedHALKeepingObject = false
    private var pendingPlaybackBuffers = 0
    private(set) var playbackEpoch = 0
    private var wantsCapture = false
    private var isInterrupted = false
    private var observers: [any NSObjectProtocol] = []

    @discardableResult
    func start(echoCancellation: Bool, onMicAudio: @escaping @Sendable (String) -> Void) -> [String] {
        self.echoCancellation = echoCancellation
        self.onMicAudio = onMicAudio
        wantsCapture = true
        startCount += 1
        observeAudioLifecycle()
        teardownGraph()
        return startGraph()
    }

    func stop() {
        wantsCapture = false
        onMicAudio = nil
        teardownGraph()
        removeObservers()
        // Do not defer session teardown. 415c955 delayed deactivate
        // muted a live session after write→player (tap stayed,
        // startCount stayed 1, third PCM was zeros). Best part is
        // no part — no recover path.
    }

    func interruptPlayback() {
        playbackEpoch += 1
        pendingPlaybackBuffers = 0
        playerNode?.stop()
        playerNode?.play()
    }

    /// Same callback the mic tap uses. Speech-shaped PCM is a turn, not a string.
    /// This guard is 453bda8 — leftover barge / tape feeds live here.
    /// Do not check HAL-install release on this path (12ba20f 97s).
    func feedTapPCM16(_ pcm: Data) {
        guard tap != nil, tapInstalled, let onMicAudio else { return }
        onMicAudio(pcm.base64EncodedString())
    }

    var isTapInstalled: Bool { tapInstalled }

    /// Phone HAL yank leaves this true. `simulateHALTapYankLeavingInstalledFlagTrue` nils it.
    var isTapObjectPresent: Bool { tap != nil }

    /// False after we removeTap keeping the object, until demand repair.
    var isHALTapAttached: Bool { tap != nil && tapInstalled && !removedHALKeepingObject }

    /// After write→player drain. iOS can yank the HAL tap and leave
    /// `isRunning` true and `tapInstalled` true without posting
    /// interruption. Put the same tap back. Do not increment `startCount`.
    func reinstallTapIfSilentWhileRunning() {
        guard FirstHearTapLoop.shouldReinstallTapIfSilentWhileRunning(
            engineRunning: engine?.isRunning ?? false,
            wantsCapture: wantsCapture
        ) else { return }
        reinstallTap()
    }

    /// Zero-notification HAL yank. `tap == nil` or object-left-in-place
    /// (`tap` still there, HAL gone). Demand-driven: first feed stays
    /// deaf, then this puts the same tap back. Do not tear down a live
    /// HAL tap. Do not increment `startCount`. Not a 400ms Task.
    func reinstallTapIfYankedWhileRunning() {
        guard FirstHearTapLoop.shouldApplyDelayedSilentTapRepair(
            engineRunning: engine?.isRunning ?? false,
            wantsCapture: wantsCapture,
            tapObjectMissing: tap == nil,
            halTapMissing: removedHALKeepingObject
        ) else { return }
        reinstallTap()
    }

    /// Sim HAL often leaves the tap up when we only post a session event.
    /// Real iOS (fe1ffc8 / fa72e1c / 18d5878 / 415c955) yanks the tap and
    /// leaves `engine.isRunning` true, so `startAudioIfNeeded` no-ops.
    /// This is that detach. It must not increment `startCount`.
    func simulateSystemTapDetachLeavingEngineRunning() {
        guard let engine else { return }
        if tap != nil {
            engine.inputNode.removeTap(onBus: 0)
        }
        tapInstalled = false
        tap?.detach()
        tap = nil
        removedHALKeepingObject = false
    }

    /// Real iOS (415c955 / bf0af19): HAL tap is gone, `isRunning` stays
    /// true, and our installed flag still says true. No interruption.
    /// This inject nils the Swift object. Phone yank does not.
    func simulateHALTapYankLeavingInstalledFlagTrue() {
        guard let engine else { return }
        if tap != nil {
            engine.inputNode.removeTap(onBus: 0)
        }
        tap?.detach()
        tap = nil
        removedHALKeepingObject = false
    }

    /// Phone HAL yank (415c955 / 18d5878): HAL tap is gone, Swift
    /// `tap` stays, `tapInstalled` stays true, `isRunning` stays true.
    /// Zero notifications. `removeTap` only — do not nil the object,
    /// do not clear `tapInstalled`. We just removed the HAL tap, so
    /// demand repair can see it. Do not auto-reinstall. Not a leftover-hot
    /// install-block witness.
    func simulateHALTapYankLeavingSwiftObjectInPlace() {
        guard let engine else { return }
        if tap != nil {
            engine.inputNode.removeTap(onBus: 0)
            removedHALKeepingObject = true
        }
    }

    func playAudioDelta(base64: String) {
        guard let audioData = Data(base64Encoded: base64) else { return }
        playPCM16(audioData)
    }

    func playPCM16(_ audioData: Data) {
        guard let playerNode,
              let engine, engine.isRunning
        else { return }

        let frameCount = audioData.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: UInt32(frameCount)),
              let floats = buffer.floatChannelData?[0]
        else { return }

        buffer.frameLength = UInt32(frameCount)
        audioData.withUnsafeBytes { raw in
            guard let src = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for index in 0..<frameCount {
                floats[index] = Float(src[index]) / Float(Int16.max)
            }
        }
        let epoch = playbackEpoch
        pendingPlaybackBuffers += 1
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self, epoch == self.playbackEpoch else { return }
                self.pendingPlaybackBuffers = max(0, self.pendingPlaybackBuffers - 1)
                if self.pendingPlaybackBuffers == 0 {
                    self.onPlaybackDrained?()
                }
            }
        }
        playerNode.play()
    }

    private func applyLifecycle(_ event: AudioTapLifecycle.Event) {
        switch AudioTapLifecycle.action(for: event, wantsCapture: wantsCapture, isInterrupted: &isInterrupted) {
        case .none:
            return
        case .reinstallTap:
            reinstallTap()
        case .rebuildGraph:
            teardownGraph()
            _ = startGraph()
        }
    }

    private func startGraph() -> [String] {
        var logs: [String] = []
        guard let onMicAudio else {
            logs.append("No mic sink")
            return logs
        }

        do {
            let session = AVAudioSession.sharedInstance()
            let mode: AVAudioSession.Mode = echoCancellation ? .voiceChat : .default
            try session.setCategory(
                .playAndRecord,
                mode: mode,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try? session.setPreferredSampleRate(Self.sampleRate)
            try? session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true)
            logs.append("Audio session active")
        } catch {
            logs.append("Audio session error: \(error.localizedDescription)")
            return logs
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: Self.outputFormat)

        // voiceChat without this is NOT AEC. Enable while the new engine
        // is stopped, before installTap / start. WWDC 2019/2023.
        if echoCancellation {
            if engine.isRunning {
                logs.append("Voice processing skipped: engine already running")
            } else {
                do {
                    try engine.inputNode.setVoiceProcessingEnabled(true)
                    engine.inputNode.isVoiceProcessingAGCEnabled = true
                    engine.inputNode.isVoiceProcessingBypassed = false
                    logs.append("Voice processing enabled while stopped")
                } catch {
                    logs.append("Voice processing failed: \(error.localizedDescription)")
                }
            }
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        logs.append("Mic format: \(Int(inputFormat.sampleRate)) Hz")

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            logs.append("Mic input has zero sample rate")
            return logs
        }

        guard let frameTap = MicFrameTap(
            inputFormat: inputFormat,
            targetFormat: Self.captureFormat,
            onFrame: onMicAudio
        ) else {
            logs.append("Mic converter unavailable for \(Int(inputFormat.sampleRate)) Hz")
            return logs
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [frameTap] buffer, _ in
            frameTap.consume(buffer)
        }
        tapInstalled = true
        removedHALKeepingObject = false

        do {
            engine.prepare()
            try engine.start()
            player.play()
            logs.append("Audio engine running")
        } catch {
            inputNode.removeTap(onBus: 0)
            frameTap.detach()
            tapInstalled = false
            logs.append("Engine start error: \(error.localizedDescription)")
            return logs
        }

        self.engine = engine
        self.playerNode = player
        self.tap = frameTap
        return logs
    }

    private func reinstallTap() {
        guard let engine, let onMicAudio, engine.isRunning else {
            return
        }
        if tap != nil {
            engine.inputNode.removeTap(onBus: 0)
        }
        tapInstalled = false
        tap?.detach()
        tap = nil
        removedHALKeepingObject = false
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let frameTap = MicFrameTap(
                inputFormat: inputFormat,
                targetFormat: Self.captureFormat,
                onFrame: onMicAudio
              )
        else { return }
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [frameTap] buffer, _ in
            frameTap.consume(buffer)
        }
        tap = frameTap
        tapInstalled = true
    }

    private func teardownGraph() {
        tap?.detach()
        tap = nil
        if let engine {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            playerNode?.stop()
            if engine.isRunning { engine.stop() }
        }
        self.engine = nil
        self.playerNode = nil
        tapInstalled = false
        removedHALKeepingObject = false
    }

    private func observeAudioLifecycle() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                Task { @MainActor in
                    guard let self, let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                    switch type {
                    case .began:
                        self.applyLifecycle(.interruptionBegan)
                    case .ended:
                        self.applyLifecycle(.interruptionEnded)
                    @unknown default:
                        break
                    }
                }
            }
        )

        observers.append(
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
                Task { @MainActor in
                    switch reason {
                    case .categoryChange, .override, .routeConfigurationChange:
                        self?.applyLifecycle(.routeCategoryOrOverride)
                    default:
                        self?.applyLifecycle(.routeDeviceChanged)
                    }
                }
            }
        )

        // Official rebuild. TTS drain is not a rebuild.
        observers.append(
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.applyLifecycle(.engineConfigurationChanged)
                }
            }
        )

        observers.append(
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.applyLifecycle(.mediaServicesWereReset)
                }
            }
        )

        #if canImport(UIKit)
        observers.append(
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.applyLifecycle(.appBecameActive)
                }
            }
        )
        #endif
    }

    private func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// Convert already-copied floats. Callers must copy off `AVAudioPCMBuffer` first.
    nonisolated static func int16Data(samples: [Float], sourceRate: Double) -> Data? {
        guard !samples.isEmpty else { return nil }
        let targetRate = sampleRate
        let floats: [Float]
        if abs(sourceRate - targetRate) < 0.5 {
            floats = samples
        } else {
            let ratio = targetRate / sourceRate
            let newCount = max(1, Int((Double(samples.count) * ratio).rounded()))
            var resampled = [Float](repeating: 0, count: newCount)
            let last = samples.count - 1
            for index in 0..<newCount {
                let src = Double(index) / ratio
                let left = min(Int(src), last)
                let right = min(left + 1, last)
                let frac = Float(src - Double(left))
                resampled[index] = samples[left] + (samples[right] - samples[left]) * frac
            }
            floats = resampled
        }
        var packed = [Int16](repeating: 0, count: floats.count)
        for index in floats.indices {
            let clipped = max(-1, min(1, floats[index]))
            packed[index] = Int16(clipped * Float(Int16.max))
        }
        return packed.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

/// AVAudioConverter on the tap thread. Homemade linear 48→24 aliased.
private final class MicFrameTap: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private let ratio: Double
    private var onFrame: (@Sendable (String) -> Void)?

    init?(
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat,
        onFrame: @escaping @Sendable (String) -> Void
    ) {
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return nil }
        self.converter = converter
        self.targetFormat = targetFormat
        self.ratio = targetFormat.sampleRate / inputFormat.sampleRate
        self.onFrame = onFrame
    }

    func detach() {
        lock.lock()
        onFrame = nil
        lock.unlock()
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        lock.lock()
        guard let sink = onFrame else {
            lock.unlock()
            return
        }
        let data = convertLocked(buffer)
        lock.unlock()
        guard let data, !data.isEmpty else { return }
        sink(data.base64EncodedString())
    }

    private func convertLocked(_ buffer: AVAudioPCMBuffer) -> Data? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }
        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0, let channel = output.int16ChannelData?[0] else {
            return nil
        }
        return Data(bytes: channel, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }
}
