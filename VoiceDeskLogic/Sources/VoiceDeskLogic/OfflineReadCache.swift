import Foundation

public protocol DeskCaching: AnyObject {
    func load() -> DeskSnapshot
    func save(_ snapshot: DeskSnapshot)
    func clear()
}

public final class MemoryDeskCache: DeskCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: DeskSnapshot

    public init(snapshot: DeskSnapshot = .empty) {
        self.snapshot = snapshot
    }

    public func load() -> DeskSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    public func save(_ snapshot: DeskSnapshot) {
        lock.lock()
        self.snapshot = snapshot
        lock.unlock()
    }

    public func clear() {
        save(.empty)
    }
}

/// Last-synced reads on disk. Sign-out must call `clear()`.
public final class FileDeskCache: DeskCaching, @unchecked Sendable {
    public static let defaultFilename = "voicedesk-desk-snapshot.json"

    private let url: URL
    private let lock = NSLock()

    public init(directory: URL, filename: String = defaultFilename) {
        self.url = directory.appendingPathComponent(filename)
    }

    public static func applicationSupport() -> FileDeskCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("VoiceDesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return FileDeskCache(directory: folder)
    }

    public func load() -> DeskSnapshot {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder().decode(DeskSnapshot.self, from: data)) ?? .empty
    }

    public func save(_ snapshot: DeskSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }
}
