#if DEBUG
import Foundation
import VoiceDeskLogic
#if canImport(UIKit)
import UIKit
#endif

/// DEBUG / dogfood only. Appends the same JSONL line to every resolvable destination.
/// Release compiles this file out — no write, no upload.
enum DebugVoiceLogFile {
    private static let lock = NSLock()
    private static var recordedPaths: [String] = []

    /// Paths last written this process (for the ladybug sheet).
    static var lastWrittenPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPaths
    }

    static var documentsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return VoiceDebugLogPaths.documentsFileURL(documentsDirectory: docs)
    }

    /// Prefer the Mac-stable file when the Simulator can see the host home.
    static var primaryFileURL: URL {
        destinations().first ?? documentsFileURL
    }

    static func destinations() -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        func add(_ url: URL?) {
            guard let url else { return }
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted else { return }
            urls.append(url)
        }

        let env = ProcessInfo.processInfo.environment
        if let hostHome = VoiceDebugLogPaths.simulatorHostHome(
            environment: env,
            sandboxHome: NSHomeDirectory()
        ) {
            add(VoiceDebugLogPaths.macHostFileURL(home: hostHome))
        }

        add(documentsFileURL)

        // Nil without an iCloud Documents entitlement — safe no-op on most dogfood builds.
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            add(VoiceDebugLogPaths.ubiquityDocumentsFileURL(container: container))
        }

        return urls
    }

    static func append(_ entry: VoiceInteractionEntry) {
        guard let payload = VoiceDebugLogPaths.jsonlLineData(for: entry) else { return }
        var written: [String] = []
        for url in destinations() {
            if write(payload, to: url) {
                written.append(url.path)
            }
        }
        lock.lock()
        recordedPaths = written
        lock.unlock()
    }

    static func ensurePlaceholderFiles() {
        let empty = Data()
        var written: [String] = []
        for url in destinations() {
            let folder = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? empty.write(to: url)
            }
            if FileManager.default.fileExists(atPath: url.path) {
                written.append(url.path)
            }
        }
        lock.lock()
        if recordedPaths.isEmpty {
            recordedPaths = written
        }
        lock.unlock()
    }

    /// Opens the on-device Documents folder in Files (device / Simulator).
    static func revealInFiles() {
        ensurePlaceholderFiles()
        let folder = documentsFileURL.deletingLastPathComponent()
        #if canImport(UIKit)
        var components = URLComponents(url: folder, resolvingAgainstBaseURL: false)
        components?.scheme = "shareddocuments"
        if let url = components?.url {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private static func write(_ payload: Data, to url: URL) -> Bool {
        let folder = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: payload)
            } else {
                try payload.write(to: url)
            }
            return true
        } catch {
            return false
        }
    }
}
#endif
