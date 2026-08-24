import XCTest
@testable import VoiceDeskLogic

final class GoogleSyncPolicyTests: XCTestCase {
    func testBaselineInboxLimitIs25() {
        XCTAssertEqual(GoogleSyncPolicy.recentInboxLimit, 25)
    }

    func testRestoreAlwaysRefreshesWhenConnectedAndOnline() {
        let stale = Date(timeIntervalSince1970: 100)
        let now = Date(timeIntervalSince1970: 200)
        XCTAssertTrue(
            GoogleSyncPolicy.shouldRefreshOnRestore(
                isConnected: true,
                isOnline: true,
                lastSyncedAt: stale,
                now: now
            ),
            "non-empty lastSyncedAt must still refresh on restore"
        )
        XCTAssertTrue(
            GoogleSyncPolicy.shouldRefreshOnRestore(
                isConnected: true,
                isOnline: true,
                lastSyncedAt: now,
                now: now
            )
        )
        XCTAssertTrue(
            GoogleSyncPolicy.shouldRefreshOnRestore(
                isConnected: true,
                isOnline: true,
                lastSyncedAt: nil,
                now: now
            )
        )
    }

    func testRestoreSkipsNetworkWhenOfflineOrDisconnected() {
        let stale = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(
            GoogleSyncPolicy.shouldRefreshOnRestore(
                isConnected: true,
                isOnline: false,
                lastSyncedAt: stale
            )
        )
        XCTAssertFalse(
            GoogleSyncPolicy.shouldRefreshOnRestore(
                isConnected: false,
                isOnline: true,
                lastSyncedAt: stale
            )
        )
    }

    func testLaunchFirstSnapshotDoesNotRequireAwaitingSync() throws {
        XCTAssertFalse(
            GoogleSyncPolicy.firstPaintRequiresAwaitingSync,
            "first frame must come from cache / local state, not await syncDesk"
        )
        XCTAssertTrue(
            GoogleSyncPolicy.shouldRefreshOnRestore(
                isConnected: true,
                isOnline: true,
                lastSyncedAt: Date(timeIntervalSince1970: 100)
            ),
            "connected + online restore must still refresh after first paint"
        )

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceDeskLaunch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let cache = FileDeskCache(directory: folder)
        let saved = DeskSnapshot(
            accountEmail: "ada@example.com",
            lastSyncedAt: Date(timeIntervalSince1970: 50),
            emails: [SampleData.syncedEmail()]
        )
        cache.save(saved)

        let firstPaint = GoogleSyncPolicy.snapshotForFirstPaint(from: cache)
        XCTAssertEqual(firstPaint.accountEmail, "ada@example.com")
        XCTAssertEqual(firstPaint.emails.first?.subject, "Inspection questions")
        XCTAssertEqual(firstPaint.lastSyncedAt, Date(timeIntervalSince1970: 50))
        XCTAssertTrue(
            GoogleSyncPolicy.shouldRefreshOnRestore(
                isConnected: true,
                isOnline: true,
                lastSyncedAt: firstPaint.lastSyncedAt
            )
        )
    }

    func testCacheAgeNoteUsesWholeSeconds() {
        let last = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_045)
        XCTAssertEqual(GoogleSyncPolicy.cacheAgeSeconds(lastSyncedAt: last, now: now), 45)
        XCTAssertEqual(GoogleSyncPolicy.cacheAgeNote(lastSyncedAt: last, now: now), "cacheAgeSec=45")
        XCTAssertNil(GoogleSyncPolicy.cacheAgeNote(lastSyncedAt: nil, now: now))
    }
}
