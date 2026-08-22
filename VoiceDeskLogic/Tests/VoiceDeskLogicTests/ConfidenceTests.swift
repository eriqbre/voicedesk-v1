import XCTest
@testable import VoiceDeskLogic

final class ConfidenceTests: XCTestCase {
    func testBandThresholdsMatchPRD() {
        XCTAssertEqual(ConfidenceBand.band(for: 0), .unknown)
        XCTAssertEqual(ConfidenceBand.band(for: 49), .unknown)
        XCTAssertEqual(ConfidenceBand.band(for: 50), .options)
        XCTAssertEqual(ConfidenceBand.band(for: 84), .options)
        XCTAssertEqual(ConfidenceBand.band(for: 85), .firm)
        XCTAssertEqual(ConfidenceBand.band(for: 100), .firm)
    }

    func testStatuteClampsAndBindsTone() {
        let low = StatuteItem(
            title: "Unknown",
            plainLanguage: "Not sure.",
            citation: "",
            confidence: -4,
            disclaimer: ""
        )
        XCTAssertEqual(low.confidence, 0)
        XCTAssertEqual(low.band, .unknown)

        let presentation = ConfidencePresentation(statute: SampleData.statute())
        XCTAssertEqual(presentation.percent, 86)
        XCTAssertEqual(presentation.band, .firm)
        XCTAssertEqual(presentation.tone, "Firm")
        XCTAssertTrue(presentation.requiresCitation)
        XCTAssertTrue(presentation.citationVisible)
        XCTAssertTrue(presentation.citation.contains("475.278"))
    }

    func testMidConfidenceDoesNotRequireCitation() {
        let mid = ConfidencePresentation(percent: 70, citation: "Fla. Stat. § 1")
        XCTAssertEqual(mid.tone, "Options")
        XCTAssertFalse(mid.requiresCitation)
    }

    func testFirmWithoutCitationIsNotVisible() {
        let firm = ConfidencePresentation(percent: 90, citation: "  ")
        XCTAssertTrue(firm.requiresCitation)
        XCTAssertFalse(firm.citationVisible)
    }
}
