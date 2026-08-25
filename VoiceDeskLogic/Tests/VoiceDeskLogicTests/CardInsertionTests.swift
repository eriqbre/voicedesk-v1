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

    func testEmailCardTapTogglesCompactAndFull() {
        let compact = SampleData.email().presented(as: .compact)
        XCTAssertTrue(compact.isCompactListRow)
        XCTAssertEqual(compact.cardPresentation.tapIdentifier, "card.email.compact")

        let opened = compact.togglingCardPresentation()
        XCTAssertFalse(opened.isCompactListRow)
        XCTAssertEqual(opened.cardPresentation, .full)
        XCTAssertEqual(opened.cardPresentation.tapIdentifier, "card.email.full")
        XCTAssertEqual(opened.id, compact.id)
        XCTAssertEqual(opened.subject, compact.subject)

        let collapsed = opened.togglingCardPresentation()
        XCTAssertTrue(collapsed.isCompactListRow)
        XCTAssertEqual(collapsed.cardPresentation, .compact)
        XCTAssertEqual(collapsed.cardPresentation.tapIdentifier, "card.email.compact")
        XCTAssertEqual(collapsed.id, compact.id)
        XCTAssertEqual(ContentCard.email(collapsed).fixtureID, "card.email")
        XCTAssertEqual(ContentCard.email(opened).fixtureID, "card.email")
        XCTAssertEqual(ContentCard.email(collapsed).emailPresentationState, "compact")
        XCTAssertEqual(ContentCard.email(opened).emailPresentationState, "full")
    }

    func testTourGraphEmailStartsFullButWrapperIDStaysCardEmail() {
        guard case .email(let item) = TourScript.graphCards().first else {
            XCTFail("tour graph starts with the sample email")
            return
        }
        XCTAssertEqual(item.cardPresentation, .full)
        XCTAssertFalse(item.isCompactListRow)
        XCTAssertEqual(ContentCard.email(item).fixtureID, "card.email")
        XCTAssertEqual(ContentCard.email(item).emailPresentationState, "full")
        XCTAssertEqual(item.cardPresentation.tapIdentifier, "card.email.full")
        XCTAssertNotEqual(
            item.cardPresentation.tapIdentifier,
            ContentCard.email(item).fixtureID,
            "smoke must query card.email; inner tap id is not the wrapper"
        )
    }
}
