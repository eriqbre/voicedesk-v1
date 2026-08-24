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

    func testCacheAgeNoteUsesWholeSeconds() {
        let last = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_045)
        XCTAssertEqual(GoogleSyncPolicy.cacheAgeSeconds(lastSyncedAt: last, now: now), 45)
        XCTAssertEqual(GoogleSyncPolicy.cacheAgeNote(lastSyncedAt: last, now: now), "cacheAgeSec=45")
        XCTAssertNil(GoogleSyncPolicy.cacheAgeNote(lastSyncedAt: nil, now: now))
    }
}
