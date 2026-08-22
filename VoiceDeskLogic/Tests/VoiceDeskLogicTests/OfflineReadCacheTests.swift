import XCTest
@testable import VoiceDeskLogic

final class OfflineReadCacheTests: XCTestCase {
    func testFileCacheRoundTripAndSignOutClears() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDeskCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let cache = FileDeskCache(directory: folder)
        XCTAssertEqual(cache.load(), .empty)

        let snapshot = DeskSnapshot(
            accountEmail: "ada@example.com",
            lastSyncedAt: Date(timeIntervalSince1970: 100),
            emails: [SampleData.syncedEmail()],
            events: [SampleData.calendarEvent()],
            tasks: [SampleData.openTask()]
        )
        cache.save(snapshot)

        let loaded = cache.load()
        XCTAssertEqual(loaded.accountEmail, "ada@example.com")
        XCTAssertEqual(loaded.emails.count, 1)
        XCTAssertEqual(loaded.emails[0].subject, "Inspection questions")
        XCTAssertEqual(loaded.events[0].title, "Saturday showing")
        XCTAssertEqual(loaded.tasks[0].title, "Confirm inspection window")

        cache.clear()
        let cleared = cache.load()
        XCTAssertEqual(cleared, .empty)
        XCTAssertTrue(cleared.emails.isEmpty)
        XCTAssertNil(cleared.accountEmail)
    }

    func testMemoryCacheSignOutClearsBodies() {
        let cache = MemoryDeskCache(snapshot: DeskSnapshot(emails: [SampleData.syncedEmail()]))
        XCTAssertEqual(cache.load().emails.count, 1)
        cache.clear()
        XCTAssertTrue(cache.load().emails.isEmpty)
    }
}
