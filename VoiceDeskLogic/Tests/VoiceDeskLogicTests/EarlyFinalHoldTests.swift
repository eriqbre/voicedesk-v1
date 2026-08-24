import XCTest
@testable import VoiceDeskLogic

final class EarlyFinalHoldTests: XCTestCase {
    func testWhatsPeriodIsHeldNotGeneralOrGrok() {
        var hold = EarlyFinalHold()
        let decision = hold.decide("What's.")
        XCTAssertEqual(decision.intent, "held")
        XCTAssertTrue(decision.isHeld)
        XCTAssertNil(decision.acceptedText)
        XCTAssertNil(decision.plan)
        XCTAssertNotEqual(decision.intent, "general")
        XCTAssertTrue(hold.heldPrefix != nil)
    }

    func testPrefixFamilyHoldsIncludingPeriodAndBareForms() {
        let prefixes = [
            "what's",
            "whats",
            "What's.",
            "Whats.",
            "What’s.",
            "what",
            "What?",
            "when",
            "When.",
            "when's",
            "how's",
            "How's.",
            "hows",
            "how about",
            "How about.",
            "how's about",
        ]
        for prefix in prefixes {
            var hold = EarlyFinalHold()
            let decision = hold.decide(prefix)
            XCTAssertEqual(decision.intent, "held", prefix)
            XCTAssertTrue(decision.isHeld, prefix)
            XCTAssertNil(decision.plan, prefix)
            XCTAssertNotEqual(decision.intent, "general", prefix)
            XCTAssertTrue(EarlyFinalHold.isIncompletePrefix(prefix), prefix)
        }
    }

    func testCompleteAsksAreNotHeld() {
        let asks: [(String, String)] = [
            ("what's on my calendar", "calendar"),
            ("what version are we on", "version"),
            ("what SHA is this", "version"),
            ("what's new", "general"),
        ]
        for (ask, intent) in asks {
            var hold = EarlyFinalHold()
            let decision = hold.decide(ask, context: VoiceRegressionDesk.connected)
            XCTAssertNotEqual(decision.intent, "held", ask)
            XCTAssertEqual(decision.acceptedText, ask, ask)
            XCTAssertEqual(decision.intent, intent, ask)
            XCTAssertFalse(EarlyFinalHold.isIncompletePrefix(ask), ask)
        }
    }

    func testHeldThenWhatSHASpeaksBakedSHA() {
        var hold = EarlyFinalHold()
        XCTAssertEqual(hold.decide("What's.").intent, "held")

        let sha = hold.decide("what SHA", context: VoiceRegressionDesk.connected)
        XCTAssertEqual(sha.intent, "version")
        XCTAssertEqual(sha.plan?.topic, .version)
        XCTAssertEqual(sha.acceptedText, "what SHA")
        XCTAssertTrue(ConversationPresence.wantsSHAAsk(sha.acceptedText ?? ""))
        XCTAssertEqual(
            ConversationPresence.spokenIdentityLine(for: sha.acceptedText ?? "", identity: .fixture),
            "VoiceDesk 1fa0a0e."
        )
        XCTAssertFalse(ConversationPresence.wantsCalendarAsk(sha.acceptedText ?? ""))
    }

    func testHeldThenSHAFragmentSpeaksBakedSHA() {
        var hold = EarlyFinalHold()
        XCTAssertEqual(hold.decide("What's.").intent, "held")

        let sha = hold.decide("SHA", context: VoiceRegressionDesk.connected)
        XCTAssertEqual(sha.intent, "version")
        XCTAssertEqual(sha.acceptedText, "What's SHA")
        XCTAssertTrue(ConversationPresence.wantsSHAAsk(sha.acceptedText ?? ""))
        XCTAssertEqual(
            ConversationPresence.spokenIdentityLine(for: sha.acceptedText ?? "", identity: .fixture),
            "VoiceDesk 1fa0a0e."
        )
        XCTAssertEqual(sha.plan?.topic, .version)
    }

    func testHeldThenCompletedPhrasesKeepDeskTopic() {
        var hold = EarlyFinalHold()
        XCTAssertEqual(hold.decide("What's.").intent, "held")
        let phone = hold.decide("what's on the phone", context: VoiceRegressionDesk.connected)
        XCTAssertEqual(phone.intent, "version")
        XCTAssertFalse(ConversationPresence.wantsSHAAsk(phone.acceptedText ?? ""))
        XCTAssertEqual(
            ConversationPresence.spokenIdentityLine(for: phone.acceptedText ?? "", identity: .fixture),
            "VoiceDesk point 1, build 1."
        )

        XCTAssertEqual(hold.decide("What's.").intent, "held")
        let calendar = hold.decide("what's on my calendar", context: VoiceRegressionDesk.connected)
        XCTAssertEqual(calendar.intent, "calendar")
        XCTAssertEqual(calendar.plan?.topic, .calendar)
        XCTAssertNotEqual(calendar.intent, "version")

        XCTAssertEqual(hold.decide("whats").intent, "held")
        let calendarTail = hold.decide("on my calendar", context: VoiceRegressionDesk.connected)
        XCTAssertEqual(calendarTail.intent, "calendar")
        XCTAssertEqual(calendarTail.acceptedText, "whats on my calendar")

        XCTAssertEqual(hold.decide("What's.").intent, "held")
        let lauren = hold.decide(
            "what's the latest email from Lauren",
            context: VoiceRegressionDesk.greenacreFirst
        )
        XCTAssertTrue(["desk-person", "desk-thread"].contains(lauren.intent), lauren.intent)
        XCTAssertNotEqual(lauren.intent, "general")
        XCTAssertNotEqual(lauren.intent, "held")
        XCTAssertNotEqual(lauren.plan?.topic, .version)
        XCTAssertNotEqual(lauren.plan?.topic, .calendar)
    }

    func testNothingMoreArrivesDoesNotClassifyWhatsAsGeneral() {
        var hold = EarlyFinalHold()
        let first = hold.decide("What's.")
        XCTAssertEqual(first.intent, "held")
        XCTAssertNotEqual(first.intent, "general")
        XCTAssertNil(first.plan)
        // Silent hold — no invented mail, no Grok “starting a thought.”
        XCTAssertTrue(hold.heldPrefix != nil)
        hold.reset()
        XCTAssertNil(hold.heldPrefix)
    }

    func testHowsTheWeatherAndWhatsNewStayLive() {
        var hold = EarlyFinalHold()
        let weather = hold.decide("How's the weather?")
        XCTAssertEqual(weather.intent, "general")
        XCTAssertEqual(weather.acceptedText, "How's the weather?")

        let news = hold.decide("what's new")
        XCTAssertEqual(news.intent, "general")
        XCTAssertEqual(news.acceptedText, "what's new")
    }
}
