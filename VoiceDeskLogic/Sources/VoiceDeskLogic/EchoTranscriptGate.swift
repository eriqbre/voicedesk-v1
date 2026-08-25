import Foundation

/// Transcript-level echo filter. The microphone stays live.
///
/// One job: drop self-hear of on-device desk TTS. That is leftover ASR of
/// `lastSpokenLine` (synonym families). Grok `.speaking` is not desk TTS.
/// An empty `lastSpokenLine` never drops a real ask.
///
/// Do **not** mute the mic tap or `beginHalfDuplex`. That stack left
/// `VoiceSession` stuck in `.speaking`.
public struct EchoTranscriptGate: Equatable, Sendable {
    public var isSpeaking = false
    public var lastSpokenLine = ""

    public init() {}

    public mutating func reset() {
        isSpeaking = false
        lastSpokenLine = ""
    }

    public mutating func beginSpeaking(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastSpokenLine = trimmed
        isSpeaking = true
    }

    public mutating func finishSpeaking() {
        isSpeaking = false
    }

    /// Tap-stop / cancel. Next real ask must not be eaten as “still speaking.”
    /// Leftover echo of the last line can still be dropped.
    public mutating func cancelSpeaking() {
        isSpeaking = false
    }

    /// On-device desk TTS only (`beginSpeaking` with a real line). Grok
    /// speaking is not desk TTS and never drops a transcript.
    public func shouldIgnoreUserTranscript(voiceState: VoiceState = .listening) -> Bool {
        _ = voiceState
        return isSpeaking && !lastSpokenLine.isEmpty
    }

    /// Returns the trimmed transcript, or `nil` when this is leftover echo of
    /// on-device desk TTS. A real ask always returns. Never drop because
    /// `lastSpokenLine` is empty or Grok is speaking.
    public func acceptUserTranscript(
        _ text: String,
        voiceState: VoiceState = .listening
    ) -> String? {
        _ = voiceState
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isLeftoverEcho(trimmed) { return nil }
        return trimmed
    }

    /// One-sentence VoiceDesk identity line — finish it over barge-in.
    public var isProtectedIdentityLine: Bool {
        Self.isProtectedIdentityLine(lastSpokenLine)
    }

    public static func isProtectedIdentityLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.lowercased().hasPrefix("voicedesk")
    }

    /// `speech_started` has no words yet. Never cancel a desk / version line —
    /// wait for the transcript so echo can be dropped first.
    public func shouldCancelSpeakOnSpeechStarted(voiceState: VoiceState = .listening) -> Bool {
        !shouldIgnoreUserTranscript(voiceState: voiceState)
    }

    /// Dropped echo never stops Eve. A live non-echo ask may barge-in except
    /// on a short identity / version line (prefer finishing that sentence).
    public func shouldCancelSpeak(
        for transcript: String,
        voiceState: VoiceState = .listening
    ) -> Bool {
        guard acceptUserTranscript(transcript, voiceState: voiceState) != nil else {
            return false
        }
        if isProtectedIdentityLine { return false }
        return shouldIgnoreUserTranscript(voiceState: voiceState)
    }

    /// Intent + plan after the gate. Dropped transcripts have intent `"dropped"`
    /// and no desk plan. Live transcripts use the same classifier as replay.
    public func decide(
        _ text: String,
        voiceState: VoiceState = .listening,
        context: DeskContext = .disconnected
    ) -> EchoTranscriptDecision {
        guard let accepted = acceptUserTranscript(text, voiceState: voiceState) else {
            return EchoTranscriptDecision(intent: "dropped", acceptedText: nil, plan: nil)
        }
        let evidence = ConversationPresence.deskEvidence(for: accepted, context: context)
        let classified = VoiceInteractionLog.classify(utterance: accepted, evidence: evidence)
        return EchoTranscriptDecision(
            intent: classified.intent,
            acceptedText: accepted,
            plan: ConversationPresence.plan(for: accepted, context: context)
        )
    }

    /// True when `text` is only a leftover echo of `lastSpokenLine`.
    public func isLeftoverEcho(_ text: String) -> Bool {
        Self.isLeftoverEcho(text, of: lastSpokenLine)
    }

    public static func isLeftoverEcho(_ incoming: String, of spoken: String) -> Bool {
        let spokenTokens = EchoNorm.expandedTokens(spoken)
        let incomingTokens = EchoNorm.contentTokens(incoming)
        guard !spokenTokens.isEmpty, !incomingTokens.isEmpty else { return false }
        return incomingTokens.allSatisfy { spokenTokens.contains($0) }
    }
}

public struct EchoTranscriptDecision: Equatable, Sendable {
    public var intent: String
    public var acceptedText: String?
    public var plan: ConversationPresence.Plan?

    public var isDropped: Bool { acceptedText == nil }

    public init(intent: String, acceptedText: String?, plan: ConversationPresence.Plan?) {
        self.intent = intent
        self.acceptedText = acceptedText
        self.plan = plan
    }
}

/// Normalize spoken desk lines and ASR leftovers onto one token set.
enum EchoNorm {
    /// Filler that ASR may wrap around a leftover fragment.
    static let fillers: Set<String> = [
        "a", "an", "the", "um", "uh", "hmm", "mm", "mmm", "ah", "ohh",
        "please", "just", "like", "yeah", "yep", "ok", "okay"
    ]

    static func contentTokens(_ raw: String) -> [String] {
        expandedTokens(raw).filter { !fillers.contains($0) }
    }

    static func expandedTokens(_ raw: String) -> Set<String> {
        var tokens = Set<String>()
        let pieces = splitWords(raw)
        for piece in pieces {
            tokens.formUnion(family(for: piece))
        }
        if tokens.contains("voice"), tokens.contains("desk") {
            tokens.insert("voicedesk")
        }
        if tokens.contains("voicedesk") {
            tokens.insert("voice")
            tokens.insert("desk")
        }
        expandDottedVersions(in: raw, into: &tokens)
        expandPointMarketing(pieces, into: &tokens)
        return tokens
    }

    private static func splitWords(_ raw: String) -> [String] {
        var prepared = raw.lowercased()
        prepared = prepared.replacingOccurrences(of: "voicedesk", with: "voice desk")
        prepared = prepared.replacingOccurrences(
            of: #"['’`]"#,
            with: "",
            options: .regularExpression
        )
        return prepared
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// `0.1` / `0.1.0` → zero / point / one family, not one golden spelling.
    private static func expandDottedVersions(in raw: String, into tokens: inout Set<String>) {
        let dotted = dottedNumberMatches(in: raw)
        for version in dotted {
            let parts = version.split(separator: ".").map(String.init)
            tokens.insert("point")
            tokens.insert("dot")
            for part in parts {
                tokens.formUnion(family(for: part))
            }
            if parts.first == "0", parts.count >= 2 {
                tokens.formUnion(family(for: "0"))
            }
        }
    }

    private static func dottedNumberMatches(in raw: String) -> [String] {
        guard let detector = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)+"#) else {
            return []
        }
        let ns = raw as NSString
        return detector.matches(in: raw, options: [], range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    /// Spoken 0.x shape `"point 1"` still owns the leading-zero family.
    private static func expandPointMarketing(_ pieces: [String], into tokens: inout Set<String>) {
        let words = pieces.map { $0.lowercased() }
        for index in words.indices {
            let word = words[index]
            guard word == "point" || word == "dot" else { continue }
            tokens.insert("point")
            tokens.insert("dot")
            if index + 1 < words.count {
                tokens.formUnion(family(for: words[index + 1]))
            }
            // 0.x spoken as “point N” — leftover “zero” is still her voice, not a command.
            tokens.formUnion(family(for: "0"))
        }
    }

    static func family(for raw: String) -> Set<String> {
        let token = raw.lowercased()
        guard !token.isEmpty else { return [] }
        var set: Set<String> = [token]
        if let words = numberWords[token] {
            set.formUnion(words)
        }
        if let digit = wordToDigit[token] {
            set.insert(digit)
            if let words = numberWords[digit] {
                set.formUnion(words)
            }
        }
        if token == "point" || token == "dot" {
            set.formUnion(["point", "dot"])
        }
        if token == "voicedesk" {
            set.formUnion(["voicedesk", "voice", "desk"])
        }
        if token == "build" || token == "built" {
            set.formUnion(["build", "built"])
        }
        return set
    }

    private static let numberWords: [String: Set<String>] = [
        "0": ["0", "zero", "oh"],
        "1": ["1", "one"],
        "2": ["2", "two"],
        "3": ["3", "three"],
        "4": ["4", "four"],
        "5": ["5", "five"],
        "6": ["6", "six"],
        "7": ["7", "seven"],
        "8": ["8", "eight"],
        "9": ["9", "nine"],
        "10": ["10", "ten"]
    ]

    private static let wordToDigit: [String: String] = [
        "zero": "0", "oh": "0",
        "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8",
        "nine": "9", "ten": "10"
    ]
}
