import XCTest
@testable import LeanKeysKit

final class TCCResetTests: XCTestCase {
    private let bundleID = "io.github.anlvdt.leankeys"

    func testArguments() {
        XCTAssertEqual(TCCReset.arguments(bundleID: bundleID),
                       ["reset", "Accessibility", "io.github.anlvdt.leankeys"])
    }

    /// The stub runner only: the real /usr/bin/tccutil is never executed by tests.
    func testRunReportsExitStatus() {
        var calls: [(URL, [String])] = []
        let success = TCCReset.run(bundleID: bundleID) { url, args in
            calls.append((url, args))
            return 0
        }
        XCTAssertTrue(success)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, URL(fileURLWithPath: "/usr/bin/tccutil"))
        XCTAssertEqual(calls.first?.1, TCCReset.arguments(bundleID: bundleID))

        let failure = TCCReset.run(bundleID: bundleID) { _, _ in 1 }
        XCTAssertFalse(failure)
    }
}
