import XCTest
@testable import VoiceDeskLogic

final class VersionAskTests: XCTestCase {
    func testDefaultFamilyMapsToVersionIntentAndMarketingSpokenLine() {
        let asks = [
            "what version are we on",
            "What version are we on?",
            "what version is this",
            "what build is this",
            "what build am I on",
            "what's on the phone",
            "whats on the phone",
            "which build is this",
            "what version is the app",
        ]
        for ask in asks {
            XCTAssertTrue(ConversationPresence.wantsVersionAsk(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsSHAAsk(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsCalendarAsk(ask), ask)
            XCTAssertFalse(ConversationPresence.looksLikeMailAsk(ask), ask)
            XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(ask), ask)
            XCTAssertFalse(ConversationPresence.isClarifyPick(ask), ask)

            let plan = ConversationPresence.plan(for: ask)
            XCTAssertEqual(plan.topic, .version, ask)
            XCTAssertFalse(plan.attachesCards, ask)
            XCTAssertEqual(
                ConversationPresence.spokenIdentityLine(for: ask, identity: .fixture),
                "VoiceDesk 0.1, build 1.",
                ask
            )

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

    func testSHAFamilyMapsToVersionTopicAndSHASpokenLine() {
        let asks = [
            "what SHA is this",
            "Which SHA is this?",
            "what's the SHA",
            "whats the sha",
            "what git hash is this",
            "which git hash",
        ]
        for ask in asks {
            XCTAssertTrue(ConversationPresence.wantsVersionAsk(ask), ask)
            XCTAssertTrue(ConversationPresence.wantsSHAAsk(ask), ask)
            XCTAssertFalse(ConversationPresence.wantsCalendarAsk(ask), ask)
            XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn(ask), ask)
            XCTAssertEqual(ConversationPresence.plan(for: ask).topic, .version, ask)
            XCTAssertEqual(
                ConversationPresence.spokenIdentityLine(for: ask, identity: .fixture),
                "VoiceDesk 1fa0a0e.",
                ask
            )
            XCTAssertEqual(
                VoiceInteractionLog.classify(
                    utterance: ask,
                    evidence: ConversationPresence.deskEvidence(
                        for: ask,
                        context: VoiceRegressionDesk.connected
                    )
                ).intent,
                "version",
                ask
            )
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
            XCTAssertFalse(ConversationPresence.wantsSHAAsk(ask), ask)
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
        XCTAssertFalse(ConversationPresence.wantsSHAAsk("what's on the phone"))
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

    func testSpokenLineUsesFixtureMarketingAndNeverInvents() {
        XCTAssertEqual(BuildIdentity.fixture.marketing, "0.1.0")
        XCTAssertEqual(BuildIdentity.fixture.build, "1")
        XCTAssertEqual(BuildIdentity.fixture.shortSHA, "1fa0a0e")
        XCTAssertEqual(BuildIdentity.fixture.spokenLine, "VoiceDesk 0.1, build 1.")
        XCTAssertEqual(BuildIdentity.fixture.spokenSHALine, "VoiceDesk 1fa0a0e.")
        XCTAssertEqual(BuildIdentity.fixture.dogfoodLine, "0.1.0 build 1 sha 1fa0a0e")
        XCTAssertFalse(BuildIdentity.fixture.spokenLine.contains("0.1.0.1"))
        XCTAssertEqual(BuildIdentity.unknown.spokenLine, "VoiceDesk, unknown version.")
        XCTAssertEqual(BuildIdentity.unknown.spokenSHALine, "VoiceDesk, unknown SHA.")
        XCTAssertEqual(BuildIdentity(shortSHA: "").spokenSHALine, "VoiceDesk, unknown SHA.")
        XCTAssertEqual(BuildIdentity(shortSHA: "unknown").spokenSHALine, "VoiceDesk, unknown SHA.")
        XCTAssertEqual(BuildIdentity(shortSHA: "1fa0a0e-dirty").spokenSHALine, "VoiceDesk, unknown SHA.")
        XCTAssertEqual(BuildIdentity(shortSHA: "not a sha").spokenSHALine, "VoiceDesk, unknown SHA.")
        XCTAssertEqual(
            BuildIdentity(marketing: "0.1.1.32", build: "32").spokenLine,
            "VoiceDesk, unknown version."
        )
        XCTAssertEqual(
            BuildIdentity(infoDictionary: [
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "GIT_SHA": "1fa0a0e",
                "GIT_BRANCH": "cursor/cards-only-email-first-tap-9c2c"
            ]).spokenLine,
            "VoiceDesk 0.1, build 1."
        )
        XCTAssertEqual(
            BuildIdentity(infoDictionary: [
                "GIT_SHA": "1fa0a0e",
                "GIT_BRANCH": "cursor/cards-only-email-first-tap-9c2c"
            ]).spokenSHALine,
            "VoiceDesk 1fa0a0e."
        )
        XCTAssertEqual(
            BuildIdentity(infoDictionary: [:]).spokenLine,
            "VoiceDesk, unknown version."
        )
        XCTAssertEqual(
            BuildIdentity(infoDictionary: [:]).spokenSHALine,
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
        XCTAssertEqual(BuildIdentity.fixture.spokenLine, "VoiceDesk 0.1, build 1.")
        XCTAssertEqual(
            ConversationPresence.spokenIdentityLine(for: "what SHA is this", identity: .fixture),
            "VoiceDesk 1fa0a0e."
        )
    }
}
