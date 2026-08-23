import XCTest
@testable import VoiceDeskLogic

final class CardInsertionTests: XCTestCase {
    func testTourInsertsRequiredCardKinds() {
        var document = ConversationDocument()
        TourScript.play(into: &document)

        for kind in TourScript.requiredKinds {
            XCTAssertFalse(
                document.cards(of: kind).isEmpty,
                "Tour must insert \(kind.rawValue)"
            )
        }
        XCTAssertGreaterThanOrEqual(document.cards(of: .person).count, 2)
    }

    func testFixtureIDsAreStable() {
        XCTAssertEqual(ContentCard.email(SampleData.email()).fixtureID, "card.email")
        XCTAssertEqual(ContentCard.listing(SampleData.listing()).fixtureID, "card.listing")
        XCTAssertEqual(ContentCard.person(SampleData.buyer()).fixtureID, "card.person")
        XCTAssertEqual(ContentCard.draftConfirm(SampleData.draftReply()).fixtureID, "card.draftConfirm")
        XCTAssertEqual(ContentCard.statute(SampleData.statute()).fixtureID, "card.statute")
        XCTAssertEqual(ContentCard.connectGoogle(SampleData.connectGoogle()).fixtureID, "card.connectGoogle")
        XCTAssertEqual(ContentCard.calendar(SampleData.calendarEvent()).fixtureID, "card.calendar")
        XCTAssertEqual(ContentCard.task(SampleData.openTask()).fixtureID, "card.task")
    }

    func testAccessibilityIdentityIsNonEmptyForEveryKind() {
        let cards: [ContentCard] = [
            .email(SampleData.email()),
            .listing(SampleData.listing()),
            .person(SampleData.buyer()),
            .draftConfirm(SampleData.draftReply()),
            .statute(SampleData.statute()),
            .connectGoogle(SampleData.connectGoogle()),
            .calendar(SampleData.calendarEvent()),
            .task(SampleData.openTask())
        ]
        for card in cards {
            XCTAssertFalse(card.accessibilityIdentity.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func testUserTurnsDoNotInsertCards() {
        var document = ConversationDocument()
        document.appendUser("What's in my inbox?")
        XCTAssertTrue(document.insertedCards.isEmpty)
    }

    func testMultiEmailListCardsAreCompactSingleIsFull() {
        let one = EmailItem.listCards([SampleData.email()])
        if case .email(let item) = one.first {
            XCTAssertFalse(item.isCompactListRow)
        } else {
            XCTFail("expected one full email card")
        }
        let many = EmailItem.listCards([SampleData.email(), SampleData.syncedEmail()])
        XCTAssertEqual(many.count, 2)
        XCTAssertTrue(many.allSatisfy { card in
            if case .email(let item) = card { return item.isCompactListRow }
            return false
        })
    }
}
