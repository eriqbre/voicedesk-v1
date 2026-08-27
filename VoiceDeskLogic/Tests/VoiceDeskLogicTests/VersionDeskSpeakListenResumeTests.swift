import XCTest
@testable import VoiceDeskLogic

/// Desk speak is on-device TTS. The live socket stays in listen.
/// Synonym families. Intent / stayLive / cards — never Eve’s exact wording.
final class VersionDeskSpeakListenResumeTests: XCTestCase {
    static let versionFamily = [
        "what version are we on",
        "What version are we on?",
        "what build",
        "what build is this",
        "what's on the phone",
        "um what version are we on",
        "uh what build is this",
        "What's. what version are we on"
    ]

    static let shaFamily = [
        "what SHA is this",
        "what's the SHA",
        "which git hash"
    ]

    static let glanceAfterVersionFamily = [
        "Okay, show me my latest emails.",
        "okay, show me my latest emails",
        "show me my latest emails",
        "tell me my emails"
    ]

    func testVersionFamilyCompletesOnDeviceTTSAndStaysLive() {
        for ask in Self.versionFamily {
            let walk = VersionDeskSpeakWalk.versionAskThenClientTTSThenClose1000(ask: ask)
            XCTAssertEqual(walk.spokenIntent, "version", ask)
            XCTAssertFalse(walk.cardsAttached, "identity stays cards-only: \(ask)")
            XCTAssertTrue(walk.spokenLineCompleted, ask)
            XCTAssertFalse(walk.usesGrokVerbatim, ask)
            XCTAssertTrue(walk.listenArmedDuringTTS, "mic stays live through client TTS: \(ask)")
            XCTAssertTrue(walk.listenArmedAfterSpeak, ask)
            XCTAssertTrue(walk.close1000StayLive, ask)
            XCTAssertEqual(walk.close1000Decision, .reconnect, ask)
            XCTAssertNotEqual(walk.close1000Decision, .stayIdle, ask)
        }
    }

    func testSHAFamilyCompletesOnDeviceTTSAndStaysLive() {
        for ask in Self.shaFamily {
            let walk = VersionDeskSpeakWalk.versionAskThenClientTTSThenClose1000(ask: ask)
            XCTAssertEqual(walk.spokenIntent, "version", ask)
            XCTAssertFalse(walk.cardsAttached, ask)
            XCTAssertTrue(walk.spokenLineCompleted, ask)
            XCTAssertFalse(walk.usesGrokVerbatim, ask)
            XCTAssertTrue(walk.listenArmedDuringTTS, "mic stays live through client TTS: \(ask)")
            XCTAssertTrue(walk.listenArmedAfterSpeak, ask)
            XCTAssertEqual(walk.close1000Decision, .reconnect, ask)
        }
    }

    func testUserStopAfterVersionSpeakStaysIdle() {
        let walk = VersionDeskSpeakWalk.versionAskThenClientTTSThenClose1000(
            ask: "what version are we on",
            userWantsVoiceOff: true
        )
        XCTAssertFalse(walk.listenArmedDuringTTS)
        XCTAssertFalse(walk.listenArmedAfterSpeak)
        XCTAssertFalse(walk.close1000StayLive)
        XCTAssertEqual(walk.close1000Decision, .stayIdle)
    }

    func testGlanceAfterVersionStaysCacheFirst() {
        let snapshot = VoiceRegressionDesk.snapshot
        XCTAssertFalse(snapshot.glanceEmails.isEmpty)
        for glance in Self.glanceAfterVersionFamily {
            let walk = VersionDeskSpeakWalk.versionAskThenClientTTSThenClose1000(
                ask: "what version are we on",
                glanceAsk: glance,
                snapshot: snapshot
            )
            XCTAssertEqual(walk.spokenIntent, "version", glance)
            XCTAssertTrue(walk.listenArmedDuringTTS, glance)
            XCTAssertTrue(walk.listenArmedAfterSpeak, glance)
            XCTAssertEqual(walk.close1000Decision, .reconnect, glance)
            XCTAssertEqual(walk.glanceIntent, "inbox-overview", glance)
            XCTAssertFalse(walk.glanceWaitsOnGmailList, glance)
            XCTAssertFalse(walk.glanceWaitsOnModel, glance)
        }
    }

    func testCalendarOverviewAfterSpeakIsHeardWithoutNewTap() {
        let desk = VoiceRegressionDesk.massimoCalendar
        for ask in [
            "What's on my calendar for the week?",
            "Okay got it. What's on my calendar for the week?",
            "what's on my calendar"
        ] {
            let replay = VoiceTurnReplay.play(utterance: ask, context: desk)
            XCTAssertEqual(replay.intent, "calendar", ask)
            XCTAssertTrue(InboxGlance.isShortOnScreenLeadIn(replay.onScreen), ask)
            XCTAssertFalse(replay.onScreen.contains("Massimo"), ask)
            if !replay.reply.isEmpty {
                XCTAssertNotEqual(replay.onScreen, replay.reply, ask)
            }
            XCTAssertNotEqual(replay.reply, "Here they are.", ask)

            let during = DeskSpeakListenResume.whileClientTTSSpeaking(
                ask: ask,
                spokenLine: replay.reply,
                nextAsk: "Tell me about my emails.",
                context: desk
            )
            XCTAssertFalse(during.ttsFinished, ask)
            XCTAssertTrue(during.listenArmed, "mic stays live through client TTS: \(ask)")
            XCTAssertTrue(during.captureArmed, ask)
            XCTAssertEqual(during.voiceState, .listening, ask)
            XCTAssertTrue(during.nextAccepted, ask)
            XCTAssertTrue(during.cancelledSpeak, "accepted follow-up must stop leftover TTS: \(ask)")

            let walk = DeskSpeakListenResume.afterCompletedDeskSpeak(
                ask: ask,
                spokenLine: replay.reply,
                nextAsk: "Tell me about my emails.",
                context: desk
            )
            XCTAssertTrue(walk.ttsFinished, ask)
            XCTAssertTrue(walk.listenArmed, ask)
            XCTAssertTrue(walk.captureArmed, ask)
            XCTAssertEqual(walk.decision, .keepListening, ask)
            XCTAssertTrue(walk.nextAccepted, ask)
            XCTAssertNotEqual(walk.nextIntent, "dropped", ask)
        }
    }

    func testNamedSenderFamilyStaysDeskOwned() {
        let desk = VoiceRegressionDesk.massimoCalendar
        for ask in [
            "It's the email from Katherine.",
            "the email from Katherine",
            "email from Lauren",
            "summarize Murray's last email"
        ] {
            let replay = VoiceTurnReplay.play(utterance: ask, context: desk)
            XCTAssertNotEqual(replay.intent, "general", ask)
            XCTAssertTrue(
                ["desk-person", "desk-thread", "need-more"].contains(replay.intent)
                    || GmailSearchQuery.hasSenderPattern(ask),
                "\(ask) → \(replay.intent)"
            )
        }
        XCTAssertTrue(
            ["desk-person", "desk-thread"].contains(
                VoiceTurnReplay.play(
                    utterance: "summarize Murray's last email",
                    context: VoiceRegressionDesk.leftoverSpeak
                ).intent
            )
        )
    }

    func testGrokVoiceServiceSpeaksDeskLinesOnDeviceNotViaGrokVerbatim() {
        XCTAssertEqual(
            LiveEveSpeak.plan(text: "1.2.3", socketConnected: false).mouth,
            .clientTTS
        )
        XCTAssertEqual(
            LiveEveSpeak.plan(text: "1.2.3", socketConnected: true).mouth,
            .eve
        )
        XCTAssertTrue(
            GrokRealtime.shouldSpeakViaRealtime(
                usesLiveLoop: true,
                isConnected: true,
                userWantsVoiceOff: false
            )
        )
        XCTAssertFalse(
            GrokRealtime.shouldSpeakViaRealtime(
                usesLiveLoop: true,
                isConnected: false,
                userWantsVoiceOff: false
            )
        )
    }
}
