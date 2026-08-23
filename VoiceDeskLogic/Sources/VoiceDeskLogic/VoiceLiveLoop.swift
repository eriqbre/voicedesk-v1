import Foundation

/// Pure live-voice loop. Linux tests drive this; `GrokVoiceService` follows the same rules.
public struct VoiceLiveLoop: Equatable, Sendable {
    public var session = VoiceSession()
    public var echo = EchoBargeInGate()
    public var verbatim = VerbatimSpeakGate()
    public var dropAudio = false
    public var dropTranscript = false
    public var captureMuted = false
    public var userWantsVoiceOff = false
    public var lastError: String?
    public var audioDeltaCount = 0
    public var currentResponseID: String?

    public init() {}

    public enum Event: Equatable, Sendable {
        case tapTalk
        case cancel
        case claimDesk
        case unmuteGeneral
        case finishLocalDeskSpeech
        case beginVerbatim
        case speechStarted
        case speechStopped
        case responseCreated(id: String)
        case audioDelta
        case responseDone(id: String?)
        case error(code: String, message: String)
        case watchdogTick(elapsed: TimeInterval)
        case recovered
    }

    public mutating func apply(_ event: Event, at now: Date = Date()) {
        switch event {
        case .tapTalk:
            userWantsVoiceOff = false
            lastError = nil
            if (session.state == .speaking || session.state == .thinking), !verbatim.isSpeaking {
                recoverToListening(playedAudio: audioDeltaCount > 0, cancelVerbatim: false, at: now)
            }
            if session.state == .idle {
                echo.reset()
                captureMuted = false
                session.apply(.tapTalk)
            }
        case .cancel:
            userWantsVoiceOff = true
            verbatim.cancel()
            echo.reset()
            captureMuted = true
            lastError = nil
            currentResponseID = nil
            audioDeltaCount = 0
            dropAudio = false
            dropTranscript = false
            session.apply(.cancel)
        case .claimDesk:
            if verbatim.isSpeaking {
                dropTranscript = true
                dropAudio = verbatim.awaitingCreated
            } else {
                dropAudio = true
                dropTranscript = true
                interrupt(keepVerbatim: false, at: now)
            }
        case .unmuteGeneral:
            dropAudio = false
            dropTranscript = false
        case .finishLocalDeskSpeech:
            break
        case .beginVerbatim:
            verbatim.begin()
            beginHalfDuplex()
            dropAudio = true
            dropTranscript = true
            interrupt(keepVerbatim: true, at: now)
        case .speechStarted:
            guard echo.shouldAcceptUserInput(at: now) else { return }
            if !verbatim.isSpeaking {
                dropAudio = false
                dropTranscript = false
            }
            interrupt(keepVerbatim: true, at: now)
        case .speechStopped:
            if session.state == .listening {
                session.apply(.listenFinished)
            }
        case .responseCreated(let id):
            currentResponseID = id
            audioDeltaCount = 0
            if verbatim.created(id) {
                dropAudio = false
                dropTranscript = false
            }
            if AssistantPlaybackPolicy.shouldEnterHalfDuplex(
                dropAssistantAudio: dropAudio,
                verbatimSpeaking: verbatim.isSpeaking
            ) {
                beginHalfDuplex()
                session.apply(.speakStarted)
            } else if session.state == .thinking || session.state == .speaking {
                session.apply(.turnFinished)
            }
        case .audioDelta:
            guard !dropAudio else { return }
            audioDeltaCount += 1
        case .responseDone(let id):
            if verbatim.shouldIgnoreDone(eventID: id, currentID: currentResponseID) {
                return
            }
            let played = audioDeltaCount > 0
            session.apply(.turnFinished)
            let finishedID = currentResponseID
            currentResponseID = nil
            audioDeltaCount = 0
            endHalfDuplex(playedAudio: played, at: now)
            if verbatim.finishDone(eventID: id, currentID: finishedID) {
                dropAudio = AssistantPlaybackPolicy.restoreSuppressAfterVerbatim
                dropTranscript = AssistantPlaybackPolicy.restoreSuppressAfterVerbatim
            }
        case .error(let code, let message):
            lastError = GrokRealtime.formatError(code: code, message: message)
            recoverToListening(playedAudio: audioDeltaCount > 0, cancelVerbatim: true, at: now)
            lastError = GrokRealtime.formatError(code: code, message: message)
        case .watchdogTick(let elapsed):
            if session.state == .speaking,
               AssistantPlaybackPolicy.shouldForceEndSpeaking(
                audioDeltaCount: audioDeltaCount,
                elapsed: elapsed
               ) {
                recoverToListening(playedAudio: false, cancelVerbatim: true, at: now)
                lastError = nil
            } else if session.state == .thinking,
                      !verbatim.isSpeaking,
                      AssistantPlaybackPolicy.shouldForceEndThinking(elapsed: elapsed) {
                recoverToListening(playedAudio: false, cancelVerbatim: false, at: now)
                lastError = nil
            }
        case .recovered:
            lastError = nil
        }
    }

    public var shouldAcceptUserTranscript: Bool {
        session.state != .speaking && echo.shouldAcceptUserInput()
    }

    public var shouldSpeakVerbatimOnLive: Bool {
        session.state != .idle && !userWantsVoiceOff
    }

    public func invariantFailures(at now: Date = Date()) -> [String] {
        var failures: [String] = []
        if session.state == .speaking, dropAudio, !verbatim.isSpeaking {
            failures.append("stuck speaking while audio is dropped")
        }
        if userWantsVoiceOff, session.state != .idle {
            failures.append("voice-off must be idle")
        }
        if userWantsVoiceOff, !captureMuted {
            failures.append("voice-off must mute capture")
        }
        if !userWantsVoiceOff,
           session.state == .listening,
           !verbatim.isSpeaking,
           !echo.assistantSpeaking,
           captureMuted {
            failures.append("listening with capture still muted")
        }
        if echo.assistantSpeaking, !verbatim.isSpeaking, session.state != .speaking {
            failures.append("echo gate speaking without session speaking")
        }
        if let lastError, lastError.compare("unknown", options: .caseInsensitive) == .orderedSame {
            failures.append("opaque Unknown lastError")
        }
        if session.state == .idle, echo.shouldAcceptUserInput(at: now) == false, echo.assistantSpeaking {
            failures.append("echo permanently blocking after idle")
        }
        return failures
    }

    private mutating func beginHalfDuplex() {
        echo.assistantStarted()
        captureMuted = true
    }

    private mutating func endHalfDuplex(playedAudio: Bool, at now: Date) {
        if playedAudio {
            echo.assistantFinished(at: now)
        } else {
            echo.assistantAborted()
        }
        if !userWantsVoiceOff {
            captureMuted = false
        }
    }

    private mutating func recoverToListening(playedAudio: Bool, cancelVerbatim: Bool, at now: Date) {
        if cancelVerbatim, verbatim.isSpeaking {
            verbatim.cancel()
        }
        endHalfDuplex(playedAudio: playedAudio, at: now)
        currentResponseID = nil
        audioDeltaCount = 0
        if session.state == .speaking || session.state == .thinking {
            session.apply(.turnFinished)
        }
    }

    private mutating func interrupt(keepVerbatim: Bool, at now: Date) {
        let wasLive = session.state == .speaking || session.state == .thinking
        let played = audioDeltaCount > 0
        currentResponseID = nil
        audioDeltaCount = 0
        if wasLive {
            session.apply(.turnFinished)
            if !verbatim.isSpeaking || !keepVerbatim {
                endHalfDuplex(playedAudio: played, at: now)
            }
        }
    }
}

/// Mic clicks fire only for tap-to-talk on/off (and the matching cancel path).
public enum VoiceEarconPolicy: Sendable {
    public enum Trigger: String, Sendable {
        case tapTalkOn
        case tapTalkOff
        case cancel
        case userUtterance
        case eveSpeak
        case cardAttach
        case deskReply
        case grokError
    }

    public static func shouldPlay(on trigger: Trigger) -> Bool {
        switch trigger {
        case .tapTalkOn, .tapTalkOff, .cancel:
            return true
        case .userUtterance, .eveSpeak, .cardAttach, .deskReply, .grokError:
            return false
        }
    }
}
