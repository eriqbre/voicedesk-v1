import XCTest
@testable import VoiceDeskLogic

final class LaunchSyncStatusTests: XCTestCase {
    func testGenericWhenCountUnknownOrZero() {
        XCTAssertEqual(LaunchSyncStatus.stem(for: .restoringGoogle), "Restoring Google")
        XCTAssertEqual(LaunchSyncStatus.stem(for: .syncingInbox), "Syncing inbox")
        XCTAssertNil(LaunchSyncStatus.downloadingStem(count: 0))
        XCTAssertNil(LaunchSyncStatus.downloadingStem(count: -3))
        XCTAssertEqual(
            LaunchSyncStatus.phaseAfterInboxIDs([], cachedProviderIDs: []),
            .syncingInbox,
            "empty list is unknown — stay generic, do not invent mail"
        )
        XCTAssertEqual(
            LaunchSyncStatus.phaseAfterInboxIDs(["a", "b"], cachedProviderIDs: ["a", "b"]),
            .syncingInbox,
            "already-cached IDs are not new"
        )
        XCTAssertNotEqual(
            LaunchSyncStatus.stem(for: .syncingInbox),
            "Downloading \(GoogleSyncPolicy.recentInboxLimit) new emails"
        )
        XCTAssertNil(LaunchSyncStatus.stem(for: .idle))
    }

    func testDownloadingCopyUsesOnlyRealPositiveCount() {
        XCTAssertEqual(LaunchSyncStatus.downloadingStem(count: 1), "Downloading 1 new email")
        XCTAssertEqual(LaunchSyncStatus.downloadingStem(count: 25), "Downloading 25 new emails")
        XCTAssertEqual(
            LaunchSyncStatus.phaseAfterInboxIDs(["n1", "n2", "n3"], cachedProviderIDs: ["old"]),
            .downloadingNewEmails(3)
        )
        XCTAssertEqual(
            LaunchSyncStatus.stem(for: .downloadingNewEmails(3)),
            "Downloading 3 new emails"
        )
        XCTAssertEqual(
            LaunchSyncStatus.phaseAfterInboxIDs(["only"], cachedProviderIDs: []),
            .downloadingNewEmails(1)
        )
        XCTAssertNotEqual(
            LaunchSyncStatus.phaseAfterInboxIDs(["only"], cachedProviderIDs: []),
            .downloadingNewEmails(GoogleSyncPolicy.recentInboxLimit),
            "never substitute the 25 pull limit for a missing count"
        )
        XCTAssertTrue(LaunchSyncStatus.animatesDots(.syncingInbox))
        XCTAssertTrue(LaunchSyncStatus.animatesDots(.downloadingNewEmails(2)))
        XCTAssertFalse(LaunchSyncStatus.animatesDots(.inboxUpToDate))
        XCTAssertFalse(LaunchSyncStatus.animatesDots(.refreshFailed))
    }

    func testFinishedAndFailedCopyAreSilentAndNotSpoken() {
        XCTAssertEqual(LaunchSyncStatus.stem(for: .inboxUpToDate), "Inbox up to date")
        XCTAssertEqual(LaunchSyncStatus.stem(for: .refreshFailed), "Couldn’t refresh inbox")
        for text in [
            "Restoring Google…",
            "Syncing inbox…",
            "Downloading 25 new emails…",
            LaunchSyncStatus.upToDateText,
            LaunchSyncStatus.failedText
        ] {
            XCTAssertTrue(LaunchSyncStatus.isSilent(text), text)
            XCTAssertNil(DeskReplySpeech.textToSpeak(text, lastSpoken: nil), text)
        }
        XCTAssertFalse(LaunchSyncStatus.isSilent("I found a few matches. Which one?"))
        XCTAssertEqual(
            DeskReplySpeech.textToSpeak(ConversationPresence.gmailSearchSeveralReply, lastSpoken: nil),
            ConversationPresence.gmailSearchSeveralReply
        )
    }
}
