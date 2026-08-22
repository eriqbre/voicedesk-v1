import AVFoundation
import Foundation
import Observation

enum VoiceState: String, Hashable {
    case idle
    case listening
    case thinking
    case speaking
}

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
    private(set) var state: VoiceState = .idle
    let backendLabel: String

    init(label: String) {
        self.backendLabel = label
    }

    func startListening() async -> String {
        cancel()
        await requestMicrophone()
        state = .listening
        try? await Task.sleep(for: .milliseconds(1300))
        guard state == .listening else { return "" }
        state = .thinking
        try? await Task.sleep(for: .milliseconds(350))
        return ""
    }

    func speak(_ text: String) async {
        state = .speaking
        let milliseconds = min(4200, max(800, text.count * 28))
        try? await Task.sleep(for: .milliseconds(milliseconds))
        if state == .speaking {
            state = .idle
        }
    }

    func cancel() {
        if state != .idle {
            state = .idle
        }
    }

    private func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }
}
