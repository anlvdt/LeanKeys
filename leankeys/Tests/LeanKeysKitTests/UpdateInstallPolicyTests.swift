import XCTest
@testable import LeanKeysKit

final class UpdateInstallPolicyTests: XCTestCase {
    func testDeveloperIDBuildInstallsSilently() {
        XCTAssertTrue(UpdateInstallPolicy.installsSilently(teamIdentifier: "ABCDE12345"))
        XCTAssertTrue(UpdateInstallPolicy.installsSilently(readTeamIdentifier: { "ABCDE12345" }))
    }

    func testAdHocOrUnsignedBuildWaitsForAClick() {
        XCTAssertFalse(UpdateInstallPolicy.installsSilently(teamIdentifier: nil))
        XCTAssertFalse(UpdateInstallPolicy.installsSilently(teamIdentifier: ""))
        XCTAssertFalse(UpdateInstallPolicy.installsSilently(readTeamIdentifier: { nil }))
    }

    /// The live read must not crash; its value depends on how the test runner is signed.
    func testLiveReadIsConsistentWithPolicy() {
        let team = UpdateInstallPolicy.currentTeamIdentifier()
        XCTAssertEqual(UpdateInstallPolicy.installsSilently(), !(team ?? "").isEmpty)
    }
}
