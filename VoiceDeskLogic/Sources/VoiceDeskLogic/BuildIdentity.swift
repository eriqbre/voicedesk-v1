import Foundation

/// Baked git identity for the binary. Never invents a SHA.
///
/// iOS fills this from Info.plist keys written at build time.
/// Linux tests use `fixture` — not a live `git` call.
public struct BuildIdentity: Equatable, Sendable {
    public var shortSHA: String
    public var branch: String

    public static let unknownSpokenLine = "VoiceDesk, unknown SHA."
    public static let unknown = BuildIdentity(shortSHA: "", branch: "")
    /// Test-only. Not a claim that this binary was built from that commit.
    public static let fixture = BuildIdentity(
        shortSHA: "1fa0a0e",
        branch: "cursor/cards-only-email-first-tap-9c2c"
    )

    public init(shortSHA: String = "", branch: String = "") {
        self.shortSHA = Self.normalizedSHA(shortSHA)
        self.branch = Self.normalizedBranch(branch)
    }

    public init(infoDictionary: [String: Any]?) {
        self.init(
            shortSHA: infoDictionary?["GIT_SHA"] as? String ?? "",
            branch: infoDictionary?["GIT_BRANCH"] as? String ?? ""
        )
    }

    /// Short spoken desk reply. `"VoiceDesk 1fa0a0e."` or unknown — never a guessed hash.
    public var spokenLine: String {
        if shortSHA.isEmpty {
            return Self.unknownSpokenLine
        }
        return "VoiceDesk \(shortSHA)."
    }

    private static func normalizedSHA(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lower = trimmed.lowercased()
        if lower == "unknown" || lower.contains("dirty") || lower.contains("replace") {
            return ""
        }
        guard lower.unicodeScalars.allSatisfy({ Self.hex.contains($0) }) else {
            return ""
        }
        guard (4...12).contains(lower.count) else {
            return ""
        }
        return lower
    }

    private static func normalizedBranch(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "HEAD" else { return "" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/-"))
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        return filtered
    }

    private static let hex = CharacterSet(charactersIn: "0123456789abcdef")
}
