import Foundation

/// Whether this build can present GIDSignIn without hanging on a placeholder URL scheme.
public enum GoogleSignInSetup: Sendable {
    public static let placeholderReversedClientID = "com.googleusercontent.apps.REPLACE_ME"
    /// Safety net so `connecting` cannot last forever if GIDSignIn never returns.
    public static let signInTimeoutSeconds: TimeInterval = 90

    public enum Diagnosis: Equatable, Sendable {
        case ready(clientID: String, reversedClientID: String)
        case incomplete(String)
    }

    public static func isPlaceholder(_ value: String?) -> Bool {
        let trimmed = trimmedOrEmpty(value)
        if trimmed.isEmpty { return true }
        if trimmed.contains("REPLACE_ME") { return true }
        if trimmed == "$(GOOGLE_REVERSED_CLIENT_ID)" || trimmed == "$(GOOGLE_CLIENT_ID)" {
            return true
        }
        return false
    }

    public static func resolvedReversedClientID(clientID: String?, reversedOverride: String?) -> String? {
        if !isPlaceholder(reversedOverride) {
            return trimmedOrEmpty(reversedOverride)
        }
        return clientID.flatMap(GoogleScopes.reversedClientID)
    }

    public static func diagnose(
        clientID: String?,
        reversedOverride: String?,
        registeredSchemes: [String]
    ) -> Diagnosis {
        if isPlaceholder(clientID) {
            return .incomplete(GoogleAuthSnapshot.missingClientIDCopy)
        }
        let client = trimmedOrEmpty(clientID)
        guard let reversed = resolvedReversedClientID(clientID: client, reversedOverride: reversedOverride) else {
            return .incomplete(GoogleAuthSnapshot.missingReversedClientIDCopy)
        }
        let usable = registeredSchemes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !isPlaceholder($0) }
        if usable.contains(reversed) {
            return .ready(clientID: client, reversedClientID: reversed)
        }
        return .incomplete(GoogleAuthSnapshot.missingReversedClientIDCopy)
    }

    private static func trimmedOrEmpty(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
