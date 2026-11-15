import XCTest
@testable import LeanKeysKit

private struct RegistrationFailed: Error {}

final class FirstRunTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "FirstRunTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFirstRunEnablesLaunchAtLoginOnceAndSetsFlag() {
        var calls = 0
        FirstRun.performIfNeeded(defaults: defaults, enableLaunchAtLogin: { calls += 1 })
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(defaults.bool(forKey: "LeanKeys.firstRunDone"))
    }

    func testLaterRunsDoNothing() {
        var calls = 0
        FirstRun.performIfNeeded(defaults: defaults, enableLaunchAtLogin: { calls += 1 })
        FirstRun.performIfNeeded(defaults: defaults, enableLaunchAtLogin: { calls += 1 })
        FirstRun.performIfNeeded(defaults: defaults, enableLaunchAtLogin: { calls += 1 })
        XCTAssertEqual(calls, 1)
    }

    func testFailureLeavesFlagUnsetSoNextLaunchRetries() {
        var calls = 0
        FirstRun.performIfNeeded(defaults: defaults, enableLaunchAtLogin: { calls += 1; throw RegistrationFailed() })
        XCTAssertFalse(defaults.bool(forKey: "LeanKeys.firstRunDone"))

        FirstRun.performIfNeeded(defaults: defaults, enableLaunchAtLogin: { calls += 1 })
        XCTAssertEqual(calls, 2, "the next launch tries again")
        XCTAssertTrue(defaults.bool(forKey: "LeanKeys.firstRunDone"))
    }
}
