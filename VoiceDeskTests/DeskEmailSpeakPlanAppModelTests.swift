import XCTest
import VoiceDeskLogic
@testable import VoiceDesk

@MainActor
final class DeskEmailSpeakPlanAppModelTests: XCTestCase {
    func testLoadedEmailSpeaksHeuristicWithoutAwaitingSummarizer() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = nil
        murray.subject = "Lot walk"
        murray.body = "Walk the lot Saturday at 10."
        let summarizer = TTFAHangingEmailSummarizer()
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [murray])),
            emailSummarizer: summarizer
        )

        await model.applyUserTurn("summarize Murray's email")

        XCTAssertFalse(fake.spoken.isEmpty, "firstAudio must not wait on xaiSummarize")
        XCTAssertEqual(fake.spoken.count, 1, "must not speak the digest a second time")
        let reply = model.turns.last?.text ?? ""
        XCTAssertEqual(fake.spoken.last, reply)
        XCTAssertTrue(
            reply.contains("Walk the lot Saturday") || reply.contains("Murray"),
            reply
        )
        XCTAssertFalse(EmailSummary.containsUIChrome(reply), reply)

        await waitUntil { summarizer.summarizeCalls >= 1 }
        XCTAssertEqual(fake.spoken.count, 1)
        summarizer.release("Murray wants a Saturday lot walk. I’ve put it on a card.")
        await Task.yield()
        XCTAssertEqual(fake.spoken.count, 1, "polish must not speak again")
        let upgraded = model.turns.last?.text ?? ""
        XCTAssertFalse(EmailSummary.containsUIChrome(upgraded), upgraded)
        XCTAssertTrue(
            upgraded.contains("Walk the lot Saturday") || upgraded.contains("Saturday lot walk"),
            upgraded
        )
    }

    func testSummarizerFailureStillSpeaksHeuristic() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = nil
        murray.subject = "Closing / notarization"
        murray.body = "Need you to notarize the closing package Thursday."
        let summarizer = ImmediateFailEmailSummarizer()
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [murray])),
            emailSummarizer: summarizer
        )

        await model.applyUserTurn("summarize Murray's email")

        XCTAssertEqual(fake.spoken.count, 1)
        let reply = model.turns.last?.text ?? ""
        XCTAssertEqual(fake.spoken.last, reply)
        XCTAssertTrue(reply.localizedCaseInsensitiveContains("notarize"), reply)
        XCTAssertFalse(EmailSummary.containsUIChrome(reply), reply)
        await Task.yield()
        XCTAssertEqual(fake.spoken.count, 1)
        XCTAssertEqual(model.turns.last?.text, reply)
    }

    func testBodyFetchThenSpeakDoesNotWaitOnHangingSummarizer() async {
        var murray = SampleData.syncedEmail()
        murray.fromName = "Murray Mitchell"
        murray.providerID = "msg-murray-ttfa"
        murray.subject = "Lot walk"
        murray.body = nil
        murray.preview = "Snippet only"
        let sync = MockGoogleSync(result: DeskSnapshot(emails: [murray]))
        sync.bodies["msg-murray-ttfa"] = "Walk the lot Saturday at 10."
        let summarizer = TTFAHangingEmailSummarizer()
        let fake = FakeLiveVoiceService()
        let model = AppModel(
            voice: fake,
            google: .mock(connected: true),
            cache: MemoryDeskCache(snapshot: DeskSnapshot(emails: [murray])),
            sync: sync,
            emailSummarizer: summarizer
        )

        await model.applyUserTurn("summarize Murray's email")

        XCTAssertEqual(sync.fetchCalls, 1)
        XCTAssertFalse(fake.spoken.isEmpty)
        XCTAssertTrue(
            (fake.spoken.last ?? "").contains("Walk the lot Saturday")
                || (model.turns.last?.text ?? "").contains("Walk the lot Saturday")
        )
        summarizer.release()
        await Task.yield()
        XCTAssertEqual(fake.spoken.count, 1)
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<40 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out waiting for summarizer kick")
    }
}

@MainActor
final class TTFAHangingEmailSummarizer: EmailSummarizing, @unchecked Sendable {
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var summarizeCalls = 0

    func summarize(_ request: EmailSummaryRequest) async -> String {
        _ = request
        return await withCheckedContinuation { continuation in
            self.summarizeCalls += 1
            self.continuation = continuation
        }
    }

    func release(_ text: String = "Murray wants to walk the lot Saturday.") {
        continuation?.resume(returning: text)
        continuation = nil
    }
}

@MainActor
final class ImmediateFailEmailSummarizer: EmailSummarizing, @unchecked Sendable {
    func summarize(_ request: EmailSummaryRequest) async -> String {
        _ = request
        return ""
    }
}
