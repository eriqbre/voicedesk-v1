@preconcurrency import AVFAudio
import Foundation
import VoiceDeskLogic
#if canImport(UIKit)
import UIKit
#endif

/// Simultaneous mic capture + playback at 24 kHz PCM16.
///
/// The engine repairs itself on purpose. iOS tears an `AVAudioEngine` graph
/// down for a phone call, a Bluetooth connect, a headphone unplug, a Siri
/// invocation, or a media-services reset, and every installed tap goes with
/// it. `engine.isRunning` keeps returning true afterwards, so nothing notices
/// and the user is never heard again. Each of those events is observed here
/// and repaired, and a liveness monitor catches whatever slips through by
/// watching that mic buffers actually keep arriving.
@MainActor
final class GrokVoiceAudioEngine {
    nonisolated static let sampleRate: Double = 24_000

    nonisolated static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    /// What the realtime API expects on `input_audio_buffer.append`.
    nonisolated static let captureFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: true
    )!

    /// Capture could not be repaired. Surfaced rather than leaving the user
    /// talking to a dead mic.
    var onCaptureFailure: ((String) -> Void)?

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var tap: MicFrameTap?
    private var onMicAudio: (@Sendable (String) -> Void)?
    private var echoCancellation = true

    private var recovery = MicCaptureRecovery()
    private var liveness = MicLivenessMonitor()
    private var observers: [any NSObjectProtocol] = []
    private var isRepairing = false
    private var hasReportedFailure = false
    /// Bumped on every start and stop. A deferred session deactivation from an
    /// earlier stop must not silence a session that has restarted since.
    private var generation = 0

    var isRunning: Bool { engine?.isRunning ?? false }

    /// The user asked for voice and we have not been told to stand down.
    var wantsCapture: Bool { recovery.wantsCapture }

    /// True only when the tap is attached *and* buffers are still arriving.
    /// `isRunning` alone cannot tell a live graph from a detached tap.
    var isCaptureHealthy: Bool {
        guard isRunning, liveness.isCapturing else { return false }
        syncLivenessFromTap()
        return !liveness.isStalled()
    }

    @discardableResult
    func start(echoCancellation: Bool, onMicAudio: @escaping @Sendable (String) -> Void) -> [String] {
        self.echoCancellation = echoCancellation
        self.onMicAudio = onMicAudio
        recovery.wantsCapture = true
        hasReportedFailure = false
        generation += 1
        observeAudioLifecycle()
        teardownGraph()
        return startGraph()
    }

    func stop() {
        recovery.wantsCapture = false
        onMicAudio = nil
        generation += 1
        let stopped = generation
        teardownGraph()
        liveness.captureStopped()
        removeObservers()

        // Deactivating immediately clips the tail of Eve's audio; deactivating
        // unconditionally later killed a session that had restarted in between.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, self.generation == stopped, !self.recovery.wantsCapture else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func interruptPlayback() {
        playerNode?.stop()
        // A stopped player silently drops every buffer scheduled after it.
        if isRunning { playerNode?.play() }
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
        playerNode.scheduleBuffer(buffer)
    }

    // MARK: - Health

    /// Watchdog entry point. Cheap enough to call on a short timer.
    func checkCaptureHealth() {
        guard recovery.wantsCapture else { return }
        guard liveness.isCapturing else {
            // A start that failed outright — permission granted late, session
            // busy — still has to be retried, not left silently dead.
            handle(.micFramesStalled)
            return
        }
        syncLivenessFromTap()
        guard !isRunning || liveness.isStalled() else { return }
        handle(.micFramesStalled)
    }

    private func syncLivenessFromTap() {
        guard let lastFrame = tap?.lastFrameAt else { return }
        liveness.frameArrived(at: lastFrame)
    }

    // MARK: - Lifecycle repair

    private func handle(_ event: AudioLifecycleEvent) {
        switch recovery.action(for: event) {
        case .none:
            return
        case .suspend:
            // The session is already gone; stop pretending we hold a graph.
            teardownGraph()
            liveness.captureStopped()
        case .verify:
            guard !isCaptureHealthy else { return }
            repairCapture(fullRebuild: false)
        case .restart:
            repairCapture(fullRebuild: false)
        case .rebuild:
            repairCapture(fullRebuild: true)
        }
    }

    private func repairCapture(fullRebuild: Bool) {
        guard recovery.wantsCapture, onMicAudio != nil, !isRepairing else { return }
        isRepairing = true
        defer { isRepairing = false }

        generation += 1
        teardownGraph()
        if fullRebuild {
            // The media daemon died — drop the stale session before rebuilding.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        let logs = startGraph()
        if isRunning {
            hasReportedFailure = false
        } else if !hasReportedFailure {
            hasReportedFailure = true
            onCaptureFailure?(logs.last ?? "Microphone could not be restarted")
        }
    }

    private func observeAudioLifecycle() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: nil
            ) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                Task { @MainActor in
                    guard let self, let raw,
                          let type = AVAudioSession.InterruptionType(rawValue: raw)
                    else { return }
                    switch type {
                    case .began:
                        self.handle(.interruptionBegan)
                    case .ended:
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                        self.handle(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
                    @unknown default:
                        break
                    }
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                Task { @MainActor in
                    self?.handle(.routeChanged(Self.routeReason(raw)))
                }
            }
        )

        // The graph was rebuilt underneath us; the mic tap is now detached.
        observers.append(
            center.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handle(.engineConfigurationChanged)
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handle(.mediaServicesWereReset)
                }
            }
        )

        #if canImport(UIKit)
        observers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handle(.appBecameActive)
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

    nonisolated private static func routeReason(_ raw: UInt) -> RouteChangeReason {
        switch AVAudioSession.RouteChangeReason(rawValue: raw) {
        case .newDeviceAvailable: return .newDeviceAvailable
        case .oldDeviceUnavailable: return .oldDeviceUnavailable
        case .categoryChange: return .categoryChange
        case .override: return .override
        case .wakeFromSleep: return .wakeFromSleep
        case .noSuitableRouteForCategory: return .noSuitableRouteForCategory
        case .routeConfigurationChange: return .routeConfigurationChange
        default: return .unknown
        }
    }

    // MARK: - Graph

    private func startGraph() -> [String] {
        var logs: [String] = []
        guard let onMicAudio else {
            logs.append("No mic sink")
            return logs
        }

        do {
            let session = AVAudioSession.sharedInstance()
            let mode: AVAudioSession.Mode = echoCancellation ? .voiceChat : .default
            // No `.mixWithOthers`: it downgrades the voice-processing unit,
            // which is what keeps Eve's own audio out of the mic.
            // `.allowBluetoothA2DP` is output-only, so a headset's mic was
            // never reachable — `.allowBluetooth` is what enables HFP input.
            try session.setCategory(
                .playAndRecord,
                mode: mode,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
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

        if echoCancellation {
            do {
                try engine.inputNode.setVoiceProcessingEnabled(true)
                engine.inputNode.isVoiceProcessingAGCEnabled = true
                engine.inputNode.isVoiceProcessingBypassed = false
                logs.append("Voice processing enabled")
            } catch {
                logs.append("Voice processing failed: \(error.localizedDescription)")
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

        do {
            engine.prepare()
            try engine.start()
            player.play()
            logs.append("Audio engine running")
        } catch {
            inputNode.removeTap(onBus: 0)
            frameTap.detach()
            logs.append("Engine start error: \(error.localizedDescription)")
            return logs
        }

        self.engine = engine
        self.playerNode = player
        self.tap = frameTap
        liveness.captureStarted()
        return logs
    }

    private func teardownGraph() {
        tap?.detach()
        tap = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            playerNode?.stop()
            if engine.isRunning { engine.stop() }
        }
        engine = nil
        playerNode = nil
    }
}

/// Converts mic buffers to 24 kHz PCM16 on the realtime audio thread and
/// records when the last one arrived.
///
/// `@unchecked Sendable`: the tap callback runs off the main actor, so the
/// converter and the timestamp are lock-protected. `AVAudioConverter` replaces
/// hand-rolled linear interpolation, which aliased badly downsampling 48 kHz
/// hardware to 24 kHz and left server-side VAD missing quiet speech.
private final class MicFrameTap: @unchecked Sendable {
    /// Read from the main actor by the liveness watchdog.
    var lastFrameAt: Date? {
        lock.lock()
        defer { lock.unlock() }
        return storedLastFrameAt
    }

    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private let ratio: Double
    private var onFrame: (@Sendable (String) -> Void)?
    private var storedLastFrameAt: Date?

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

    /// Stop emitting immediately. Removing a tap can race one last callback.
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
        if data != nil { storedLastFrameAt = Date() }
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

        guard status != .error, output.frameLength > 0,
              let channel = output.int16ChannelData?[0]
        else { return nil }

        return Data(bytes: channel, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }
}
