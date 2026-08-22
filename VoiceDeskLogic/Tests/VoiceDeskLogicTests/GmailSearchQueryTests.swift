import XCTest
@testable import VoiceDeskLogic

final class GmailSearchQueryTests: XCTestCase {
    func testBaselineInboxLimitIs25() {
        XCTAssertEqual(GoogleSyncPolicy.recentInboxLimit, 25)
    }

    func testMurrayAskUsesFromClause() {
        let query = GmailSearchQuery.query(from: "Hey, show me Murray's latest email.")
        XCTAssertEqual(query, "from:murray")
    }

    func testSteveBrownPossessiveKeepsFirstNameAsFrom() {
        let query = GmailSearchQuery.query(from: "show me Steve Brown's note")
        XCTAssertEqual(query, "from:steve brown")
    }

    func testExplicitFromColonIsPreserved() {
        let query = GmailSearchQuery.query(from: "pull up from:ada inspection")
        XCTAssertTrue(query?.contains("from:ada") == true)
        XCTAssertTrue(query?.contains("inspection") == true)
    }

    func testFullThreadFollowUpHasNoSearchTokens() {
        XCTAssertNil(GmailSearchQuery.query(from: "Can you summarize the full thread?"))
    }

    func testFindMurraysClosingNoteWithoutSayingEmail() {
        let query = GmailSearchQuery.query(from: "find Murray's closing note")
        XCTAssertTrue(query?.contains("from:murray") == true)
        XCTAssertTrue(query?.contains("closing") == true)
        XCTAssertTrue(GmailSearchQuery.hasSenderPattern("find Murray's closing note"))
    }

    func testEmailAboutSubjectTokens() {
        let query = GmailSearchQuery.query(from: "email about the inspection window")
        XCTAssertTrue(query?.contains("inspection") == true)
        XCTAssertTrue(query?.contains("window") == true)
    }

    func testDidMurraySendSomethingUsesFrom() {
        let query = GmailSearchQuery.query(from: "Did Murray send me something?")
        XCTAssertTrue(query?.contains("from:murray") == true)
    }
}
