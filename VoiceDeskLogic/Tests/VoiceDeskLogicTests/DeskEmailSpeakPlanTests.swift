import XCTest
@testable import VoiceDeskLogic

final class DeskEmailSpeakPlanTests: XCTestCase {
    func testBodyAvailableSpeaksHeuristicWithoutAwaitingSummarizer() async {
        let request = EmailSummaryRequest(
            fromName: "Murray Mitchell",
            subject: "Lot walk",
            body: "Walk the lot Saturday at 10."
        )
        let summarizer = HangingEmailSummarizer()

        let started = Date()
        let plan = DeskEmailSpeakPlan.afterBodyAvailable(request)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 0.05, "speak plan must be sync — no xAI wait")
        XCTAssertEqual(summarizer.summarizeCalls, 0, "summarizer must not run before firstAudio")
        XCTAssertFalse(DeskEmailSpeakPlan.firstAudioWaitsOnXAISummarize(plan.stagesBeforeFirstAudio))
        XCTAssertEqual(plan.stagesBeforeFirstAudio, ["gmailFetch", "heuristic"])
        XCTAssertFalse(plan.stagesBeforeFirstAudio.contains("xaiSummarize"))
        XCTAssertTrue(
            plan.spokenText.contains("Walk the lot Saturday") || plan.spokenText.contains("Murray"),
            plan.spokenText
        )
        XCTAssertTrue(plan.voiceLogNotes.contains("firstAudio skipped xaiSummarize"))
        XCTAssertEqual(DeskReplySpeech.textToSpeak(plan.spokenText, lastSpoken: nil), plan.spokenText)

        let polishTask = Task { await summarizer.summarize(request) }
        await waitUntil { summarizer.summarizeCalls == 1 }
        XCTAssertFalse(plan.spokenText.contains("cloud polish"))
        summarizer.fail()
        _ = await polishTask.value
    }

    func testSummarizerFailureStillYieldsHeuristicSpeak() async {
        let request = EmailSummaryRequest(
            fromName: "Murray Mitchell",
            subject: "Closing / notarization",
            body: """
            Hey — two quick questions:
            1. Can you notarize the closing package Thursday?
            2. Is the buyer still set for 3pm on Beach Drive?
            """
        )
        let plan = DeskEmailSpeakPlan.afterBodyAvailable(request, didFetchBody: true)
        let polished = await FailingEmailSummarizer().summarize(request)

        XCTAssertFalse(DeskEmailSpeakPlan.firstAudioWaitsOnXAISummarize(plan.stagesBeforeFirstAudio))
        XCTAssertTrue(plan.spokenText.localizedCaseInsensitiveContains("notarize"), plan.spokenText)
        XCTAssertTrue(polished.isEmpty, "failed polish must not replace the already-spoken heuristic")
        XCTAssertNil(DeskEmailSpeakPlan.cardTextUpgrade(spoken: plan.spokenText, polished: polished))
        XCTAssertFalse(EmailSummary.containsUIChrome(plan.spokenText), plan.spokenText)
    }

    func testCachedBodyOmitsGmailFetchStage() {
        let request = EmailSummaryRequest(
            fromName: "Murray Mitchell",
            subject: "Lot walk",
            body: "Walk the lot Saturday at 10."
        )
        let plan = DeskEmailSpeakPlan.afterBodyAvailable(request, didFetchBody: false)
        XCTAssertEqual(plan.stagesBeforeFirstAudio, ["heuristic"])
        XCTAssertFalse(DeskEmailSpeakPlan.firstAudioWaitsOnXAISummarize(plan.stagesBeforeFirstAudio))
    }

    func testCardUpgradeIsQuietAndSkipsChromeOrDuplicate() {
        let spoken = "Murray wrote about the lot walk. Walk the lot Saturday at 10."
        XCTAssertEqual(
            DeskEmailSpeakPlan.cardTextUpgrade(
                spoken: spoken,
                polished: "Murray wants you at the lot Saturday at 10. I’ve put it on a card."
            ),
            "Murray wants you at the lot Saturday at 10."
        )
        XCTAssertNil(DeskEmailSpeakPlan.cardTextUpgrade(spoken: spoken, polished: spoken))
        XCTAssertNil(DeskEmailSpeakPlan.cardTextUpgrade(spoken: spoken, polished: ""))
        XCTAssertNil(DeskEmailSpeakPlan.cardTextUpgrade(spoken: spoken, polished: "See the card."))
    }

    func testApplyLoadedEmailDoesNotAwaitSummarizerBeforeSpeak() throws {
        let source = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"), "AppModel.swift")
        let fn = "private func applyLoadedEmail"
        guard let start = source.range(of: fn) else {
            XCTFail("applyLoadedEmail missing")
            return
        }
        let after = source[start.lowerBound...]
        let nextFn = after.range(of: "\n    private func ", options: [], range: after.index(after.startIndex, offsetBy: fn.count)..<after.endIndex)
        let body = String(after[..<(nextFn?.lowerBound ?? after.endIndex)])

        XCTAssertTrue(body.contains("DeskEmailSpeakPlan.afterBodyAvailable"), body)
        XCTAssertTrue(body.contains("speakDeskReply"), body)
        guard let speakRange = body.range(of: "speakDeskReply") else {
            return
        }
        let beforeSpeak = String(body[..<speakRange.lowerBound])
        XCTAssertFalse(
            beforeSpeak.contains("emailSummarizer.summarize"),
            "firstAudio must not await xaiSummarize"
        )
        XCTAssertFalse(beforeSpeak.contains("await emailSummarizer"))
        XCTAssertTrue(
            body.contains("kickBackgroundEmailPolish") || body.contains("emailSummarizer.summarize"),
            "optional async polish may still run after speak"
        )
        XCTAssertFalse(source.contains("captureGate"))
        XCTAssertFalse(source.contains("beginHalfDuplex"))
        XCTAssertFalse(source.contains("MicrophoneCaptureGate"))
    }

    private func repoFile(_ relative: String) -> String? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try? String(contentsOf: candidate, encoding: .utf8)
            }
        }
        return nil
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<40 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out")
    }
}

/// Never resumes unless `fail()` is called — proves firstAudio is not gated on it.
final class HangingEmailSummarizer: EmailSummarizing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var summarizeCalls = 0

    func summarize(_ request: EmailSummaryRequest) async -> String {
        _ = request
        return await withCheckedContinuation { continuation in
            lock.lock()
            summarizeCalls += 1
            self.continuation = continuation
            lock.unlock()
        }
    }

    func fail() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: "")
    }
}

final class FailingEmailSummarizer: EmailSummarizing, @unchecked Sendable {
    func summarize(_ request: EmailSummaryRequest) async -> String {
        _ = request
        return ""
    }
}
