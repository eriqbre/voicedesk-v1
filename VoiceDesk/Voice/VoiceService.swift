import AVFoundation
import Foundation
import Observation
import VoiceDeskLogic

enum VoiceServiceEvent: Sendable {
    case state(VoiceState)
    case userTranscript(String, isFinal: Bool, itemID: String?)
    case assistantTranscript(String, isFinal: Bool)
    case failed(String)
    case recovered
    case setupRequired
}

struct VoiceTranscript: Sendable {
    enum Role: Sendable {
        case user
        case assistant
    }

    var role: Role
    var text: String
    var isFinal: Bool
    var itemID: String?
}

@MainActor
protocol VoiceServicing: AnyObject {
    var state: VoiceState { get }
    var backendLabel: String { get }
    var isInstant: Bool { get }
    var needsCredentials: Bool { get }
    var usesLiveLoop: Bool { get }
    var eventHandler: ((VoiceServiceEvent) -> Void)? { get set }
    /// Live player still has scheduled desk / Grok PCM. Ambient speech must
    /// not cancel it; only a command does.
    var hasPendingPlayback: Bool { get }

    func startListening() async -> String
    func speak(_ text: String) async
    func sendTextTurn(_ text: String) async
    func updatePresenceInstructions(_ text: String)
    func interruptResponse()
    /// 12:14: `create_response` false while tools run; one create after.
    func beginToolWaitCreate()
    func endToolWaitCreate()
    func cancel()
    /// Open live Grok + audio session after first paint so the first tap can hear.
    func warmUp() async
    /// First barge-in already dropped local. claimLocal must yield that
    /// turn so the interrupt answer can schedule on the one-engine player.
    var listenLoopBargeConsumed: Bool { get }
}

extension VoiceServicing {
    func warmUp() async {}
    var hasPendingPlayback: Bool { false }
    var listenLoopBargeConsumed: Bool { false }
    func beginToolWaitCreate() {}
    func endToolWaitCreate() {}
}

enum VoiceRuntime {
    /// Production/debug: live Grok when a key exists. Honest setup when it does not.
    /// Mock is only for `-ui-testing`, unit tests, and CI Simulator smoke.
    @MainActor
    static func makeService() -> any VoiceServicing {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return MockVoiceService(label: "UITest", instant: true)
        }
        if let key = VoiceDeskSecrets.xaiAPIKey {
            return GrokVoiceService(apiKey: key, voiceID: VoiceDeskSecrets.voiceID)
        }
        return UnconfiguredVoiceService()
    }
}

/// Observable facade so SwiftUI tracks state through `any VoiceServicing`.
@MainActor
@Observable
final class VoiceBox {
    private(set) var state: VoiceState
    private(set) var lastError: String?
    let backendLabel: String
    let isInstant: Bool
    let needsCredentials: Bool
    let usesLiveLoop: Bool

    var transcriptHandler: ((VoiceTranscript) -> Void)?
    var hasPendingPlayback: Bool { service.hasPendingPlayback }
    var listenLoopBargeConsumed: Bool { service.listenLoopBargeConsumed }

    private let service: any VoiceServicing

    init(service: any VoiceServicing) {
        self.service = service
        self.state = service.state
        self.backendLabel = service.backendLabel
        self.isInstant = service.isInstant
        self.needsCredentials = service.needsCredentials
        self.usesLiveLoop = service.usesLiveLoop
        service.eventHandler = { [weak self] event in
            self?.handle(event)
        }
    }

    func startListening() async -> String {
        lastError = nil
        return await service.startListening()
    }

    func warmUp() async {
        await service.warmUp()
    }

    func speak(_ text: String) async {
        await service.speak(text)
    }

    func sendTextTurn(_ text: String) async {
        await service.sendTextTurn(text)
    }

    func updatePresenceInstructions(_ text: String) {
        service.updatePresenceInstructions(text)
    }

    func interruptResponse() {
        service.interruptResponse()
    }

    func beginToolWaitCreate() {
        service.beginToolWaitCreate()
    }

    func endToolWaitCreate() {
        service.endToolWaitCreate()
    }

    func cancel() {
        service.cancel()
    }

    private func handle(_ event: VoiceServiceEvent) {
        switch event {
        case .state(let next):
            state = next
        case .userTranscript(let text, let isFinal, let itemID):
            transcriptHandler?(VoiceTranscript(role: .user, text: text, isFinal: isFinal, itemID: itemID))
        case .assistantTranscript(let text, let isFinal):
            transcriptHandler?(VoiceTranscript(role: .assistant, text: text, isFinal: isFinal))
        case .failed(let message):
            lastError = message
        case .recovered:
            lastError = nil
        case .setupRequired:
            break
        }
    }
}

/// Timed listen/speak for `-ui-testing`, unit tests, and CI only.
@MainActor
@Observable
final class MockVoiceService: VoiceServicing {
    private var session = VoiceSession()
    let backendLabel: String
    let isInstant: Bool
    let needsCredentials = false
    let usesLiveLoop = false
    var eventHandler: ((VoiceServiceEvent) -> Void)?

    var state: VoiceState { session.state }

    init(label: String, instant: Bool = false) {
        self.backendLabel = label
        self.isInstant = instant
    }

    private(set) var spoken: [String] = []

    func startListening() async -> String {
        apply(.cancel)
        if !isInstant {
            await requestMicrophone()
        }
        apply(.tapTalk)
        if !isInstant {
            try? await Task.sleep(for: .milliseconds(1300))
            guard session.state == .listening else { return "" }
        }
        apply(.listenFinished)
        return ""
    }

    func speak(_ text: String) async {
        spoken.append(text)
        apply(.speakStarted)
        if !isInstant {
            let milliseconds = min(4200, max(800, text.count * 28))
            try? await Task.sleep(for: .milliseconds(milliseconds))
        }
        if session.state == .speaking {
            apply(.speakFinished)
        }
    }

    func sendTextTurn(_ text: String) async {
        _ = text
    }

    func updatePresenceInstructions(_ text: String) {
        _ = text
    }

    func interruptResponse() {}

    func cancel() {
        apply(.cancel)
    }

    private func apply(_ event: VoiceSessionEvent) {
        session.apply(event)
        eventHandler?(.state(session.state))
    }

    private func requestMicrophone() async {
        _ = await AVAudioApplication.requestRecordPermission()
    }
}

/// No key: honest empty/setup. Never a timed fake Grok conversation.
@MainActor
@Observable
final class UnconfiguredVoiceService: VoiceServicing {
    private(set) var state: VoiceState = .idle
    let backendLabel = "Connect Grok · set XAI_API_KEY"
    let isInstant = true
    let needsCredentials = true
    let usesLiveLoop = false
    var eventHandler: ((VoiceServiceEvent) -> Void)?

    func startListening() async -> String {
        eventHandler?(.setupRequired)
        return ""
    }

    func speak(_ text: String) async {
        _ = text
    }

    func sendTextTurn(_ text: String) async {
        _ = text
    }

    func updatePresenceInstructions(_ text: String) {
        _ = text
    }

    func interruptResponse() {}

    func cancel() {
        state = .idle
        eventHandler?(.state(.idle))
    }
}
