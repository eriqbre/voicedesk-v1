import XCTest
@testable import VoiceDeskLogic

/// Live Talk is Eve only. Desk write-TTS + Eve path on the same turn
/// is two mouths. The device walk (version drain, skipped-glance stub,
/// person drain, voicePath Eve, no Eve PCM) must fail this gate.
final class LiveTalkMouthTests: XCTestCase {
    func testDeskDrainWithEvePathAndSkippedGlanceStubIsDualMouth() {
        let walk = LiveTalkMouth.deskDrainAlignedWithEvePathAndSkippedGlanceStub()
        XCTAssertTrue(walk.afterDeskTTSDrain)
        XCTAssertTrue(walk.eveVoicePath)
        XCTAssertTrue(walk.skippedGlanceStubFirstAudio)
        XCTAssertTrue(walk.clientVoiceSpeechWrite)
        XCTAssertTrue(
            walk.isDualMouth,
            "desk drain + Eve path on the same turn is two mouths"
        )
        XCTAssertFalse(LiveTalkMouth.liveTalkEveOnly().isDualMouth)
        XCTAssertFalse(LiveTalkMouth.offlineClientTTS().isDualMouth)
    }

    func testLiveTalkSpeaksViaEveWhenSocketUp() {
        XCTAssertTrue(
            LiveTalkMouth.speaksViaEve(
                liveSessionArmed: true,
                socketConnected: true,
                userWantsVoiceOff: false
            )
        )
        XCTAssertFalse(
            LiveTalkMouth.speaksViaEve(
                liveSessionArmed: true,
                socketConnected: false,
                userWantsVoiceOff: false
            ),
            "down socket keeps ClientVoiceSpeech"
        )
        XCTAssertFalse(
            LiveTalkMouth.speaksViaEve(
                liveSessionArmed: false,
                socketConnected: true,
                userWantsVoiceOff: false
            )
        )
        XCTAssertFalse(
            LiveTalkMouth.speaksViaEve(
                liveSessionArmed: true,
                socketConnected: true,
                userWantsVoiceOff: true
            )
        )
    }

    func testLiveSpeakDoesNotWriteDeskTTSOrEmitDrain() throws {
        let source = try XCTUnwrap(repoFile("VoiceDesk/Voice/GrokVoiceService.swift"))
        let speakFn = speakSlice(
            source,
            from: "func speak(_ text: String) async {",
            to: "private func returnToListenAfterDeskTTS"
        )
        XCTAssertTrue(speakFn.contains("shouldSpeakViaRealtime"), speakFn)
        XCTAssertFalse(
            speakFn.contains("speakLiveReplyViaEve"),
            "live VAD must not stack a second response.create"
        )
        XCTAssertFalse(speakFn.contains("responseCreateObject"), speakFn)
        XCTAssertFalse(speakFn.contains("verbatimSpeakSessionUpdateObject"), speakFn)
        XCTAssertTrue(speakFn.contains("ClientVoiceSpeech.shared.speak"), speakFn)
        XCTAssertFalse(speakFn.contains("synthesizer.speak("), speakFn)
        XCTAssertFalse(speakFn.contains("resumeCapture"), speakFn)
        XCTAssertFalse(speakFn.contains("rearmTap"), speakFn)
        XCTAssertFalse(speakFn.contains("keepListeningAfterClientTTS"), speakFn)
        XCTAssertFalse(speakFn.contains("speakVerbatimViaGrok"), speakFn)
        XCTAssertFalse(source.contains("private func speakLiveReplyViaEve"), source)

        let app = try XCTUnwrap(repoFile("VoiceDesk/AppModel.swift"))
        let desk = speakSlice(app, from: "private func speakDeskReply", to: "private func rememberUserTurn")
        XCTAssertTrue(desk.contains("voice.speak(spoken)"), desk)
        XCTAssertFalse(desk.contains("ClientVoiceSpeech"), desk)
    }

    private func speakSlice(_ source: String, from: String, to: String) -> String {
        guard let start = source.range(of: from),
              let end = source.range(of: to, range: start.upperBound..<source.endIndex)
        else { return "" }
        return String(source[start.lowerBound..<end.lowerBound])
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
