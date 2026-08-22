import XCTest
@testable import VoiceDeskLogic

final class GmailSearchQueryTests: XCTestCase {
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
}
