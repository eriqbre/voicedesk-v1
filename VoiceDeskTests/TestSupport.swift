import XCTest

@MainActor
extension XCTestCase {
    /// Several `AppModel` paths finish inside a detached `Task` — `connectGoogle`,
    /// `surfaceDeskEvidence` — so the work has not run yet on the next line.
    /// `await`ing the non-async method that spawns them does nothing. Poll the
    /// observable outcome instead.
    func waitUntil(
        _ description: String = "condition",
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(predicate(), "timed out waiting for \(description)", file: file, line: line)
    }
}
