import XCTest
@testable import VoiceDeskLogic

final class VoiceLiveLoopTests: XCTestCase {
    func testListenGeneralSpeakThenListening() {
        var loop = VoiceLiveLoop()
        loop.apply(.tapTalk)
        XCTAssertEqual(loop.session.state, .listening)
        XCTAssertFalse(loop.captureMuted)
        XCTAssertTrue(loop.invariantFailures().isEmpty, "\(loop.invariantFailures())")

        loop.apply(.speechStarted)
        loop.apply(.speechStopped)
        XCTAssertEqual(loop.session.state, .thinking)

        loop.apply(.responseCreated(id: "wx-1"))
        XCTAssertEqual(loop.session.state, .speaking)
        XCTAssertTrue(loop.captureMuted)
        loop.apply(.audioDelta)
        loop.apply(.responseDone(id: "wx-1"))
        XCTAssertEqual(loop.session.state, .listening)
        XCTAssertFalse(loop.captureMuted)
        XCTAssertFalse(loop.dropAudio)
        XCTAssertTrue(loop.invariantFailures().isEmpty, "\(loop.invariantFailures())")
    }

    func testDeskThenGeneralUnmutesAndSpeaks() {
        var loop = VoiceLiveLoop()
        loop.apply(.tapTalk)
        loop.apply(.speechStopped)
        loop.apply(.claimDesk)
        XCTAssertTrue(loop.dropAudio)

        loop.apply(.beginVerbatim)
        loop.apply(.responseCreated(id: "verbatim-1"))
        XCTAssertEqual(loop.session.state, .speaking)
        XCTAssertFalse(loop.dropAudio, "verbatim created unmutes Eve")
        loop.apply(.audioDelta)
        loop.apply(.responseDone(id: "verbatim-1"))
        XCTAssertFalse(loop.dropAudio, "desk mute must not restore after digest")
        XCTAssertFalse(loop.verbatim.isSpeaking)
        XCTAssertEqual(loop.session.state, .listening)

        loop.apply(.unmuteGeneral)
        loop.apply(.speechStarted)
        loop.apply(.speechStopped)
        loop.apply(.responseCreated(id: "wx-2"))
        XCTAssertEqual(loop.session.state, .speaking)
        XCTAssertFalse(loop.dropAudio)
        XCTAssertTrue(loop.invariantFailures().isEmpty, "\(loop.invariantFailures())")
    }

    func testLeftoverDoneDoesNotRemuteOrEndHalfDuplexEarly() {
        var loop = VoiceLiveLoop()
        loop.apply(.tapTalk)
        loop.apply(.claimDesk)
        loop.apply(.beginVerbatim)
        loop.apply(.responseCreated(id: "verbatim-1"))
        XCTAssertEqual(loop.session.state, .speaking)

        loop.apply(.responseDone(id: "handoff-1"))
        XCTAssertTrue(loop.verbatim.isSpeaking)
        XCTAssertEqual(loop.session.state, .speaking)
        XCTAssertTrue(loop.captureMuted)

        loop.apply(.audioDelta)
        loop.apply(.responseDone(id: "verbatim-1"))
        XCTAssertFalse(loop.verbatim.isSpeaking)
        XCTAssertEqual(loop.session.state, .listening)
        XCTAssertFalse(loop.dropAudio)
        XCTAssertFalse(loop.captureMuted)
        XCTAssertTrue(loop.invariantFailures().isEmpty, "\(loop.invariantFailures())")
    }

    func testSuppressedHandoffDoesNotEnterSpeaking() {
        var loop = VoiceLiveLoop()
        loop.apply(.tapTalk)
        loop.apply(.speechStopped)
        loop.apply(.claimDesk)
        loop.apply(.responseCreated(id: "handoff-1"))
        XCTAssertNotEqual(loop.session.state, .speaking)
        XCTAssertTrue(loop.dropAudio)
        loop.apply(.responseDone(id: "handoff-1"))
        XCTAssertEqual(loop.session.state, .listening)
        XCTAssertTrue(loop.invariantFailures().isEmpty, "\(loop.invariantFailures())")
    }

    func testEchoPhantomDroppedWhileSpeakingThenAcceptedAfterCooldown() {
        var loop = VoiceLiveLoop()
        let t0 = Date(timeIntervalSince1970: 20_000)
        loop.apply(.tapTalk, at: t0)
        loop.apply(.responseCreated(id: "eve-1"), at: t0)
        XCTAssertEqual(loop.session.state, .speaking)
        XCTAssertFalse(loop.shouldAcceptUserTranscript)

        loop.apply(.speechStarted, at: t0)
        XCTAssertEqual(loop.session.state, .speaking, "echo must not barge in")

        loop.apply(.audioDelta, at: t0)
        loop.apply(.responseDone(id: "eve-1"), at: t0.addingTimeInterval(1))
        XCTAssertFalse(loop.echo.shouldAcceptUserInput(at: t0.addingTimeInterval(1.1)))
        XCTAssertTrue(loop.echo.shouldAcceptUserInput(at: t0.addingTimeInterval(1.4)))
        XCTAssertTrue(loop.shouldAcceptUserTranscript || loop.echo.shouldAcceptUserInput(at: t0.addingTimeInterval(1.4)))
    }

    func testSilentSpeakingWatchdogReturnsToListening() {
        var loop = VoiceLiveLoop()
        loop.apply(.tapTalk)
        loop.apply(.responseCreated(id: "stuck-1"))
        XCTAssertEqual(loop.session.state, .speaking)
        loop.apply(.watchdogTick(elapsed: 1))
        XCTAssertEqual(loop.session.state, .speaking)
        loop.apply(.watchdogTick(elapsed: 4))
        XCTAssertEqual(loop.session.state, .listening)
        XCTAssertFalse(loop.captureMuted)
        XCTAssertNil(loop.lastError)
        XCTAssertTrue(loop.invariantFailures().isEmpty, "\(loop.invariantFailures())")
    }

    func testErrorNeverUnknownAndRecovers() {
        var loop = VoiceLiveLoop()
        loop.apply(.tapTalk)
        loop.apply(.responseCreated(id: "err-1"))
        loop.apply(.error(code: "", message: "Unknown"))
        XCTAssertEqual(loop.session.state, .listening)
        XCTAssertNotEqual(loop.lastError, "Unknown")
        XCTAssertEqual(loop.lastError, "Grok session error")
        XCTAssertFalse(loop.captureMuted)
        loop.apply(.recovered)
        XCTAssertNil(loop.lastError)
        XCTAssertTrue(loop.invariantFailures().isEmpty, "\(loop.invariantFailures())")
    }

    func testCancelReturnsIdleMutedNotEchoBlocked() {
        var loop = VoiceLiveLoop()
        loop.apply(.tapTalk)
        loop.apply(.responseCreated(id: "eve-1"))
        loop.apply(.cancel)
        XCTAssertEqual(loop.session.state, .idle)
        XCTAssertTrue(loop.userWantsVoiceOff)
        XCTAssertTrue(loop.captureMuted)
        XCTAssertFalse(loop.echo.assistantSpeaking)
        XCTAssertTrue(loop.echo.shouldAcceptUserInput())
        XCTAssertFalse(loop.shouldSpeakVerbatimOnLive)
        XCTAssertTrue(loop.invariantFailures().isEmpty, "\(loop.invariantFailures())")
    }

    func testThinkingWatchdogDoesNotCancelVerbatim() {
        var loop = VoiceLiveLoop()
        loop.apply(.tapTalk)
        loop.apply(.speechStopped)
        XCTAssertEqual(loop.session.state, .thinking)
        loop.apply(.beginVerbatim)
        loop.apply(.watchdogTick(elapsed: 4))
        XCTAssertTrue(loop.verbatim.isSpeaking)
        loop.apply(.responseCreated(id: "verbatim-1"))
        XCTAssertEqual(loop.session.state, .speaking)
    }

    func testClaimThenUnmuteGeneralClearsSuppress() {
        var loop = VoiceLiveLoop()
        loop.apply(.tapTalk)
        loop.apply(.claimDesk)
        XCTAssertTrue(loop.dropAudio)
        loop.apply(.unmuteGeneral)
        XCTAssertFalse(loop.dropAudio)
        loop.apply(.responseCreated(id: "wx"))
        XCTAssertEqual(loop.session.state, .speaking)
    }

    func testWeatherAndJohnWickAreGeneralRoutes() {
        XCTAssertFalse(ConversationPresence.ownsConnectedDeskTurn("What's the weather like in Tarpon Springs?"))
        XCTAssertFalse(ConversationPresence.ownsConnectedDeskTurn("How's the weather today in Tarpon Springs?"))
        XCTAssertFalse(ConversationPresence.ownsConnectedDeskTurn("What year did John Wick get released"))
        XCTAssertTrue(ConversationPresence.ownsConnectedDeskTurn("Show me my latest emails"))
    }
}

final class VoiceEarconPolicyTests: XCTestCase {
    func testEarconsOnlyOnMicOnOff() {
        XCTAssertTrue(VoiceEarconPolicy.shouldPlay(on: .tapTalkOn))
        XCTAssertTrue(VoiceEarconPolicy.shouldPlay(on: .tapTalkOff))
        XCTAssertTrue(VoiceEarconPolicy.shouldPlay(on: .cancel))
        XCTAssertFalse(VoiceEarconPolicy.shouldPlay(on: .userUtterance))
        XCTAssertFalse(VoiceEarconPolicy.shouldPlay(on: .eveSpeak))
        XCTAssertFalse(VoiceEarconPolicy.shouldPlay(on: .cardAttach))
        XCTAssertFalse(VoiceEarconPolicy.shouldPlay(on: .deskReply))
        XCTAssertFalse(VoiceEarconPolicy.shouldPlay(on: .grokError))
    }
}
