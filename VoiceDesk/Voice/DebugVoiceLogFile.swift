#if DEBUG
import Foundation
import VoiceDeskLogic

/// Local JSONL under Documents. DEBUG / dogfood only — never compiled in Release.
enum DebugVoiceLogFile {
    static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = docs.appendingPathComponent("VoiceDesk-debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("voice-log.jsonl")
    }

    static func append(_ entry: VoiceInteractionEntry) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entry),
              var line = String(data: data, encoding: .utf8)
        else { return }
        line.append("\n")
        guard let payload = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: payload)
            }
        } else {
            try? payload.write(to: fileURL)
        }
    }
}
#endif
