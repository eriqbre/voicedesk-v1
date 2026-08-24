import XCTest
@testable import VoiceDeskLogic

final class DeskSpokenPathTests: XCTestCase {
    func testDeskClaimDropsRefusalAndHandoffFromSpokenPath() {
        let murray = "Give me a quick summary of Murray's latest email."
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(murray), murray)

        for phrase in [
            "I can’t help with that.",
            "I can't help with that.",
            "I’m not able to do that.",
            "I'm not able to help.",
            "I cannot help with that.",
            "I’ll let the app handle that.",
            "I'll let the app handle that."
        ] {
            XCTAssertTrue(DeskSpokenPath.isForbiddenLiveSpeech(phrase), phrase)
            XCTAssertTrue(ConversationPresence.isGrokDeskMeta(phrase), phrase)
            XCTAssertTrue(ConversationPresence.isGrokCapabilityRefusal(phrase) || ConversationPresence.isGrokDeskHandoff(phrase), phrase)
            XCTAssertEqual(DeskSpokenPath.strippingLeadingRefusal(phrase), "")
            XCTAssertFalse(
                DeskSpokenPath.allowsLiveGrokAudio(
                    deskClaimed: true,
                    verbatimSpeaking: false,
                    assistantText: phrase
                ),
                phrase
            )
            XCTAssertTrue(DeskSpokenPath.shouldDiscardHeldAudio(assistantText: phrase), phrase)
        }
    }

    func testVerbatimDigestStillPlaysAfterRefusalPrefix() {
        let digest = "Murray Mitchell emailed about closing. He wrote: Need you to notarize today."
        XCTAssertFalse(DeskSpokenPath.isForbiddenLiveSpeech(digest))
        XCTAssertFalse(ConversationPresence.isGrokCapabilityRefusal(digest))

        XCTAssertFalse(
            DeskSpokenPath.allowsLiveGrokAudio(
                deskClaimed: true,
                verbatimSpeaking: true,
                assistantText: ""
            ),
            "hold Eve audio until we know it is not a refusal"
        )
        XCTAssertFalse(
            DeskSpokenPath.allowsLiveGrokAudio(
                deskClaimed: true,
                verbatimSpeaking: true,
                assistantText: "I can’t help with that."
            )
        )
        XCTAssertTrue(
            DeskSpokenPath.allowsLiveGrokAudio(
                deskClaimed: true,
                verbatimSpeaking: true,
                assistantText: "I can’t help with that. \(digest)"
            ),
            "strip the refusal prefix; play the Eve summary"
        )
        XCTAssertEqual(
            DeskSpokenPath.strippingLeadingRefusal("I can’t help with that. \(digest)"),
            digest
        )
        XCTAssertTrue(
            DeskSpokenPath.allowsLiveGrokAudio(
                deskClaimed: true,
                verbatimSpeaking: true,
                assistantText: digest
            )
        )
        XCTAssertTrue(
            GrokRealtime.shouldSpeakViaRealtime(
                usesLiveLoop: true,
                isConnected: true,
                userWantsVoiceOff: false
            )
        )
        let prompt = GrokRealtime.verbatimSpeakUserText(text: digest)
        XCTAssertTrue(GrokRealtime.isVerbatimSpeakPrompt(prompt))
        XCTAssertTrue(prompt.contains(digest))
        XCTAssertTrue(GrokRealtime.verbatimSpeakInstructions(text: digest).contains("cannot help"))
        XCTAssertTrue(GrokRealtime.verbatimSpeakInstructions(text: digest).contains("not able to"))
        XCTAssertEqual(DeskReplySpeech.textToSpeak(digest, lastSpoken: nil), digest)
    }

    func testQuotedCantHelpInLongDigestIsNotARefusal() {
        let quoted = """
        Murray Mitchell emailed about the inspection. He wrote: I can't help Friday, \
        send the punch list to Steve. Need you to notarize the closing package today.
        """
        XCTAssertFalse(ConversationPresence.isGrokCapabilityRefusal(quoted), quoted)
        XCTAssertFalse(DeskSpokenPath.isForbiddenLiveSpeech(quoted), quoted)
        XCTAssertTrue(
            DeskSpokenPath.allowsLiveGrokAudio(
                deskClaimed: true,
                verbatimSpeaking: true,
                assistantText: quoted
            )
        )
        XCTAssertEqual(DeskSpokenPath.strippingLeadingRefusal(quoted), quoted)
    }

    func testClaimedHandoffStaysMutedUntilVerbatimDigest() {
        XCTAssertFalse(
            DeskSpokenPath.allowsLiveGrokAudio(
                deskClaimed: true,
                verbatimSpeaking: false,
                assistantText: "I’ll let the app handle that."
            )
        )
        XCTAssertTrue(
            DeskSpokenPath.allowsLiveGrokAudio(
                deskClaimed: false,
                verbatimSpeaking: false,
                assistantText: "John Wick came out in 2014."
            ),
            "general Grok turns still speak"
        )
    }

    func testGrokVoiceServiceDoesNotReintroduceMicMuteOrHalfDuplex() throws {
        let service = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        XCTAssertFalse(service.contains("captureGate"))
        XCTAssertFalse(service.contains("beginHalfDuplex"))
        XCTAssertFalse(service.contains("muteMic"))
        XCTAssertFalse(service.contains("micMuted"))
        XCTAssertFalse(service.contains("captureEnabled"))
        XCTAssertTrue(service.contains("allowsAudio"))
        XCTAssertTrue(service.contains("heldVerbatimAudio"))
        XCTAssertTrue(service.contains("DeskSpokenPath"))

        let session = try XCTUnwrap(repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/VoiceSession.swift"))
        XCTAssertFalse(session.contains("halfDuplex"))
        XCTAssertFalse(session.contains("captureGate"))
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
}
