import Foundation

/// Headless live Grok speech tape. Product socket is
/// `wss://api.x.ai/v1/realtime?model=grok-voice-latest` with the existing
/// PCM 24 kHz / `server_vad` / Eve `session.update` contract.
///
/// Local: `XAI_API_KEY=... swift test --package-path VoiceDeskLogic --filter GrokVoiceTape`
/// Never reads `Secrets.plist`. Missing key skips the live test; it does not fail CI.
public enum GrokVoiceTape: Sendable {
    public static let firstAudioCap: Duration = .seconds(12)
    public static let turnCap: Duration = .seconds(25)
    public static let appendChunkMilliseconds = 100

    public static let environmentKeyNames = ["XAI_API_KEY", "VOICEDESK_XAI_API_KEY"]

    public struct Fixture: Codable, Equatable, Sendable {
        public var id: String
        public var family: String
        public var utterance: String
        public var intent: String
        public var allowedIntents: [String]?
        /// Live tape hits a subset — one or two per family — not every synonym.
        public var live: Bool?
        /// Optional 24 kHz mono PCM16 LE `.wav` or raw `.pcm` / `.raw`, relative to the fixture file.
        public var pcmFile: String?
        public var deskPreset: String?
        public var pendingSearchClarify: Bool?
        public var hadFocusedEmail: Bool?
        public var stickyFromName: String?

        public init(
            id: String,
            family: String,
            utterance: String,
            intent: String,
            allowedIntents: [String]? = nil,
            live: Bool? = nil,
            pcmFile: String? = nil,
            deskPreset: String? = nil,
            pendingSearchClarify: Bool? = nil,
            hadFocusedEmail: Bool? = nil,
            stickyFromName: String? = nil
        ) {
            self.id = id
            self.family = family
            self.utterance = utterance
            self.intent = intent
            self.allowedIntents = allowedIntents
            self.live = live
            self.pcmFile = pcmFile
            self.deskPreset = deskPreset
            self.pendingSearchClarify = pendingSearchClarify
            self.hadFocusedEmail = hadFocusedEmail
            self.stickyFromName = stickyFromName
        }

        public var hasPCM: Bool {
            guard let pcmFile else { return false }
            return !pcmFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        public var runLive: Bool { live == true }

        public var intentsThatPass: Set<String> {
            var set = Set(allowedIntents ?? [])
            set.insert(intent)
            return set
        }

        public var replayContext: DeskContext {
            VoiceRegressionDesk.desk(preset: deskPreset)
        }

        public var replayFocusedEmail: EmailItem? {
            guard hadFocusedEmail == true else { return nil }
            return VoiceRegressionDesk.sticky(named: stickyFromName)
        }

        public var replayClarifyMatches: [EmailItem] {
            guard pendingSearchClarify == true else { return [] }
            return replayContext.snapshot.emails
        }
    }

    public enum Failure: Equatable, Sendable, CustomStringConvertible {
        case noFirstAudio
        case deskRefusal
        case transport(String)

        public var description: String {
            switch self {
            case .noFirstAudio:
                return "no first audio delta within the cap"
            case .deskRefusal:
                return "assistant text looks like a Grok desk-refusal / meta handoff"
            case .transport(let message):
                return message
            }
        }
    }

    public struct Result: Equatable, Sendable {
        public var fixtureID: String
        public var utterance: String
        public var usedPCM: Bool
        public var userTranscript: String?
        public var firstAudioDeltaMilliseconds: Int?
        public var assistantText: String
        public var errors: [String]
        public var failures: [Failure]

        public init(
            fixtureID: String,
            utterance: String,
            usedPCM: Bool,
            userTranscript: String? = nil,
            firstAudioDeltaMilliseconds: Int? = nil,
            assistantText: String = "",
            errors: [String] = [],
            failures: [Failure] = []
        ) {
            self.fixtureID = fixtureID
            self.utterance = utterance
            self.usedPCM = usedPCM
            self.userTranscript = userTranscript
            self.firstAudioDeltaMilliseconds = firstAudioDeltaMilliseconds
            self.assistantText = assistantText
            self.errors = errors
            self.failures = failures
        }

        public var passed: Bool { failures.isEmpty }
    }

    public static func apiKeyFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        for name in environmentKeyNames {
            let trimmed = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// Reuses `ConversationPresence` desk-refusal / handoff detectors.
    public static func isDeskRefusal(_ raw: String) -> Bool {
        ConversationPresence.isGrokDeskRefusal(raw)
            || ConversationPresence.isGrokDeskHandoff(raw)
            || ConversationPresence.isGrokDeskMeta(raw)
    }

    public static func evaluate(
        assistantText: String,
        firstAudioDeltaMilliseconds: Int?,
        firstAudioCapMilliseconds: Int = 12_000
    ) -> [Failure] {
        var failures: [Failure] = []
        if let firstAudioDeltaMilliseconds {
            if firstAudioDeltaMilliseconds > firstAudioCapMilliseconds {
                failures.append(.noFirstAudio)
            }
        } else {
            failures.append(.noFirstAudio)
        }
        if isDeskRefusal(assistantText) {
            failures.append(.deskRefusal)
        }
        return failures
    }

    public static func decodeJSONL(_ text: String) throws -> [Fixture] {
        var fixtures: [Fixture] = []
        let decoder = JSONDecoder()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            fixtures.append(try decoder.decode(Fixture.self, from: Data(line.utf8)))
        }
        return fixtures
    }

    /// Offline family outcome. No network. Uses the synthetic regression desk — not live mail.
    public static func replay(_ fixture: Fixture) -> VoiceTurnReplay.Result {
        VoiceTurnReplay.play(
            utterance: fixture.utterance,
            context: fixture.replayContext,
            focusedEmail: fixture.replayFocusedEmail,
            pendingSearchClarify: fixture.pendingSearchClarify ?? false,
            clarifyMatches: fixture.replayClarifyMatches
        )
    }

    public static func liveSubset(_ fixtures: [Fixture]) -> [Fixture] {
        let marked = fixtures.filter(\.runLive)
        if !marked.isEmpty { return marked }
        var seen = Set<String>()
        return fixtures.filter { fixture in
            seen.insert(fixture.family).inserted
        }
    }

    public static func loadFixtures(from directory: URL) throws -> [Fixture] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var fixtures: [Fixture] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            fixtures.append(contentsOf: try decodeJSONL(text))
        }
        return fixtures
    }

    public static func resolvePCMURL(fixture: Fixture, directory: URL) -> URL? {
        guard let name = fixture.pcmFile?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        return directory.appendingPathComponent(name)
    }

    public static func loadPCM16LE24kMono(from url: URL) throws -> Data {
        try pcm16LE24kMono(from: try Data(contentsOf: url))
    }

    public static func pcm16LE24kMono(from data: Data) throws -> Data {
        if looksLikeWAV(data) {
            return try pcmFromWAV(data)
        }
        guard data.count % 2 == 0 else {
            throw TapeError.invalidPCM("raw PCM must be even-length PCM16 LE")
        }
        return data
    }

    public static func appendJSONChunks(pcm: Data, milliseconds: Int = appendChunkMilliseconds) -> [String] {
        GrokRealtime.pcmAppendChunks(pcm, milliseconds: milliseconds).map {
            GrokRealtime.appendAudioJSON(base64: $0.base64EncodedString())
        }
    }

    public static func run(
        fixture: Fixture,
        pcm: Data? = nil,
        apiKey: String,
        firstAudioCap: Duration = firstAudioCap,
        turnCap: Duration = turnCap
    ) async -> Result {
        await GrokVoiceTapeSession.run(
            fixture: fixture,
            pcm: pcm,
            apiKey: apiKey,
            firstAudioCap: firstAudioCap,
            turnCap: turnCap
        )
    }

    enum TapeError: Error, CustomStringConvertible {
        case invalidPCM(String)

        var description: String {
            switch self {
            case .invalidPCM(let message):
                return message
            }
        }
    }

    private static func looksLikeWAV(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        return data.prefix(4) == Data("RIFF".utf8) && data.subdata(in: 8..<12) == Data("WAVE".utf8)
    }

    private static func pcmFromWAV(_ data: Data) throws -> Data {
        var offset = 12
        var sampleRate = 0
        var channels = 0
        var bits = 0
        var audioFormat = 0
        var pcm: Data?
        while offset + 8 <= data.count {
            let id = String(data: data.subdata(in: offset..<(offset + 4)), encoding: .ascii) ?? ""
            let size = int32LE(data, offset + 4)
            offset += 8
            let next = min(offset + size, data.count)
            let payload = data.subdata(in: offset..<next)
            if id == "fmt " {
                guard payload.count >= 16 else {
                    throw TapeError.invalidPCM("WAV fmt chunk is short")
                }
                audioFormat = int16LE(payload, 0)
                channels = int16LE(payload, 2)
                sampleRate = int32LE(payload, 4)
                bits = int16LE(payload, 14)
            } else if id == "data" {
                pcm = payload
            }
            offset = next + (size % 2)
        }
        guard audioFormat == 1 else {
            throw TapeError.invalidPCM("WAV must be PCM (format 1), got \(audioFormat)")
        }
        guard channels == 1 else {
            throw TapeError.invalidPCM("WAV must be mono, got \(channels) channels")
        }
        guard bits == 16 else {
            throw TapeError.invalidPCM("WAV must be PCM16, got \(bits)-bit")
        }
        guard sampleRate == GrokRealtime.sampleRate else {
            throw TapeError.invalidPCM("WAV must be \(GrokRealtime.sampleRate) Hz, got \(sampleRate)")
        }
        guard let pcm, pcm.count % 2 == 0 else {
            throw TapeError.invalidPCM("WAV data chunk missing or not PCM16")
        }
        return pcm
    }

    private static func int16LE(_ data: Data, _ offset: Int) -> Int {
        Int(Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)))
    }

    private static func int32LE(_ data: Data, _ offset: Int) -> Int {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return Int(Int32(bitPattern: b0 | b1 | b2 | b3))
    }
}
