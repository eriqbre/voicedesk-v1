import Foundation

/// DEBUG dogfood log locations. Path helpers only — no I/O, no transcripts.
///
/// Elon / Cursor agents on Eriq’s Mac should read:
/// `~/Desktop/projects/voicedesk-v1/.debug/voice-log.jsonl`
public enum VoiceDebugLogPaths: Sendable {
    public static let fileName = "voice-log.jsonl"
    public static let onDeviceFolderName = "VoiceDesk-debug"

    /// Relative to the Mac user home. Survives Simulator rebuilds; gitignored.
    public static let macHostRelativePath = "Desktop/projects/voicedesk-v1/.debug/voice-log.jsonl"

    /// Documented absolute hint (tilde). Same file as `macHostFileURL(home:)`.
    public static let documentedMacPath = "~/Desktop/projects/voicedesk-v1/.debug/voice-log.jsonl"

    /// After device **Save to Files → iCloud Drive → VoiceDesk-debug** (no chat paste).
    public static let documentedICloudDrivePath =
        "~/Library/Mobile Documents/com~apple~CloudDocs/VoiceDesk-debug/voice-log.jsonl"

    public static func macHostFileURL(home: String) -> URL {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("voicedesk-v1", isDirectory: true)
            .appendingPathComponent(".debug", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    public static func iCloudDriveFileURL(home: String) -> URL {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent(onDeviceFolderName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    public static func documentsFileURL(documentsDirectory: URL) -> URL {
        documentsDirectory
            .appendingPathComponent(onDeviceFolderName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    public static func ubiquityDocumentsFileURL(container: URL) -> URL {
        container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(onDeviceFolderName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// Simulator: `SIMULATOR_HOST_HOME`. Fallback: strip CoreSimulator sandbox prefix.
    public static func simulatorHostHome(
        environment: [String: String],
        sandboxHome: String? = nil
    ) -> String? {
        if let host = environment["SIMULATOR_HOST_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            return host
        }
        let sandbox = sandboxHome ?? environment["HOME"] ?? ""
        let marker = "/Library/Developer/CoreSimulator"
        guard let range = sandbox.range(of: marker) else { return nil }
        let home = String(sandbox[..<range.lowerBound])
        return home.isEmpty ? nil : home
    }

    public static func jsonlLineData(for entry: VoiceInteractionEntry) -> Data? {
        VoiceCloudLogCodec.jsonlLine(for: entry)
    }
}
