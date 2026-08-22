import AVFoundation
import Foundation
import Observation
import VoiceDeskLogic

@MainActor
protocol VoiceServicing: AnyObject {
    var state: VoiceState { get }
    var backendLabel: String { get }
    func startListening() async -> String
    func speak(_ text: String) async
    func cancel()
}

enum VoiceRuntime {
    @MainActor
    static func makeService() -> MockVoiceService {
        if VoiceDeskSecrets.xaiAPIKey != nil {
            return MockVoiceService(
                label: "Mock loop · XAI_API_KEY is set; Grok realtime still TODO"
            )
        }
        return MockVoiceService(label: "Mock voice · set XAI_API_KEY to unlock Grok")
    }
}

/// Speaks and listens with timed UI states so the conversation shell is demoable
/// without a device key or live audio. Replace calls inside with `LiveGrokVoiceClient`.
@MainActor
@Observable
final class MockVoiceService: VoiceServicing {
    private var session = VoiceSession()
    let backendLabel: String
    let instant: Bool

    var state: VoiceState { session.state }

    init(label: String, instant: Bool = false) {
        self.backendLabel = label
        self.instant = instant
    }

    func startListening() async -> String {
        session.apply(.cancel)
        if !instant {
            await requestMicrophone()
        }
        session.apply(.tapTalk)
        if !instant {
            try? await Task.sleep(for: .milliseconds(1300))
            guard session.state == .listening else { return "" }
        }
        session.apply(.listenFinished)
        return ""
    }

    func speak(_ text: String) async {
        session.apply(.speakStarted)
        if !instant {
            let milliseconds = min(4200, max(800, text.count * 28))
            try? await Task.sleep(for: .milliseconds(milliseconds))
        }
        if session.state == .speaking {
            session.apply(.speakFinished)
        }
    }

    func cancel() {
        session.apply(.cancel)
    }

    private func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }
}
