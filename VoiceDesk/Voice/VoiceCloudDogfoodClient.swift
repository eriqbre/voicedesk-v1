import Foundation
import Observation
import VoiceDeskLogic

/// Opt-in DEBUG / TestFlight cloud upload. App Store production never enables.
@MainActor
@Observable
final class VoiceCloudDogfoodSettings {
    static let shared = VoiceCloudDogfoodSettings()
    static let enabledKey = "voice.cloudDogfoodLog.enabled"
    static let gistIDKey = "voice.cloudDogfoodLog.gistID"

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    var lastStatus: String = ""
    var lastDestination: String = ""
    var lastError: String = ""
    var persistedGistID: String?

    var allowsLogging: Bool {
        VoiceDogfoodGate.allowsLogging
    }

    var showsBanner: Bool {
        allowsLogging && isEnabled
    }

    var config: VoiceCloudLogConfig? {
        VoiceCloudLogConfig.resolve(
            token: VoiceDeskSecrets.voiceDogfoodGitHubToken,
            gistID: VoiceDeskSecrets.voiceDogfoodGistID,
            repo: VoiceDeskSecrets.voiceDogfoodGitHubRepo,
            repoPath: VoiceDeskSecrets.voiceDogfoodGitHubPath,
            httpsURL: VoiceDeskSecrets.voiceDogfoodUploadURL,
            httpsSecret: VoiceDeskSecrets.voiceDogfoodUploadSecret,
            persistedGistID: persistedGistID
        )
    }

    var pullHint: String {
        config?.pullHint ?? "Add VOICE_DOGFOOD_GITHUB_TOKEN (and gist/repo) or HTTPS URL+secret."
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        persistedGistID = UserDefaults.standard.string(forKey: Self.gistIDKey)
    }

    func rememberGistID(_ id: String) {
        persistedGistID = id
        UserDefaults.standard.set(id, forKey: Self.gistIDKey)
    }
}

@MainActor
final class VoiceCloudDogfoodClient {
    static let shared = VoiceCloudDogfoodClient()

    private var queue: [VoiceInteractionEntry] = []
    private var running = false
    private let transport = URLSessionVoiceCloudTransport()

    func enqueue(_ entry: VoiceInteractionEntry) {
        let settings = VoiceCloudDogfoodSettings.shared
        guard settings.allowsLogging, settings.isEnabled else { return }
        guard settings.config != nil else {
            settings.lastError = VoiceCloudLogError.missingConfig.description
            settings.lastStatus = "missing Secrets token"
            return
        }
        queue.append(entry)
        pump()
    }

    private func pump() {
        guard !running else { return }
        running = true
        Task { await drain() }
    }

    private func drain() async {
        let settings = VoiceCloudDogfoodSettings.shared
        while !queue.isEmpty {
            let entry = queue.removeFirst()
            guard let config = settings.config else {
                settings.lastError = VoiceCloudLogError.missingConfig.description
                break
            }
            let uploader = VoiceCloudLogUploader(
                config: config,
                transport: transport,
                allowsLogging: settings.allowsLogging,
                optedIn: settings.isEnabled
            )
            do {
                let result = try await uploader.upload(entry)
                if let created = result.createdGistID {
                    settings.rememberGistID(created)
                }
                settings.lastDestination = result.destination
                settings.lastStatus = "uploaded"
                settings.lastError = ""
            } catch {
                settings.lastError = error.localizedDescription
                settings.lastStatus = "upload failed"
            }
        }
        running = false
    }
}

struct URLSessionVoiceCloudTransport: VoiceCloudLogTransporting {
    func send(_ request: VoiceCloudLogHTTPRequest) async throws -> VoiceCloudLogHTTPResponse {
        guard let url = URL(string: request.url) else {
            throw VoiceCloudLogError.badURL
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body.isEmpty ? nil : request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return VoiceCloudLogHTTPResponse(status: status, body: data)
    }
}
