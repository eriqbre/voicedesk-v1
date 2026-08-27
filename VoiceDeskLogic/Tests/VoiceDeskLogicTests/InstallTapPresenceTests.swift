import XCTest
@testable import VoiceDeskLogic

final class InstallTapPresenceTests: XCTestCase {
    func testReleaseWithoutInvalidateIsMissing() {
        let presence = InstallTapPresence()
        var hold: InstallTapHold? = presence.nextHold()
        XCTAssertFalse(presence.isReleased, "HAL still holds the install block")
        hold = nil
        XCTAssertTrue(presence.isReleased, "HAL released the install block — SET missing")
    }

    func testInvalidateThenOldReleaseDoesNotMarkNextMissing() {
        let presence = InstallTapPresence()
        var hold: InstallTapHold? = presence.nextHold()
        presence.invalidate()
        hold = nil
        XCTAssertFalse(
            presence.isReleased,
            "our removeTap must not leave leftover drain-time reinstall marked released"
        )
        let next = presence.nextHold()
        XCTAssertFalse(presence.isReleased)
        _ = next
    }

    func testHoldDeinitDoesNotNameReinstall() throws {
        let source = try XCTUnwrap(Self.repoFile("VoiceDeskLogic/Sources/VoiceDeskLogic/InstallTapPresence.swift"))
        XCTAssertFalse(
            source.contains("reinstallTap"),
            "hold deinit must SET missing only — deinit put-back raced leftover"
        )
        XCTAssertFalse(source.contains("HALTapLease"), source)
        XCTAssertFalse(source.contains("Task.sleep"), source)
    }

    private static func repoFile(_ relative: String) -> String? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try? String(contentsOf: candidate, encoding: .utf8)
            }
        }
        return nil
    }
}
