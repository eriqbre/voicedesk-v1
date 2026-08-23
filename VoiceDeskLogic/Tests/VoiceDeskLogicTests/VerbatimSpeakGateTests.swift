import XCTest
@testable import VoiceDeskLogic

final class VerbatimSpeakGateTests: XCTestCase {
    func testLeftoverDoneDoesNotFinishWhileAwaitingCreated() {
        var gate = VerbatimSpeakGate()
        gate.begin()
        XCTAssertTrue(gate.shouldIgnoreDone(currentID: "handoff-1"))
        XCTAssertFalse(gate.finishDone(currentID: "handoff-1"))
        XCTAssertTrue(gate.isSpeaking)
        XCTAssertTrue(gate.awaitingCreated)

        XCTAssertTrue(gate.created("verbatim-2"))
        XCTAssertFalse(gate.shouldIgnoreDone(eventID: "verbatim-2", currentID: "verbatim-2"))
        XCTAssertTrue(gate.finishDone(eventID: "verbatim-2", currentID: "verbatim-2"))
        XCTAssertFalse(gate.isSpeaking)
    }

    func testWrongResponseDoneIsIgnoredAfterCreated() {
        var gate = VerbatimSpeakGate()
        gate.begin()
        XCTAssertTrue(gate.created("verbatim-2"))
        XCTAssertTrue(gate.shouldIgnoreDone(currentID: "handoff-1"))
        XCTAssertFalse(gate.finishDone(currentID: "handoff-1"))
        XCTAssertTrue(gate.isSpeaking)
        XCTAssertTrue(gate.finishDone(currentID: "verbatim-2"))
        XCTAssertFalse(gate.isSpeaking)
    }

    func testLeftoverDoneAfterCreatedDoesNotRemuteWhenEventIDDiffers() {
        var gate = VerbatimSpeakGate()
        gate.begin()
        XCTAssertTrue(gate.created("verbatim-2"))
        // Inbox-overview / person-follow-up race: currentID already flipped.
        XCTAssertTrue(gate.shouldIgnoreDone(eventID: "handoff-1", currentID: "verbatim-2"))
        XCTAssertFalse(gate.finishDone(eventID: "handoff-1", currentID: "verbatim-2"))
        XCTAssertTrue(gate.isSpeaking)
        XCTAssertTrue(gate.finishDone(eventID: "verbatim-2", currentID: "verbatim-2"))
        XCTAssertFalse(gate.isSpeaking)
    }

    func testInboxDigestAndPersonFollowUpAreSpeakable() {
        let digest = ConversationPresence.inboxOverviewCopy([
            VoiceRegressionDesk.murray,
            VoiceRegressionDesk.steve
        ])
        XCTAssertEqual(DeskReplySpeech.textToSpeak(digest, lastSpoken: nil), digest)
        let madison = ConversationPresence.emailBodyReply(
            EmailItem(
                fromName: "John Madison",
                fromEmail: "john@example.com",
                sentAtLabel: "Today",
                subject: "Offer",
                preview: "Can we talk numbers",
                body: "Can we talk numbers on Beach Drive.",
                filterTag: "Inbox"
            )
        )
        XCTAssertEqual(DeskReplySpeech.textToSpeak(madison, lastSpoken: digest), madison)
        XCTAssertFalse(ConversationPresence.isGrokDeskMeta(digest))
        XCTAssertFalse(ConversationPresence.isGrokDeskMeta(madison))
    }

    func testVerbatimAudioWaitsForNonRefusalTranscript() {
        var gate = VerbatimSpeakGate()
        gate.begin()
        XCTAssertTrue(gate.created("verbatim-2"))
        XCTAssertFalse(gate.allowsAudio(deskClaimed: true))

        gate.hear("I can’t help with that.")
        XCTAssertFalse(gate.allowsAudio(deskClaimed: true))
        XCTAssertTrue(DeskSpokenPath.shouldDiscardHeldAudio(assistantText: gate.heard))

        gate.hear(" Murray Mitchell emailed about closing.")
        XCTAssertTrue(gate.allowsAudio(deskClaimed: true))
        XCTAssertFalse(DeskSpokenPath.isForbiddenLiveSpeech(DeskSpokenPath.strippingLeadingRefusal(gate.heard)))
    }
}
