import Foundation

/// Baked marketing + build + git identity. Never invents a version or a SHA.
///
/// iOS fills this from Info.plist keys written at build time
/// (`CFBundleShortVersionString` / `CFBundleVersion` from Version.xcconfig,
/// `GIT_SHA` / `GIT_BRANCH` from the inject bake).
/// Linux tests use `fixture` — not a live `git` call.
public struct BuildIdentity: Equatable, Sendable {
    public var marketing: String
    public var build: String
    public var shortSHA: String
    public var branch: String

    public static let unknownSpokenLine = "VoiceDesk, unknown version."
    public static let unknownSHASpokenLine = "VoiceDesk, unknown SHA."
    public static let unknown = BuildIdentity(marketing: "", build: "", shortSHA: "", branch: "")
    /// Test-only. Not a claim that this binary was built from that commit.
    public static let fixture = BuildIdentity(
        marketing: "0.1.0",
        build: "2",
        shortSHA: "1fa0a0e",
        branch: "cursor/cards-only-email-first-tap-9c2c"
    )

    public init(marketing: String = "", build: String = "", shortSHA: String = "", branch: String = "") {
        self.marketing = Self.normalizedMarketing(marketing)
        self.build = Self.normalizedBuild(build)
        self.shortSHA = Self.normalizedSHA(shortSHA)
        self.branch = Self.normalizedBranch(branch)
    }

    public init(infoDictionary: [String: Any]?) {
        let marketing = (infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? (infoDictionary?["MARKETING_VERSION"] as? String)
            ?? ""
        let build = (infoDictionary?["CFBundleVersion"] as? String)
            ?? (infoDictionary?["CURRENT_PROJECT_VERSION"] as? String)
            ?? ""
        self.init(
            marketing: marketing,
            build: build,
            shortSHA: infoDictionary?["GIT_SHA"] as? String ?? "",
            branch: infoDictionary?["GIT_BRANCH"] as? String ?? ""
        )
    }

    /// Default spoken desk reply. `"VoiceDesk 0.1, build 2."` or unknown — never a guessed version.
    public var spokenLine: String {
        guard let spokenMarketing, !build.isEmpty else {
            return Self.unknownSpokenLine
        }
        return "VoiceDesk \(spokenMarketing), build \(build)."
    }

    /// SHA-ask family only. `"VoiceDesk 1fa0a0e."` or unknown — never a guessed hash.
    public var spokenSHALine: String {
        if shortSHA.isEmpty {
            return Self.unknownSHASpokenLine
        }
        return "VoiceDesk \(shortSHA)."
    }

    /// Dogfood note: marketing, build integer, and short SHA so both identities are visible.
    public var dogfoodLine: String {
        let marketingPart = marketing.isEmpty ? "unknown" : marketing
        let buildPart = build.isEmpty ? "unknown" : build
        let shaPart = shortSHA.isEmpty ? "unknown" : shortSHA
        return "\(marketingPart) build \(buildPart) sha \(shaPart)"
    }

    /// Speak major.minor; keep a non-zero patch. Never four dotted numbers.
    public var spokenMarketing: String? {
        let parts = marketing.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        if parts.count == 3, parts[2] == "0" {
            return "\(parts[0]).\(parts[1])"
        }
        return marketing
    }

    private static func normalizedMarketing(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return ""
        }
        return trimmed
    }

    private static func normalizedBuild(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) else {
            return ""
        }
        return trimmed
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
