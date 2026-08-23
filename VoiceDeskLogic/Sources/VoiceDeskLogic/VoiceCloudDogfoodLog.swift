import Foundation

/// DEBUG + TestFlight only. App Store production (`compileDebug == false` and
/// no sandbox receipt) never enables cloud upload.
public enum VoiceDogfoodGate: Sendable {
    public static var compileDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// TestFlight / sandbox App Store receipt. Production App Store is `receipt`.
    public static func isTestFlightReceipt(receiptLastPathComponent: String?) -> Bool {
        receiptLastPathComponent == "sandboxReceipt"
    }

    public static func isTestFlightReceipt(bundle: Bundle = .main) -> Bool {
        isTestFlightReceipt(receiptLastPathComponent: bundle.appStoreReceiptURL?.lastPathComponent)
    }

    public static func allowsLogging(compileDebug: Bool, isTestFlight: Bool) -> Bool {
        compileDebug || isTestFlight
    }

    public static var allowsLogging: Bool {
        allowsLogging(compileDebug: compileDebug, isTestFlight: isTestFlightReceipt())
    }
}

/// DEBUG / TestFlight default ON. App Store production cannot enable.
/// `storedValue` is nil when the user has never flipped the escape-hatch toggle.
public enum VoiceCloudDogfoodPreference: Sendable {
    public static func isEnabled(allowsLogging: Bool, storedValue: Bool?) -> Bool {
        guard allowsLogging else { return false }
        return storedValue ?? true
    }
}

/// Fixed private gist Elon discovers without a gist id from Eriq.
public enum VoiceCloudGistStore: Sendable {
    public static let description = "VoiceDesk dogfood voice-log"
    public static let filename = VoiceDebugLogPaths.fileName
    public static let bootstrapLine = "# VoiceDesk dogfood voice-log\n"

    public static func matchesDescription(_ raw: String?) -> Bool {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value == description || value.hasPrefix(description)
    }

    public static func idMatchingDescription(in listBody: Data) -> String? {
        guard let items = try? JSONSerialization.jsonObject(with: listBody) as? [[String: Any]] else {
            return nil
        }
        for item in items {
            guard matchesDescription(item["description"] as? String),
                  let id = item["id"] as? String,
                  !id.isEmpty
            else { continue }
            return id
        }
        return nil
    }
}

/// Where a dogfood turn is posted. Prefer a private GitHub gist or repo.
public enum VoiceCloudLogKind: String, Sendable, Equatable {
    case githubGist
    case githubRepo
    case https
}

public struct VoiceCloudLogConfig: Equatable, Sendable {
    public var kind: VoiceCloudLogKind
    public var token: String?
    public var gistID: String?
    public var repo: String?
    public var repoPath: String
    public var httpsURL: String?
    public var httpsSecret: String?
    public var filename: String
    public var persistCreatedGistID: Bool

    public init(
        kind: VoiceCloudLogKind,
        token: String? = nil,
        gistID: String? = nil,
        repo: String? = nil,
        repoPath: String = ".debug/voice-log.jsonl",
        httpsURL: String? = nil,
        httpsSecret: String? = nil,
        filename: String = VoiceDebugLogPaths.fileName,
        persistCreatedGistID: Bool = false
    ) {
        self.kind = kind
        self.token = token
        self.gistID = gistID
        self.repo = repo
        self.repoPath = repoPath
        self.httpsURL = httpsURL
        self.httpsSecret = httpsSecret
        self.filename = filename
        self.persistCreatedGistID = persistCreatedGistID
    }

    /// Resolve Secrets / env. Prefer gist, then repo, then HTTPS+secret.
    /// Token-only creates a private gist on first upload.
    public static func resolve(
        token: String?,
        gistID: String?,
        repo: String?,
        repoPath: String? = nil,
        httpsURL: String?,
        httpsSecret: String?,
        persistedGistID: String? = nil
    ) -> VoiceCloudLogConfig? {
        let tok = trimmed(token)
        let gist = trimmed(gistID) ?? trimmed(persistedGistID)
        let repository = trimmed(repo)
        let path = trimmed(repoPath) ?? ".debug/voice-log.jsonl"
        let url = trimmed(httpsURL)
        let secret = trimmed(httpsSecret)

        if tok != nil, gist != nil {
            return VoiceCloudLogConfig(kind: .githubGist, token: tok, gistID: gist)
        }
        if tok != nil, repository != nil {
            return VoiceCloudLogConfig(kind: .githubRepo, token: tok, repo: repository, repoPath: path)
        }
        if url != nil, secret != nil {
            return VoiceCloudLogConfig(kind: .https, httpsURL: url, httpsSecret: secret)
        }
        if tok != nil {
            return VoiceCloudLogConfig(
                kind: .githubGist,
                token: tok,
                gistID: nil,
                persistCreatedGistID: true
            )
        }
        return nil
    }

    public var pullHint: String {
        switch kind {
        case .githubGist:
            if let gistID, !gistID.isEmpty {
                return "gh gist view \(gistID) --filename \(filename)"
            }
            return "gh gist view <gist-id> --filename \(filename)"
        case .githubRepo:
            let repo = repo ?? "OWNER/REPO"
            return "gh api repos/\(repo)/contents/\(repoPath) --jq .content | base64 -d"
        case .https:
            return "curl -sS -H 'X-VoiceDesk-Secret: $VOICE_DOGFOOD_UPLOAD_SECRET' \(httpsURL ?? "<url>")"
        }
    }

    private static func trimmed(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

public struct VoiceCloudLogHTTPRequest: Equatable, Sendable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, url: String, headers: [String: String], body: Data = Data()) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct VoiceCloudLogHTTPResponse: Equatable, Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

public protocol VoiceCloudLogTransporting: Sendable {
    func send(_ request: VoiceCloudLogHTTPRequest) async throws -> VoiceCloudLogHTTPResponse
}

public struct VoiceCloudLogResult: Equatable, Sendable {
    public var destination: String
    public var gistID: String?
    public var createdGistID: String?
    public var bytes: Int

    public init(destination: String, gistID: String? = nil, createdGistID: String? = nil, bytes: Int) {
        self.destination = destination
        self.gistID = gistID
        self.createdGistID = createdGistID
        self.bytes = bytes
    }
}

public enum VoiceCloudLogError: Error, Equatable, CustomStringConvertible, LocalizedError, Sendable {
    case notAllowed
    case missingConfig
    case missingToken
    case badURL
    case http(Int, String)
    case encode
    case gistParse

    public var description: String {
        switch self {
        case .notAllowed:
            return "cloud dogfood log is off (App Store, or escape-hatch toggle off)"
        case .missingConfig:
            return "Add VOICE_DOGFOOD_GITHUB_TOKEN to Secrets.plist once"
        case .missingToken:
            return "VOICE_DOGFOOD_GITHUB_TOKEN missing"
        case .badURL:
            return "cloud log URL is invalid"
        case .http(let status, let body):
            return "cloud log HTTP \(status): \(body)"
        case .encode:
            return "could not encode voice-log line"
        case .gistParse:
            return "GitHub gist response missing file content"
        }
    }

    public var errorDescription: String? { description }
}

/// Cloud JSONL + GitHub/HTTPS bodies. No audio fields.
public enum VoiceCloudLogCodec: Sendable {
    public static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func jsonlLine(for entry: VoiceInteractionEntry) -> Data? {
        guard let data = try? jsonEncoder().encode(entry),
              var line = String(data: data, encoding: .utf8)
        else { return nil }
        if !line.hasSuffix("\n") { line.append("\n") }
        return line.data(using: .utf8)
    }

    public static func appendJSONL(existing: String, line: Data) -> String {
        var content = existing
        if !content.isEmpty, !content.hasSuffix("\n") {
            content.append("\n")
        }
        content.append(String(data: line, encoding: .utf8) ?? "")
        return content
    }

    public static func gistCreateBody(filename: String, content: String, description: String) throws -> Data {
        let payload: [String: Any] = [
            "description": description,
            "public": false,
            "files": [filename: ["content": content]]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public static func gistUpdateBody(filename: String, content: String) throws -> Data {
        let payload: [String: Any] = [
            "files": [filename: ["content": content]]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public static func gistFileContent(from body: Data, filename: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let files = object["files"] as? [String: Any]
        else { return nil }
        if let file = files[filename] as? [String: Any], let content = file["content"] as? String {
            return content
        }
        for value in files.values {
            if let file = value as? [String: Any], let content = file["content"] as? String {
                return content
            }
        }
        return nil
    }

    public static func gistID(from body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return object["id"] as? String
    }

    public static func repoContentsBody(message: String, content: String, sha: String?) throws -> Data {
        var payload: [String: Any] = [
            "message": message,
            "content": Data(content.utf8).base64EncodedString()
        ]
        if let sha, !sha.isEmpty {
            payload["sha"] = sha
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public static func repoFile(from body: Data) -> (content: String, sha: String?)? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        let sha = object["sha"] as? String
        guard let encoded = object["content"] as? String else {
            return ("", sha)
        }
        let compact = encoded.replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: compact),
              let text = String(data: data, encoding: .utf8)
        else { return ("", sha) }
        return (text, sha)
    }

    public static func httpsEnvelope(entry: VoiceInteractionEntry, uploadedAt: Date) throws -> Data {
        try jsonEncoder().encode(VoiceCloudLogEnvelope(uploadedAt: uploadedAt, entry: entry))
    }
}

public struct VoiceCloudLogEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var uploadedAt: Date
    public var hasAudio: Bool
    public var entry: VoiceInteractionEntry

    public init(
        schemaVersion: Int = VoiceInteractionEntry.currentSchemaVersion,
        uploadedAt: Date,
        hasAudio: Bool = false,
        entry: VoiceInteractionEntry
    ) {
        self.schemaVersion = schemaVersion
        self.uploadedAt = uploadedAt
        self.hasAudio = hasAudio
        self.entry = entry
    }
}

/// Strip secrets / emails / phones from a cloud payload. Names and transcripts stay.
public enum VoiceCloudLogRedactor: Sendable {
    public static func redact(_ entry: VoiceInteractionEntry) -> VoiceInteractionEntry {
        var copy = entry
        copy.userTranscript = secretsAndContact(in: entry.userTranscript)
        copy.assistantReply = secretsAndContact(in: entry.assistantReply)
        copy.focusedPerson = entry.focusedPerson.map { secretsAndContact(in: $0) }
        copy.searchQuery = entry.searchQuery.map { secretsAndContact(in: $0) }
        copy.routingNotes = entry.routingNotes.map { secretsAndContact(in: $0) }
        copy.cardsAttached = entry.cardsAttached.map { secretsAndContact(in: $0) }
        copy.errors = entry.errors.map { secretsAndContact(in: $0) }
        copy.voicePath = secretsAndContact(in: entry.voicePath)
        return copy
    }

    public static func redactHeaders(_ headers: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in headers {
            if key.caseInsensitiveCompare("Authorization") == .orderedSame
                || key.caseInsensitiveCompare("X-VoiceDesk-Secret") == .orderedSame {
                out[key] = "[redacted]"
            } else {
                out[key] = secretsAndContact(in: value)
            }
        }
        return out
    }

    public static func secretsAndContact(in raw: String) -> String {
        var text = raw
        text = replace(text, pattern: #"(?i)bearer\s+[A-Za-z0-9._\-+/=]+"#, with: "Bearer [redacted]")
        text = replace(text, pattern: #"github_pat_[A-Za-z0-9_]{20,}"#, with: "[redacted-pat]")
        text = replace(text, pattern: #"gh[pousr]_[A-Za-z0-9]{20,}"#, with: "[redacted-token]")
        text = replace(text, pattern: #"(?i)xai-[A-Za-z0-9_\-]{8,}"#, with: "[redacted-xai]")
        text = replace(text, pattern: #"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b"#, with: "[phone]")
        text = replaceEmails(in: text)
        return text
    }

    public static func containsAudioKey(in json: String) -> Bool {
        let banned = ["\"pcm\"", "\"wav\"", "\"m4a\"", "\"audioBase64\"", "\"microphone\"", "\"rawAudio\""]
        let lower = json.lowercased()
        return banned.contains { lower.contains($0.lowercased()) }
    }

    private static func replace(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func replaceEmails(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
            options: .caseInsensitive
        ) else { return text }
        let ns = text as NSString
        var result = text
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let email = ns.substring(with: match.range)
            let local = email.split(separator: "@").first.map(String.init) ?? "user"
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: "\(local)@redacted")
            }
        }
        return result
    }
}

enum VoiceCloudGitHub {
    static func request(method: String, url: String, token: String, body: Data = Data()) -> VoiceCloudLogHTTPRequest {
        VoiceCloudLogHTTPRequest(
            method: method,
            url: url,
            headers: [
                "Accept": "application/vnd.github+json",
                "Authorization": "Bearer \(token)",
                "User-Agent": "VoiceDesk-dogfood",
                "X-GitHub-Api-Version": "2022-11-28",
                "Content-Type": "application/json"
            ],
            body: body
        )
    }

    static func send(
        _ transport: any VoiceCloudLogTransporting,
        method: String,
        url: String,
        token: String,
        body: Data = Data()
    ) async throws -> VoiceCloudLogHTTPResponse {
        let response = try await transport.send(request(method: method, url: url, token: token, body: body))
        guard (200..<300).contains(response.status) else {
            let snippet = String(data: response.body, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw VoiceCloudLogError.http(response.status, String(snippet.prefix(180)))
        }
        return response
    }
}

/// List-or-create the private dogfood gist. Persisted id wins; else description match; else create once.
public struct VoiceCloudGistResolver: Sendable {
    public var token: String
    public var filename: String
    public var persistedID: String?
    public var transport: any VoiceCloudLogTransporting

    public init(
        token: String,
        filename: String = VoiceCloudGistStore.filename,
        persistedID: String? = nil,
        transport: any VoiceCloudLogTransporting
    ) {
        self.token = token
        self.filename = filename
        self.persistedID = persistedID
        self.transport = transport
    }

    public func resolve() async throws -> (id: String, created: Bool) {
        if let persistedID, !persistedID.isEmpty {
            return (persistedID, false)
        }
        let listed = try await VoiceCloudGitHub.send(
            transport,
            method: "GET",
            url: "https://api.github.com/gists?per_page=100",
            token: token
        )
        if let found = VoiceCloudGistStore.idMatchingDescription(in: listed.body) {
            return (found, false)
        }
        let body = try VoiceCloudLogCodec.gistCreateBody(
            filename: filename,
            content: VoiceCloudGistStore.bootstrapLine,
            description: VoiceCloudGistStore.description
        )
        let created = try await VoiceCloudGitHub.send(
            transport,
            method: "POST",
            url: "https://api.github.com/gists",
            token: token,
            body: body
        )
        guard let id = VoiceCloudLogCodec.gistID(from: created.body) else {
            throw VoiceCloudLogError.gistParse
        }
        return (id, true)
    }
}

public struct VoiceCloudLogUploader: Sendable {
    public var config: VoiceCloudLogConfig
    public var transport: any VoiceCloudLogTransporting
    public var allowsLogging: Bool
    public var optedIn: Bool
    public var now: @Sendable () -> Date

    public init(
        config: VoiceCloudLogConfig,
        transport: any VoiceCloudLogTransporting,
        allowsLogging: Bool,
        optedIn: Bool,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.transport = transport
        self.allowsLogging = allowsLogging
        self.optedIn = optedIn
        self.now = now
    }

    public func upload(_ entry: VoiceInteractionEntry) async throws -> VoiceCloudLogResult {
        guard allowsLogging, optedIn else { throw VoiceCloudLogError.notAllowed }
        let redacted = VoiceCloudLogRedactor.redact(entry)
        guard let line = VoiceCloudLogCodec.jsonlLine(for: redacted) else {
            throw VoiceCloudLogError.encode
        }
        switch config.kind {
        case .githubGist:
            return try await uploadGist(line: line)
        case .githubRepo:
            return try await uploadRepo(line: line)
        case .https:
            return try await uploadHTTPS(entry: redacted)
        }
    }

    private func uploadGist(line: Data) async throws -> VoiceCloudLogResult {
        guard let token = config.token, !token.isEmpty else { throw VoiceCloudLogError.missingToken }
        let resolved = try await VoiceCloudGistResolver(
            token: token,
            filename: config.filename,
            persistedID: config.gistID,
            transport: transport
        ).resolve()
        do {
            return try await patchGist(id: resolved.id, token: token, line: line)
        } catch VoiceCloudLogError.http(let status, _) where status == 404 {
            let created = try await VoiceCloudGistResolver(
                token: token,
                filename: config.filename,
                persistedID: nil,
                transport: transport
            ).resolve()
            return try await patchGist(id: created.id, token: token, line: line)
        }
    }

    private func patchGist(id: String, token: String, line: Data) async throws -> VoiceCloudLogResult {
        let existing = try await gistContent(id: id, token: token)
        let merged = VoiceCloudLogCodec.appendJSONL(existing: existing, line: line)
        let body = try VoiceCloudLogCodec.gistUpdateBody(filename: config.filename, content: merged)
        _ = try await VoiceCloudGitHub.send(
            transport,
            method: "PATCH",
            url: "https://api.github.com/gists/\(id)",
            token: token,
            body: body
        )
        return VoiceCloudLogResult(
            destination: "gist:\(id)",
            gistID: id,
            createdGistID: id,
            bytes: merged.utf8.count
        )
    }

    private func gistContent(id: String, token: String) async throws -> String {
        let response = try await VoiceCloudGitHub.send(
            transport,
            method: "GET",
            url: "https://api.github.com/gists/\(id)",
            token: token
        )
        return VoiceCloudLogCodec.gistFileContent(from: response.body, filename: config.filename) ?? ""
    }

    private func uploadRepo(line: Data) async throws -> VoiceCloudLogResult {
        guard let token = config.token, !token.isEmpty else { throw VoiceCloudLogError.missingToken }
        guard let repo = config.repo, !repo.isEmpty else { throw VoiceCloudLogError.missingConfig }
        let encodedPath = config.repoPath.split(separator: "/").map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        let url = "https://api.github.com/repos/\(repo)/contents/\(encodedPath)"
        var existing = ""
        var sha: String?
        do {
            let current = try await VoiceCloudGitHub.send(transport, method: "GET", url: url, token: token)
            if let parsed = VoiceCloudLogCodec.repoFile(from: current.body) {
                existing = parsed.content
                sha = parsed.sha
            }
        } catch VoiceCloudLogError.http(let status, _) where status == 404 {
            existing = ""
            sha = nil
        }
        let merged = VoiceCloudLogCodec.appendJSONL(existing: existing, line: line)
        let body = try VoiceCloudLogCodec.repoContentsBody(
            message: "dogfood voice-log",
            content: merged,
            sha: sha
        )
        _ = try await VoiceCloudGitHub.send(transport, method: "PUT", url: url, token: token, body: body)
        return VoiceCloudLogResult(destination: "repo:\(repo)/\(config.repoPath)", bytes: merged.utf8.count)
    }

    private func uploadHTTPS(entry: VoiceInteractionEntry) async throws -> VoiceCloudLogResult {
        guard let rawURL = config.httpsURL, let url = URL(string: rawURL) else {
            throw VoiceCloudLogError.badURL
        }
        guard let secret = config.httpsSecret, !secret.isEmpty else {
            throw VoiceCloudLogError.missingConfig
        }
        let body = try VoiceCloudLogCodec.httpsEnvelope(entry: entry, uploadedAt: now())
        let request = VoiceCloudLogHTTPRequest(
            method: "POST",
            url: url.absoluteString,
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": "VoiceDesk-dogfood",
                "X-VoiceDesk-Secret": secret
            ],
            body: body
        )
        let response = try await transport.send(request)
        try Self.throwIfFailed(response)
        return VoiceCloudLogResult(destination: "https:\(url.host ?? rawURL)", bytes: body.count)
    }

    private static func throwIfFailed(_ response: VoiceCloudLogHTTPResponse) throws {
        guard (200..<300).contains(response.status) else {
            let snippet = String(data: response.body, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw VoiceCloudLogError.http(response.status, String(snippet.prefix(180)))
        }
    }
}
