@preconcurrency import AVFAudio

/// Simultaneous mic capture + playback at 24 kHz PCM16.
/// Ported from xai-cookbook `VoiceAgentAudioEngine` (VoiceTesterApp).
@MainActor
final class GrokVoiceAudioEngine {
    nonisolated static let sampleRate: Double = 24_000

    nonisolated static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    var isRunning: Bool { engine?.isRunning ?? false }
    var hasPendingPlayback: Bool { pendingPlaybackBuffers > 0 }

    /// Fires on the main actor when the last scheduled desk-TTS buffer ends.
    /// `response.done` is earlier — capture often dies only after playback.
    var onPlaybackDrained: (() -> Void)?

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var onMicAudio: (@Sendable (String) -> Void)?
    private var echoCancellation = true
    private var tapInstalled = false
    private var pendingPlaybackBuffers = 0
    private var playbackEpoch = 0

    @discardableResult
    func start(echoCancellation: Bool, onMicAudio: @escaping @Sendable (String) -> Void) -> [String] {
        self.echoCancellation = echoCancellation
        self.onMicAudio = onMicAudio
        var logs: [String] = []

        do {
            let session = AVAudioSession.sharedInstance()
            let mode: AVAudioSession.Mode = echoCancellation ? .voiceChat : .default
            try session.setCategory(
                .playAndRecord,
                mode: mode,
                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
            )
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
        let sourceRate = inputFormat.sampleRate
        logs.append("Mic format: \(Int(sourceRate)) Hz")

        guard sourceRate > 0 else {
            logs.append("Mic input has zero sample rate")
            return logs
        }

        installMicTap(on: inputNode, format: inputFormat, sourceRate: sourceRate, onMicAudio: onMicAudio)
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
            player.play()
            logs.append("Audio engine running")
        } catch {
            logs.append("Engine start error: \(error.localizedDescription)")
            return logs
        }

        self.engine = engine
        self.playerNode = player
        return logs
    }

    func stop() {
        guard let engine else { return }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        playbackEpoch += 1
        pendingPlaybackBuffers = 0
        playerNode?.stop()
        if engine.isRunning { engine.stop() }
        self.engine = nil
        self.playerNode = nil
        onMicAudio = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func interruptPlayback() {
        playbackEpoch += 1
        pendingPlaybackBuffers = 0
        playerNode?.stop()
        playerNode?.play()
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
    }

    private func installMicTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        sourceRate: Double,
        onMicAudio: @escaping @Sendable (String) -> Void
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var samples = [Float](repeating: 0, count: count)
            samples.withUnsafeMutableBufferPointer { dest in
                guard let base = dest.baseAddress else { return }
                base.update(from: channel, count: count)
            }
            guard let data = Self.int16Data(samples: samples, sourceRate: sourceRate) else { return }
            onMicAudio(data.base64EncodedString())
        }
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
