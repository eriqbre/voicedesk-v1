import XCTest
@testable import VoiceDeskLogic

final class VersionAskTests: XCTestCase {
    func testSynonymFamilyMapsToVersionIntent() {
        let asks = [
            "what version are we on",
            "What version are we on?",
            "what version is this",
            "what build is this",
            "what build am I on",
            "what's on the phone",
            "whats on the phone",
            "what SHA is this",
            "which build is this",
            "Which SHA is this?",
            "what version is the app",
        ]
        for ask in asks {
            XCTAssertTrue(ConversationPresence.wantsVersionAsk(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsCalendarAsk(ask), ask)
            XCTAssertFalse(ConversationPresence.looksLikeMailAsk(ask), ask)
            XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(ask), ask)
            XCTAssertFalse(ConversationPresence.isClarifyPick(ask), ask)

            let plan = ConversationPresence.plan(for: ask)
            XCTAssertEqual(plan.topic, .version, ask)
            XCTAssertFalse(plan.attachesCards, ask)

            let evidence = ConversationPresence.deskEvidence(
                for: ask,
                context: VoiceRegressionDesk.connected
            )
            XCTAssertEqual(evidence?.topic, .version, ask)
            XCTAssertTrue(evidence?.cards.isEmpty == true, ask)
            XCTAssertFalse(evidence?.shouldSearchGmail == true, ask)
            XCTAssertEqual(evidence?.resetsFocusedEmail, true, ask)

            let classified = VoiceInteractionLog.classify(utterance: ask, evidence: evidence)
            XCTAssertEqual(classified.intent, "version", ask)
            XCTAssertNotEqual(classified.intent, "calendar", ask)
        }
    }

    func testCalendarPhrasesDoNotMatchVersion() {
        let asks = [
            "what's on my calendar",
            "whats on my calendar",
            "What's the latest on my calendar?",
            "what's on my calendar this week",
            "latest on my calendar",
            "what meetings do I have today",
        ]
        for ask in asks {
            XCTAssertFalse(ConversationPresence.wantsVersionAsk(ask), ask)
            XCTAssertTrue(ConversationPresence.wantsCalendarAsk(ask), ask)
            XCTAssertNotEqual(ConversationPresence.plan(for: ask).topic, .version, ask)
            XCTAssertEqual(
                VoiceInteractionLog.classify(
                    utterance: ask,
                    evidence: ConversationPresence.deskEvidence(
                        for: ask,
                        context: VoiceRegressionDesk.connected
                    )
                ).intent,
                "calendar",
                ask
            )
        }
    }

    func testWhatsOnThePhoneIsVersionWhatsOnMyCalendarIsCalendar() {
        XCTAssertTrue(ConversationPresence.wantsVersionAsk("what's on the phone"))
        XCTAssertFalse(ConversationPresence.wantsCalendarAsk("what's on the phone"))
        XCTAssertEqual(ConversationPresence.plan(for: "what's on the phone").topic, .version)
        XCTAssertEqual(
            VoiceInteractionLog.classify(
                utterance: "what's on the phone",
                evidence: ConversationPresence.deskEvidence(
                    for: "what's on the phone",
                    context: .disconnected
                )
            ).intent,
            "version"
        )

        XCTAssertTrue(ConversationPresence.wantsCalendarAsk("what's on my calendar"))
        XCTAssertFalse(ConversationPresence.wantsVersionAsk("what's on my calendar"))
        XCTAssertEqual(ConversationPresence.plan(for: "what's on my calendar").topic, .calendar)
        XCTAssertEqual(
            VoiceInteractionLog.classify(
                utterance: "what's on my calendar",
                evidence: ConversationPresence.deskEvidence(
                    for: "what's on my calendar",
                    context: VoiceRegressionDesk.connected
                )
            ).intent,
            "calendar"
        )
    }

    func testSpokenLineUsesFixtureSHAAndNeverInvents() {
        XCTAssertEqual(BuildIdentity.fixture.shortSHA, "1fa0a0e")
        XCTAssertEqual(BuildIdentity.fixture.spokenLine, "VoiceDesk 1fa0a0e.")
        XCTAssertTrue(BuildIdentity.fixture.spokenLine.contains("1fa0a0e"))
        XCTAssertEqual(BuildIdentity.unknown.spokenLine, "VoiceDesk, unknown SHA.")
        XCTAssertEqual(BuildIdentity(shortSHA: "").spokenLine, "VoiceDesk, unknown SHA.")
        XCTAssertEqual(BuildIdentity(shortSHA: "unknown").spokenLine, "VoiceDesk, unknown SHA.")
        XCTAssertEqual(BuildIdentity(shortSHA: "1fa0a0e-dirty").spokenLine, "VoiceDesk, unknown SHA.")
        XCTAssertEqual(BuildIdentity(shortSHA: "not a sha").spokenLine, "VoiceDesk, unknown SHA.")
        XCTAssertEqual(
            BuildIdentity(infoDictionary: ["GIT_SHA": "1fa0a0e", "GIT_BRANCH": "cursor/cards-only-email-first-tap-9c2c"]).spokenLine,
            "VoiceDesk 1fa0a0e."
        )
        XCTAssertEqual(
            BuildIdentity(infoDictionary: [:]).spokenLine,
            "VoiceDesk, unknown SHA."
        )
    }

    func testVersionAskClearsStickyAndDoesNotSearchGmail() {
        let replay = VoiceTurnReplay.play(
            utterance: "what's on the phone",
            context: VoiceRegressionDesk.connected,
            focusedEmail: VoiceRegressionDesk.murray
        )
        XCTAssertEqual(replay.intent, "version")
        XCTAssertTrue(replay.ownsDeskTurn)
        XCTAssertFalse(replay.looksLikeMailAsk)
        XCTAssertFalse(replay.shouldSearchGmail)
        XCTAssertTrue(replay.stickyCleared)
        XCTAssertTrue(replay.cardLabels.isEmpty)
        XCTAssertTrue(BuildIdentity.fixture.spokenLine.contains("1fa0a0e"))
    }
}
