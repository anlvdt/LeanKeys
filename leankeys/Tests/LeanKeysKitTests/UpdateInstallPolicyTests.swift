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

    func testSilentForDeveloperID() {
        XCTAssertTrue(UpdateInstallPolicy.installsSilently(signature: .developerID(team: "ABC")))
    }

    func testSilentForStableCertificate() {
        XCTAssertTrue(UpdateInstallPolicy.installsSilently(signature: .certificate))
    }

    func testNotSilentForAdhocOrUnsigned() {
        XCTAssertFalse(UpdateInstallPolicy.installsSilently(signature: .adhoc))
        XCTAssertFalse(UpdateInstallPolicy.installsSilently(signature: .unsigned))
    }

    func testEmptyTeamIsNotDeveloperID() {
        XCTAssertFalse(UpdateInstallPolicy.installsSilently(signature: .developerID(team: "")))
    }

    /// A path that is not signed code never matches the running app's designated requirement.
    func testUnsignedCandidateDoesNotMatchRunningIdentity() {
        XCTAssertFalse(UpdateInstallPolicy.candidateMatchesRunningIdentity(URL(fileURLWithPath: "/nonexistent/LeanKeys.app")))
    }

    /// The running binary satisfies its own designated requirement.
    func testRunningBinaryMatchesItself() throws {
        let exe = try XCTUnwrap(Bundle.main.executableURL)
        XCTAssertTrue(UpdateInstallPolicy.candidateMatchesRunningIdentity(exe))
    }

    /// The live read must not crash; its value depends on how the test runner is signed.
    func testLiveReadIsConsistentWithPolicy() {
        XCTAssertEqual(
            UpdateInstallPolicy.installsSilently(),
            UpdateInstallPolicy.installsSilently(signature: UpdateInstallPolicy.currentSignature())
        )
    }
}
