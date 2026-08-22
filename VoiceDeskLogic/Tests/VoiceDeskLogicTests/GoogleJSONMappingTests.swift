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
              "description": "<p>Window table &amp; party of 4. Ask for Massimo.</p>",
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
        XCTAssertEqual(events[0].notes, "Window table & party of 4. Ask for Massimo.")
        XCTAssertTrue(events[0].hasDetails)

        let legacy = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "title": "Dinner reservation",
          "whenLabel": "Tonight 7:00 PM",
          "relatedPeople": ["Massimo Ricci"]
        }
        """.data(using: .utf8)!
        let cached = try JSONDecoder().decode(CalendarItem.self, from: legacy)
        XCTAssertNil(cached.notes)
        XCTAssertEqual(cached.title, "Dinner reservation")
        XCTAssertEqual(cached.relatedPeople, ["Massimo Ricci"])

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

    func testStripsHTMLBodyAndDecodesEntities() {
        let html = "<p>Murray said &quot;walk the lot&quot; Saturday.</p><br>See you &#39;there&#39;."
        let message: [String: Any] = [
            "id": "m-html",
            "threadId": "t-html",
            "snippet": "Murray said",
            "payload": [
                "mimeType": "text/html",
                "body": ["data": b64url(html)]
            ]
        ]
        let body = GoogleJSONMapping.plainTextBody(from: message)
        XCTAssertEqual(body, "Murray said \"walk the lot\" Saturday.\n\nSee you 'there'.")
        XCTAssertFalse((body ?? "").contains("&quot;"))
        XCTAssertFalse((body ?? "").contains("<p>"))
        XCTAssertTrue((body ?? "").contains("\n"))
    }

    func testMurrayQuotedReplyKeepsLatestAndExposesEarlier() {
        let plain = """
        Hi Jordan,

        Can we walk the lot Saturday at 10?

        Thanks,
        Murray

        On Tue, Aug 19, 2026 at 4:02 PM Jordan Hale wrote:
        > Sounds good
        >> Let's lock Saturday
        """
        let message: [String: Any] = [
            "id": "m-murray",
            "threadId": "t-murray",
            "snippet": "Can we walk the lot",
            "payload": [
                "mimeType": "text/plain",
                "headers": [
                    ["name": "From", "value": "Murray Cole <murray@example.com>"],
                    ["name": "Subject", "value": "Lot walk"]
                ],
                "body": ["data": b64url(plain)]
            ]
        ]
        let email = GoogleJSONMapping.email(from: message, now: now)
        XCTAssertEqual(email?.fromName, "Murray Cole")
        XCTAssertTrue(email?.body?.contains("walk the lot Saturday") == true)
        XCTAssertTrue(email?.body?.contains("Thanks,") == true)
        XCTAssertFalse(email?.body?.contains(">>") == true)
        XCTAssertFalse(email?.body?.contains("Sounds good") == true)
        XCTAssertEqual(email?.earlierMessages.count, 1)
        XCTAssertTrue(email?.earlierMessages.first?.plainBody?.contains("Sounds good") == true)
        XCTAssertTrue(email?.earlierMessages.first?.plainBody?.contains("Let's lock Saturday") == true)
        XCTAssertFalse(email?.earlierMessages.first?.plainBody?.contains(">>") == true)
    }

    func testAmazonHTMLKeepsParagraphsAndPrefersHTML() {
        let html = """
        <html><body>
        <p>Your Amazon.com order of &quot;Echo Dot&quot; has shipped.</p>
        <p>Track it here:</p>
        <p><a href="https://www.amazon.com/progress-tracker/package">https://www.amazon.com/progress-tracker/package</a></p>
        <div class="gmail_quote">On Monday someone wrote:<br>&gt; thanks</div>
        </body></html>
        """
        let message: [String: Any] = [
            "id": "m-amz",
            "threadId": "t-amz",
            "snippet": "Your Amazon.com order of &quot;Echo Dot&quot; has shipped.",
            "payload": [
                "mimeType": "text/html",
                "headers": [
                    ["name": "From", "value": "Amazon <auto@amazon.com>"],
                    ["name": "Subject", "value": "Your Amazon.com order of &quot;Echo Dot&quot;"]
                ],
                "body": ["data": b64url(html)]
            ]
        ]
        let email = GoogleJSONMapping.email(from: message, now: now)
        XCTAssertEqual(email?.subject, "Your Amazon.com order of \"Echo Dot\"")
        XCTAssertTrue(email?.htmlBody?.contains("Echo Dot") == true)
        XCTAssertFalse(email?.htmlBody?.contains("gmail_quote") == true)
        XCTAssertTrue(email?.body?.contains("Echo Dot") == true)
        XCTAssertTrue(email?.body?.contains("\n") == true)
        XCTAssertFalse(email?.body?.contains("&quot;") == true)
        XCTAssertFalse(email?.body?.contains("<p>") == true)
        XCTAssertFalse(email?.body?.contains("thanks") == true)
        let spoken = EmailBodyFormatting.spokenSummary(from: email?.body, fallback: email?.preview ?? "")
        XCTAssertTrue(spoken.contains("Echo Dot"))
        XCTAssertFalse(spoken.contains("https://"))
        XCTAssertLessThan(spoken.count, 160)
    }

    func testThreadJSONUsesLatestByDefaultAndKeepsHistory() {
        let older = """
        Sounds good — Saturday works.
        """
        let latest = """
        Walk the lot Saturday at 10.
        """
        let thread: [String: Any] = [
            "id": "t-chain",
            "messages": [
                [
                    "id": "m-old",
                    "threadId": "t-chain",
                    "internalDate": "1787300000000",
                    "snippet": "Sounds good",
                    "payload": [
                        "mimeType": "text/plain",
                        "headers": [
                            ["name": "From", "value": "Jordan Hale <jordan@example.com>"],
                            ["name": "Subject", "value": "Lot walk"]
                        ],
                        "body": ["data": b64url(older)]
                    ]
                ],
                [
                    "id": "m-new",
                    "threadId": "t-chain",
                    "internalDate": "1787400000000",
                    "snippet": "Walk the lot",
                    "payload": [
                        "mimeType": "text/plain",
                        "headers": [
                            ["name": "From", "value": "Murray Cole <murray@example.com>"],
                            ["name": "Subject", "value": "Re: Lot walk"]
                        ],
                        "body": ["data": b64url(latest)]
                    ]
                ]
            ]
        ]
        let email = GoogleJSONMapping.email(fromThread: thread, now: now)
        XCTAssertEqual(email?.providerID, "m-new")
        XCTAssertEqual(email?.fromName, "Murray Cole")
        XCTAssertEqual(email?.body, "Walk the lot Saturday at 10.")
        XCTAssertFalse(email?.body?.contains("Sounds good") == true)
        XCTAssertEqual(email?.earlierMessages.count, 1)
        XCTAssertEqual(email?.earlierMessages.first?.fromName, "Jordan Hale")
        XCTAssertEqual(email?.earlierMessages.first?.plainBody, "Sounds good — Saturday works.")
    }

    func testDoesNotDoubleEncodeEntities() {
        XCTAssertEqual(GoogleJSONMapping.decodeHTMLEntities("&amp;quot;Deal&amp;quot;"), "\"Deal\"")
        XCTAssertEqual(
            EmailBodyFormatting.spokenSummary(from: "Track https://www.amazon.com/x shipped.", fallback: ""),
            "Track shipped."
        )
    }

    func testOldCachedEmailJSONStillDecodes() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","fromName":"Ada","fromEmail":"ada@example.com","sentAtLabel":"Today","subject":"Hi","preview":"Hello","filterTag":"Inbox"}
        """.data(using: .utf8)!
        let email = try JSONDecoder().decode(EmailItem.self, from: json)
        XCTAssertEqual(email.fromName, "Ada")
        XCTAssertNil(email.htmlBody)
        XCTAssertTrue(email.earlierMessages.isEmpty)
        XCTAssertFalse(email.hasFullBody)
    }

    private func b64url(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
