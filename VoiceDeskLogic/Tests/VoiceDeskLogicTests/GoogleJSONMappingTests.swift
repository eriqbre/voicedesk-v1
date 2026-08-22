import XCTest
@testable import VoiceDeskLogic

final class GoogleJSONMappingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_400_000) // 2026-08-22-ish

    func testMapsGmailMessageAndParsesFrom() throws {
        let json = """
        {
          "messages": [
            {
              "id": "m1",
              "threadId": "t1",
              "snippet": "Can we walk the punch list?",
              "internalDate": "1787400000000",
              "payload": {
                "headers": [
                  {"name": "From", "value": "Ada Cole <ada.cole@example.com>"},
                  {"name": "Subject", "value": "Inspection questions"}
                ]
              }
            },
            {
              "id": "m1-dup",
              "threadId": "t1",
              "snippet": "duplicate thread",
              "payload": {
                "headers": [
                  {"name": "From", "value": "Ada Cole <ada.cole@example.com>"},
                  {"name": "Subject", "value": "Inspection questions"}
                ]
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let emails = try GoogleJSONMapping.emails(fromMessagesJSON: json, now: now)
        XCTAssertEqual(emails.count, 1)
        XCTAssertEqual(emails[0].fromName, "Ada Cole")
        XCTAssertEqual(emails[0].fromEmail, "ada.cole@example.com")
        XCTAssertEqual(emails[0].subject, "Inspection questions")
        XCTAssertEqual(emails[0].preview, "Can we walk the punch list?")
        XCTAssertEqual(emails[0].threadID, "t1")
        XCTAssertFalse(emails[0].fromName.contains("Jordan"))
    }

    func testMapsCalendarAndOpenTasks() throws {
        let calendar = """
        {
          "items": [
            {
              "id": "evt1",
              "summary": "Offer review",
              "location": "Coastal office",
              "start": { "dateTime": "2026-08-22T15:00:00Z" },
              "attendees": [{ "displayName": "Priya Shah" }]
            },
            {
              "id": "evt1",
              "summary": "duplicate",
              "start": { "dateTime": "2026-08-22T15:00:00Z" }
            }
          ]
        }
        """.data(using: .utf8)!
        let events = try GoogleJSONMapping.events(fromCalendarJSON: calendar, now: now)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].title, "Offer review")
        XCTAssertEqual(events[0].location, "Coastal office")
        XCTAssertEqual(events[0].relatedPeople, ["Priya Shah"])

        let tasks = """
        {
          "items": [
            { "id": "tk1", "title": "Call lender", "status": "needsAction" },
            { "id": "tk2", "title": "Done already", "status": "completed" },
            { "id": "tk1", "title": "Call lender again", "status": "needsAction" }
          ]
        }
        """.data(using: .utf8)!
        let open = try GoogleJSONMapping.tasks(fromTasksJSON: tasks)
        XCTAssertEqual(open.map(\.title), ["Call lender"])
        XCTAssertFalse(open.contains { $0.isCompleted })
    }

    func testDraftReplyUsesRealThreadNotSample() {
        let email = SampleData.syncedEmail()
        let draft = GoogleJSONMapping.draftReply(to: email)
        XCTAssertTrue(draft.toLine.contains("ada.cole@example.com"))
        XCTAssertTrue(draft.subject.hasPrefix("Re:"))
        XCTAssertFalse(draft.toLine.lowercased().contains("jordan"))
        XCTAssertEqual(draft.status, .pending)
    }

    func testParseFromBareEmail() {
        let parsed = GoogleJSONMapping.parseFrom("ada@example.com")
        XCTAssertEqual(parsed.name, "ada@example.com")
        XCTAssertEqual(parsed.email, "ada@example.com")
    }

    func testDecodesHTMLEntitiesInSubjectAndSnippet() throws {
        XCTAssertEqual(GoogleJSONMapping.decodeHTMLEntities("&quot;Deal&quot; &amp; more"), "\"Deal\" & more")
        XCTAssertEqual(GoogleJSONMapping.decodeHTMLEntities("it&#39;s &lt;ok&gt;"), "it's <ok>")
        XCTAssertEqual(GoogleJSONMapping.decodeHTMLEntities("&#x27;hex&#x27;"), "'hex'")

        let json = """
        {
          "messages": [
            {
              "id": "amz1",
              "threadId": "tamz",
              "snippet": "Your Amazon.com order of &quot;Echo&quot; has shipped.",
              "payload": {
                "headers": [
                  {"name": "From", "value": "Amazon <auto@amazon.com>"},
                  {"name": "Subject", "value": "Your Amazon.com order of &quot;Echo&quot;"}
                ]
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let emails = try GoogleJSONMapping.emails(fromMessagesJSON: json, now: now)
        XCTAssertEqual(emails[0].subject, "Your Amazon.com order of \"Echo\"")
        XCTAssertEqual(emails[0].preview, "Your Amazon.com order of \"Echo\" has shipped.")
        XCTAssertFalse(emails[0].subject.contains("&quot;"))
        XCTAssertFalse(emails[0].preview.contains("&quot;"))
        XCTAssertNil(emails[0].body)
    }

    func testExtractsPlainTextBodyFromFullMessage() {
        let plain = "Murray here — walk the lot Saturday."
        let encoded = Data(plain.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let message: [String: Any] = [
            "id": "m-murray",
            "threadId": "t-murray",
            "snippet": "Murray here",
            "payload": [
                "mimeType": "multipart/alternative",
                "parts": [
                    [
                        "mimeType": "text/plain",
                        "body": ["data": encoded]
                    ]
                ]
            ]
        ]
        XCTAssertEqual(GoogleJSONMapping.plainTextBody(from: message), plain)
        let email = GoogleJSONMapping.email(from: message, now: now)
        XCTAssertEqual(email?.body, plain)
        XCTAssertTrue(email?.hasFullBody == true)
    }
}
