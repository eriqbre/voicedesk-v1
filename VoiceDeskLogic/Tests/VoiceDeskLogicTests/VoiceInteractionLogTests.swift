import XCTest
@testable import VoiceDeskLogic

final class VoiceInteractionLogTests: XCTestCase {
    override func setUp() {
        VoiceInteractionLog.resetForTests()
    }

    func testReleasePathNeverPersistsTranscripts() {
        #if DEBUG
        XCTAssertTrue(VoiceInteractionLog.isEnabled)
        let entry = VoiceInteractionEntry(
            source: "text",
            userTranscript: "secret utterance",
            intent: "general",
            routingNotes: [],
            cardsAttached: [],
            assistantReply: "ok",
            voicePath: "AVSpeech"
        )
        VoiceInteractionLog.record(entry)
        XCTAssertEqual(VoiceInteractionLog.snapshot().last?.userTranscript, "secret utterance")
        XCTAssertTrue(VoiceInteractionLog.exportJSON().contains("secret utterance"))
        #else
        XCTAssertFalse(VoiceInteractionLog.isEnabled)
        VoiceInteractionLog.record(
            VoiceInteractionEntry(
                source: "text",
                userTranscript: "secret utterance",
                intent: "general",
                routingNotes: [],
                cardsAttached: [],
                assistantReply: "ok",
                voicePath: "AVSpeech"
            )
        )
        XCTAssertTrue(VoiceInteractionLog.snapshot().isEmpty)
        XCTAssertEqual(VoiceInteractionLog.exportJSON(), "[]")
        #endif
    }

    func testClassifyInboxOverviewClearsStickyVsMurrayPerson() {
        let murray = EmailItem(
            providerID: "log-murray",
            fromName: "Murray Mitchell",
            fromEmail: "murray@example.com",
            sentAtLabel: "Today 9:00 AM",
            subject: "Closing / notarization",
            preview: "Need you to notarize",
            body: "Need you to notarize today.",
            filterTag: "Inbox"
        )
        let steve = EmailItem(
            providerID: "log-steve",
            fromName: "Steve Brown",
            fromEmail: "steve@example.com",
            sentAtLabel: "Today 8:00 AM",
            subject: "Inspection note",
            preview: "Punch list",
            filterTag: "Inbox"
        )
        let context = DeskContext(
            isConnected: true,
            snapshot: DeskSnapshot(emails: [murray, steve])
        )
        let overview = ConversationPresence.deskEvidence(
            for: "summary of my latest emails",
            context: context,
            focusedEmail: murray
        )
        let classified = VoiceInteractionLog.classify(
            utterance: "summary of my latest emails",
            evidence: overview,
            hadFocusedEmail: true
        )
        XCTAssertEqual(classified.intent, "inbox-overview")
        XCTAssertTrue(classified.notes.contains("sticky cleared"))
        XCTAssertNil(overview?.focusedEmail)

        let person = ConversationPresence.deskEvidence(
            for: "summarize the Murray email",
            context: context,
            focusedEmail: steve
        )
        let personClass = VoiceInteractionLog.classify(
            utterance: "summarize the Murray email",
            evidence: person,
            hadFocusedEmail: true
        )
        XCTAssertTrue(["desk-person", "desk-thread"].contains(personClass.intent), personClass.intent)
        XCTAssertNotEqual(personClass.intent, "inbox-overview")
        XCTAssertFalse(personClass.notes.contains("sticky cleared"))
        if case .email(let item) = person?.cards.first {
            XCTAssertEqual(item.fromName, "Murray Mitchell")
        } else {
            XCTFail("expected Murray person path")
        }
    }

    func testMacHostPathIsStableUnderDesktopProjects() {
        XCTAssertEqual(
            VoiceDebugLogPaths.documentedMacPath,
            "~/Desktop/projects/voicedesk-v1/.debug/voice-log.jsonl"
        )
        XCTAssertEqual(
            VoiceDebugLogPaths.macHostRelativePath,
            "Desktop/projects/voicedesk-v1/.debug/voice-log.jsonl"
        )
        let url = VoiceDebugLogPaths.macHostFileURL(home: "/Users/eriq")
        XCTAssertEqual(
            url.path,
            "/Users/eriq/Desktop/projects/voicedesk-v1/.debug/voice-log.jsonl"
        )
        XCTAssertTrue(url.path.hasSuffix("/.debug/voice-log.jsonl"))
    }

    func testSimulatorHostHomePrefersEnvThenCoreSimulatorPrefix() {
        XCTAssertEqual(
            VoiceDebugLogPaths.simulatorHostHome(
                environment: ["SIMULATOR_HOST_HOME": "/Users/eriq"],
                sandboxHome: "/Users/eriq/Library/Developer/CoreSimulator/Devices/ABC/data"
            ),
            "/Users/eriq"
        )
        XCTAssertEqual(
            VoiceDebugLogPaths.simulatorHostHome(
                environment: [:],
                sandboxHome: "/Users/eriq/Library/Developer/CoreSimulator/Devices/ABC/data/Containers/Data/Application/UUID"
            ),
            "/Users/eriq"
        )
        XCTAssertNil(
            VoiceDebugLogPaths.simulatorHostHome(
                environment: [:],
                sandboxHome: "/var/mobile/Containers/Data/Application/UUID"
            )
        )
    }

    func testICloudDrivePathIsCloudDocsVoiceDeskDebug() {
        XCTAssertEqual(
            VoiceDebugLogPaths.documentedICloudDrivePath,
            "~/Library/Mobile Documents/com~apple~CloudDocs/VoiceDesk-debug/voice-log.jsonl"
        )
        let url = VoiceDebugLogPaths.iCloudDriveFileURL(home: "/Users/eriq")
        XCTAssertEqual(
            url.path,
            "/Users/eriq/Library/Mobile Documents/com~apple~CloudDocs/VoiceDesk-debug/voice-log.jsonl"
        )
    }

    func testJsonlLineIsSingleLineAndDoesNotUpload() {
        let entry = VoiceInteractionEntry(
            source: "text",
            userTranscript: "secret line\nwith break",
            intent: "general",
            routingNotes: ["sticky cleared"],
            cardsAttached: ["email:Murray:Hi"],
            assistantReply: "ok",
            voicePath: "Eve realtime"
        )
        guard let data = VoiceDebugLogPaths.jsonlLineData(for: entry),
              let text = String(data: data, encoding: .utf8)
        else {
            return XCTFail("expected jsonl bytes")
        }
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertEqual(text.filter { $0 == "\n" }.count, 1)
        XCTAssertTrue(text.contains("secret line"))
        XCTAssertTrue(text.contains("Eve realtime"))
    }
}
