import AVFoundation

/// Simultaneous mic capture + playback at 24 kHz PCM16.
/// Ported from xai-cookbook `VoiceAgentAudioEngine` (VoiceTesterApp).
@MainActor
final class GrokVoiceAudioEngine {
    static let sampleRate: Double = 24_000
    static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    var isRunning: Bool { engine?.isRunning ?? false }

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    @discardableResult
    func start(echoCancellation: Bool, onMicAudio: @escaping @Sendable (String) -> Void) -> [String] {
        var logs: [String] = []

        do {
            let session = AVAudioSession.sharedInstance()
            let mode: AVAudioSession.Mode = echoCancellation ? .voiceChat : .default
            try session.setCategory(.playAndRecord, mode: mode, options: [.defaultToSpeaker, .allowBluetoothA2DP])
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

        guard inputFormat.sampleRate > 0 else {
            logs.append("Mic input has zero sample rate")
            return logs
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let data = Self.resampleToInt16(buffer: buffer, inputFormat: inputFormat) else { return }
            onMicAudio(data.base64EncodedString())
        }

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
        engine.inputNode.removeTap(onBus: 0)
        playerNode?.stop()
        if engine.isRunning { engine.stop() }
        self.engine = nil
        self.playerNode = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func interruptPlayback() {
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
        playerNode.scheduleBuffer(buffer)
    }

    nonisolated static func resampleToInt16(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) -> Data? {
        let targetRate = sampleRate
        let sourceBuffer: AVAudioPCMBuffer
        if inputFormat.sampleRate != targetRate {
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetRate,
                channels: 1,
                interleaved: true
            ),
                let converter = AVAudioConverter(from: inputFormat, to: format)
            else { return nil }
            let newCount = AVAudioFrameCount(Double(buffer.frameLength) * targetRate / inputFormat.sampleRate)
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: newCount) else { return nil }
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                status.pointee = .haveData
                return buffer
            }
            if error != nil { return nil }
            sourceBuffer = converted
        } else {
            sourceBuffer = buffer
        }

        guard let floats = sourceBuffer.floatChannelData?[0] else { return nil }
        let count = Int(sourceBuffer.frameLength)
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let clipped = max(-1, min(1, floats[index]))
            samples[index] = Int16(clipped * Float(Int16.max))
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
