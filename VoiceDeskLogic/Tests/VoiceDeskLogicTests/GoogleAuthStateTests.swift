import XCTest
@testable import VoiceDeskLogic

final class GoogleAuthStateTests: XCTestCase {
    func testMissingClientIDNeverBecomesConnected() {
        var snap = GoogleAuthSnapshot.signedOut
        snap = GoogleAuthSnapshot.reduce(snap, .clientIDMissing)
        XCTAssertEqual(snap.state, .missingClientID)
        XCTAssertFalse(snap.isConnected)
        XCTAssertTrue(snap.setupNeeded)

        snap = GoogleAuthSnapshot.reduce(snap, .connectStarted)
        XCTAssertEqual(snap.state, .missingClientID)
        XCTAssertFalse(snap.isConnected)

        snap = GoogleAuthSnapshot.reduce(snap, .connectFailed("should stay setup"))
        XCTAssertEqual(snap.state, .missingClientID)
        XCTAssertFalse(snap.isConnected)
    }

    func testSuccessRequiresEmail() {
        var snap = GoogleAuthSnapshot.reduce(.signedOut, .connectStarted)
        XCTAssertEqual(snap.state, .connecting)

        snap = GoogleAuthSnapshot.reduce(snap, .connectSucceeded(email: "  "))
        XCTAssertEqual(snap.state, .failed)
        XCTAssertFalse(snap.isConnected)

        snap = GoogleAuthSnapshot.reduce(snap, .connectStarted)
        snap = GoogleAuthSnapshot.reduce(snap, .connectSucceeded(email: "ada@example.com"))
        XCTAssertTrue(snap.isConnected)
        XCTAssertEqual(snap.email, "ada@example.com")
        XCTAssertTrue(snap.statusLine.contains("ada@example.com"))
    }

    func testDisconnectClearsAccount() {
        var snap = GoogleAuthSnapshot.reduce(.signedOut, .connectSucceeded(email: "ada@example.com"))
        XCTAssertTrue(snap.isConnected)
        snap = GoogleAuthSnapshot.reduce(snap, .disconnect)
        XCTAssertEqual(snap, .signedOut)
        XCTAssertFalse(snap.isConnected)
        XCTAssertNil(snap.email)
    }

    func testReversedClientID() {
        XCTAssertEqual(
            GoogleScopes.reversedClientID(from: "123-abc.apps.googleusercontent.com"),
            "com.googleusercontent.apps.123-abc"
        )
        XCTAssertNil(GoogleScopes.reversedClientID(from: "not-a-client-id"))
        XCTAssertTrue(GoogleScopes.readScopes.contains(GoogleScopes.gmailReadonly))
        XCTAssertFalse(GoogleScopes.readScopes.contains { $0.contains("gmail.send") })
    }
}
