import XCTest
@testable import VoiceDeskLogic

/// Live walks 2026-08-25, SHA fa6616e:
/// 1. ~12:05 ET — inbox / need-more / task miss / calendar → deaf after 16:07:51Z
/// 2. ~12:17 ET — inbox / Lauren-Fleeman / calendar → deaf after 16:18:08Z
/// Both end on a completed calendar speak. Deaf is listen-resume, not parse.
///
/// After any local desk speak, listen/capture must be armed again.
/// Synonym families, not one golden phrase. Intent / state only.
///
/// Out of scope (logged, not fixed): “The email from Eriq via Todoist is
/// listed twice…” classified as task with garbage `from:eriqviatodoist`.
final class DeskSpeakListenResumeTests: XCTestCase {
    static let inboxOverviewFamily = [
        "Tell me about my emails.",
        "tell me my emails",
        "show me my emails",
        "what's in my inbox"
    ]

    static let calendarFamily = [
        "What's on my calendar this week?",
        "What's on my calendar for the week?",
        "whats on my calendar",
        "what's on my calendar",
        "my calendar this week",
        "Okay got it. What's on my calendar for the week?"
    ]

    static let namedSenderFamily = [
        "It's the email from Katherine.",
        "it's the email from Katherine",
        "the email from Katherine",
        "email from Katherine"
    ]

    /// Walk 2 ~12:17 ET. Same deaf after calendar. No need-more / task miss.
    static let walk2InboxFamily = [
        "Tell me my emails for the day.",
        "tell me my emails for the day",
        "Tell me about my emails.",
        "tell me my emails"
    ]

    static let walk2LaurenFamily = [
        "Find that, find that email from Lauren about Fleeman Road.",
        "find that email from Lauren about Fleeman Road",
        "Give me a summary of the email from Lauren about Fleeman Road."
    ]

    static let needMoreFamily = [
        "Who’s it from?",
        "who's it from",
        "what's the subject"
    ]

    static let taskFamily = [
        "what's on my tasks",
        "what tasks do I have",
        "my tasks",
        "open tasks"
    ]

    /// Walk leftover: this must stay a follow-up ask after a desk speak,
    /// not get eaten because listen died.
    static let nextAskFamily = [
        "What's on my calendar this week?",
        "Tell me about my emails.",
        "what's on my tasks"
    ]

    private var connected: DeskContext {
        VoiceRegressionDesk.connected
    }

    func testListenStaysUnarmedUntilClientTTSReportsDone() {
        let during = DeskSpeakListenResume.whileClientTTSSpeaking(
            ask: "What's on my calendar for the week?",
            spokenLine: "Massimo’s on Thursday.",
            nextAsk: "Tell me about my emails.",
            context: connected
        )
        XCTAssertFalse(during.ttsFinished)
        XCTAssertFalse(during.listenArmed)
        XCTAssertFalse(during.captureArmed)
        XCTAssertEqual(during.voiceState, .speaking)
        XCTAssertFalse(ListenResumePolicy.shouldArmListenAfterClientTTS(ttsFinished: during.ttsFinished))

        let after = DeskSpeakListenResume.afterCompletedDeskSpeak(
            ask: "What's on my calendar for the week?",
            spokenLine: "Massimo’s on Thursday.",
            nextAsk: "Tell me about my emails.",
            context: connected
        )
        XCTAssertTrue(after.ttsFinished)
        XCTAssertTrue(after.listenArmed)
        XCTAssertTrue(after.captureArmed)
        XCTAssertEqual(after.decision, .resumeCapture)
        XCTAssertTrue(after.nextAccepted)
    }

    func testInboxOverviewSpeakLeavesListenArmedForNextAsk() {
        for ask in Self.inboxOverviewFamily {
            let walk = DeskSpeakListenResume.afterCompletedDeskSpeak(
                ask: ask,
                spokenLine: "Five emails in the last sync.",
                nextAsk: "What's on my calendar this week?",
                context: connected
            )
            XCTAssertEqual(walk.spokenIntent, "inbox-overview", ask)
            XCTAssertTrue(walk.listenArmed, ask)
            XCTAssertTrue(walk.captureArmed, ask)
            XCTAssertEqual(walk.decision, .resumeCapture, ask)
            XCTAssertEqual(walk.voiceState, .listening, ask)
            XCTAssertTrue(walk.nextAccepted, ask)
            XCTAssertEqual(walk.nextIntent, "calendar", ask)
        }
    }

    func testNamedSenderThenCalendarLeavesListenArmedOnClientTTS() {
        let desk = VoiceRegressionDesk.massimoCalendar
        for sender in Self.namedSenderFamily {
            XCTAssertNotEqual(
                VoiceTurnReplay.play(utterance: sender, context: desk).intent,
                "general",
                "\(sender) must stay desk-owned"
            )
            XCTAssertTrue(GmailSearchQuery.hasSenderPattern(sender), sender)
        }
        XCTAssertTrue(ListenResumePolicy.deskSpeakUsesClientTTS())
        for calendar in Self.calendarFamily {
            let walk = DeskSpeakListenResume.afterNamedSenderThenCalendar(
                senderAsk: "It's the email from Katherine.",
                calendarAsk: calendar,
                context: desk
            )
            XCTAssertEqual(walk.spokenIntent, "calendar", calendar)
            XCTAssertTrue(walk.listenArmed, "calendar after named-sender must arm listen: \(calendar)")
            XCTAssertTrue(walk.captureArmed, calendar)
            XCTAssertEqual(walk.decision, .resumeCapture, calendar)
            XCTAssertTrue(walk.nextAccepted, calendar)
        }
    }

    func testCalendarAfterNamedSenderClose1000Reconnects() {
        let desk = VoiceRegressionDesk.massimoCalendar
        let walk = DeskSpeakListenResume.afterNamedSenderThenCalendar(
            senderAsk: "It's the email from Katherine.",
            calendarAsk: "Okay got it. What's on my calendar for the week?",
            context: desk,
            liveSessionArmed: true,
            reportClose: true
        )
        XCTAssertEqual(walk.spokenIntent, "calendar")
        XCTAssertTrue(walk.listenArmed)
        XCTAssertEqual(walk.decision, .reconnect)
        XCTAssertNotEqual(walk.decision, .stayIdle)

        let stopped = DeskSpeakListenResume.afterNamedSenderThenCalendar(
            senderAsk: "It's the email from Katherine.",
            calendarAsk: "Okay got it. What's on my calendar for the week?",
            context: desk,
            userWantsVoiceOff: true,
            liveSessionArmed: true,
            reportClose: true
        )
        XCTAssertEqual(stopped.decision, .stayIdle)
        XCTAssertFalse(stopped.listenArmed)
    }

    func testCalendarSpeakLeavesListenArmedForInboxFollowUp() {
        for ask in Self.calendarFamily {
            let walk = DeskSpeakListenResume.afterCompletedDeskSpeak(
                ask: ask,
                spokenLine: "Massimo’s on Thursday.",
                nextAsk: "Tell me about my emails.",
                context: connected
            )
            XCTAssertEqual(walk.spokenIntent, "calendar", ask)
            XCTAssertTrue(walk.listenArmed, ask)
            XCTAssertTrue(walk.captureArmed, ask)
            XCTAssertEqual(walk.decision, .resumeCapture, ask)
            XCTAssertTrue(walk.nextAccepted, ask)
            XCTAssertEqual(walk.nextIntent, "inbox-overview", ask)
        }
    }

    func testNeedMoreSpeakLeavesListenArmed() {
        for spoken in [
            ConversationPresence.emailNeedMoreReply,
            "Who’s it from, or what’s the subject?"
        ] {
            let walk = DeskSpeakListenResume.afterCompletedDeskSpeak(
                ask: "show me that one",
                spokenLine: spoken,
                nextAsk: "what's on my tasks",
                context: connected
            )
            XCTAssertTrue(walk.listenArmed, spoken)
            XCTAssertTrue(walk.captureArmed, spoken)
            XCTAssertEqual(walk.decision, .resumeCapture, spoken)
            XCTAssertEqual(walk.voiceState, .listening, spoken)
            XCTAssertTrue(walk.nextAccepted, spoken)
            XCTAssertEqual(walk.nextIntent, "task", spoken)
        }
    }

    func testTaskMissSpeakLeavesListenArmed() {
        for ask in Self.taskFamily {
            let walk = DeskSpeakListenResume.afterCompletedDeskSpeak(
                ask: ask,
                spokenLine: ConversationPresence.taskMissReply,
                nextAsk: "What's on my calendar this week?",
                context: connected
            )
            XCTAssertEqual(walk.spokenIntent, "task", ask)
            XCTAssertTrue(walk.listenArmed, ask)
            XCTAssertTrue(walk.captureArmed, ask)
            XCTAssertEqual(walk.decision, .resumeCapture, ask)
            XCTAssertTrue(walk.nextAccepted, ask)
            XCTAssertEqual(walk.nextIntent, "calendar", ask)
        }
    }

    func testClosedSocketAfterDeskSpeakReconnectsWithoutNewTap() {
        let walk = DeskSpeakListenResume.afterCompletedDeskSpeak(
            ask: "What's on my calendar this week?",
            spokenLine: "Massimo’s on Thursday.",
            nextAsk: "Tell me about my emails.",
            context: connected,
            socketConnected: false,
            captureRunningAfterSpeak: false
        )
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.captureArmed)
        XCTAssertEqual(walk.decision, .reconnect)
        XCTAssertTrue(walk.nextAccepted)
    }

    func testCaptureAlreadyRunningStillResumesAfterDeskTTS() {
        let walk = DeskSpeakListenResume.afterCompletedDeskSpeak(
            ask: "Tell me about my emails.",
            spokenLine: "Five emails in the last sync.",
            nextAsk: "What's on my calendar this week?",
            context: connected,
            captureRunningAfterSpeak: true
        )
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.captureArmed)
        XCTAssertEqual(walk.decision, .resumeCapture)
        XCTAssertTrue(walk.nextAccepted)
    }

    /// Walk 2 tape: inbox-overview → long Lauren speak → calendar (Massimo’s) → silence.
    /// Engine still “running” after calendar TTS is the live fail.
    func testWalk2InboxLaurenCalendarSpeakLeavesListenArmed() {
        let desk = VoiceRegressionDesk.laurenSeveral
        for inbox in Self.walk2InboxFamily {
            XCTAssertEqual(
                VoiceTurnReplay.play(utterance: inbox, context: desk).intent,
                "inbox-overview",
                inbox
            )
        }
        for lauren in Self.walk2LaurenFamily {
            let replay = VoiceTurnReplay.play(utterance: lauren, context: desk)
            XCTAssertTrue(["desk-person", "desk-thread"].contains(replay.intent), "\(lauren) → \(replay.intent)")
            XCTAssertNotEqual(replay.intent, "general", lauren)
        }

        let walk = DeskSpeakListenResume.afterSequentialDeskSpeaks(
            turns: [
                ("Tell me my emails for the day.", "Five emails in the last sync."),
                (
                    "Find that, find that email from Lauren about Fleeman Road.",
                    "Laren Jansen wrote about Fleeman Road disclosures."
                ),
                ("What's on my calendar for the week?", "Massimo’s on Thursday.")
            ],
            nextAsk: "Tell me about my emails.",
            context: desk,
            captureRunningAfterSpeak: true
        )
        XCTAssertEqual(walk.spokenIntent, "calendar")
        XCTAssertTrue(walk.listenArmed, "calendar TTS must leave listen armed")
        XCTAssertTrue(walk.captureArmed, "must resume capture even if engine reports running")
        XCTAssertEqual(walk.decision, .resumeCapture)
        XCTAssertEqual(walk.voiceState, .listening)
        XCTAssertTrue(walk.nextAccepted)
        XCTAssertEqual(walk.nextIntent, "inbox-overview")
    }

    /// 4ac127a Qs 15 Pro Max: walk-2 through calendar, then close 1000 / idle.
    /// Reconnect + capture armed. No new first-tap.
    func testWalk2CalendarThenIdleCode1000ReconnectsAndArmsCapture() {
        let desk = VoiceRegressionDesk.laurenSeveral
        let walk = DeskSpeakListenResume.afterWalk2CalendarThenIdleNormalClose(
            nextAsk: "Tell me about my emails.",
            context: desk
        )
        XCTAssertEqual(walk.spokenIntent, "calendar")
        XCTAssertEqual(walk.decision, .reconnect)
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.captureArmed)
        XCTAssertEqual(walk.voiceState, .listening)
        XCTAssertTrue(walk.nextAccepted)
        XCTAssertEqual(walk.nextIntent, "inbox-overview")

        let stopped = DeskSpeakListenResume.afterWalk2CalendarThenIdleNormalClose(
            nextAsk: "Tell me about my emails.",
            context: desk,
            userWantsVoiceOff: true
        )
        XCTAssertEqual(stopped.decision, .stayIdle)
        XCTAssertFalse(stopped.listenArmed)
        XCTAssertFalse(stopped.captureArmed)
    }

    func testUserStopAfterDeskSpeakDoesNotArm() {
        let decision = ListenResumePolicy.afterDeskSpeak(
            userWantsVoiceOff: true,
            socketConnected: true,
            captureRunning: false
        )
        XCTAssertEqual(decision, .stayIdle)
        XCTAssertFalse(ListenResumePolicy.isArmed(decision))
    }

    func testNextAskFamilyIsAcceptedAfterCalendarSpeak() {
        for next in Self.nextAskFamily {
            let walk = DeskSpeakListenResume.afterCompletedDeskSpeak(
                ask: "What's on my calendar this week?",
                spokenLine: "Massimo’s on Thursday.",
                nextAsk: next,
                context: connected
            )
            XCTAssertTrue(walk.listenArmed, next)
            XCTAssertTrue(walk.nextAccepted, next)
            XCTAssertNotEqual(walk.nextIntent, "dropped", next)
            XCTAssertNotEqual(walk.nextIntent, "general", "\(next) must stay desk-owned after listen resume")
        }
    }

    /// Recorded walk #3 routing — do not change here. After that speak,
    /// listen must still arm.
    func testTodoistTwiceParseStaysOutOfScopeButListenStillArms() {
        let recorded = "The email from Eriq via Todoist is listed twice in my email list."
        let replay = VoiceTurnReplay.play(utterance: recorded, context: connected)
        // Live walk: intent task, garbage q=from:eriqviatodoist. Log only.
        _ = replay.intent
        _ = replay.gmailQuery

        let walk = DeskSpeakListenResume.afterCompletedDeskSpeak(
            ask: recorded,
            spokenLine: ConversationPresence.taskMissReply,
            nextAsk: "What's on my calendar this week?",
            context: connected
        )
        XCTAssertTrue(walk.listenArmed)
        XCTAssertTrue(walk.captureArmed)
        XCTAssertEqual(walk.decision, .resumeCapture)
        XCTAssertTrue(walk.nextAccepted)
        XCTAssertEqual(walk.nextIntent, "calendar")
    }
}
