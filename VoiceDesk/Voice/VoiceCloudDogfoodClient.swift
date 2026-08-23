import Foundation
import Observation
import VoiceDeskLogic

/// DEBUG / TestFlight cloud upload. Default ON. App Store production never enables.
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

    var hasGitHubToken: Bool {
        VoiceDeskSecrets.voiceDogfoodGitHubToken != nil
    }

    var hasAnyDestination: Bool {
        config != nil
    }

    /// Quiet one-time setup hint. Not a per-session ritual.
    var showsMissingTokenBanner: Bool {
        allowsLogging && isEnabled && !hasGitHubToken && VoiceDeskSecrets.voiceDogfoodUploadURL == nil
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
        config?.pullHint ?? "Add VOICE_DOGFOOD_GITHUB_TOKEN to Secrets.plist once"
    }

    private init() {
        let stored = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool
        isEnabled = VoiceCloudDogfoodPreference.isEnabled(
            allowsLogging: VoiceDogfoodGate.allowsLogging,
            storedValue: stored
        )
        if stored == nil, isEnabled {
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
        }
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
    private var ensuring = false
    private let transport = URLSessionVoiceCloudTransport()

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    func prepareOnLaunch() {
        guard !isUITesting else { return }
        let settings = VoiceCloudDogfoodSettings.shared
        guard settings.allowsLogging, settings.isEnabled else { return }
        guard let token = VoiceDeskSecrets.voiceDogfoodGitHubToken else { return }
        Task { await ensureGist(token: token) }
    }

    func enqueue(_ entry: VoiceInteractionEntry) {
        guard !isUITesting else { return }
        let settings = VoiceCloudDogfoodSettings.shared
        guard settings.allowsLogging, settings.isEnabled else { return }
        guard settings.config != nil else {
            settings.lastError = VoiceCloudLogError.missingConfig.description
            settings.lastStatus = "missing token"
            return
        }
        queue.append(entry)
        pump()
    }

    private func ensureGist(token: String) async {
        guard !ensuring else { return }
        ensuring = true
        defer { ensuring = false }
        let settings = VoiceCloudDogfoodSettings.shared
        do {
            let resolved = try await VoiceCloudGistResolver(
                token: token,
                persistedID: settings.persistedGistID ?? VoiceDeskSecrets.voiceDogfoodGistID,
                transport: transport
            ).resolve()
            settings.rememberGistID(resolved.id)
            settings.lastDestination = "gist:\(resolved.id)"
            settings.lastError = ""
            if settings.lastStatus.isEmpty {
                settings.lastStatus = resolved.created ? "gist ready" : "gist reused"
            }
        } catch {
            settings.lastError = error.localizedDescription
            settings.lastStatus = "gist setup failed"
        }
    }

    private func pump() {
        guard !running else { return }
        running = true
        Task { await drain() }
    }

    private func drain() async {
        let settings = VoiceCloudDogfoodSettings.shared
        if let token = VoiceDeskSecrets.voiceDogfoodGitHubToken, settings.persistedGistID == nil {
            await ensureGist(token: token)
        }
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
                if let id = result.gistID ?? result.createdGistID {
                    settings.rememberGistID(id)
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
