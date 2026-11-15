import XCTest
@testable import LeanKeysKit

final class SafeInstallerTests: XCTestCase {
    private let mount = URL(fileURLWithPath: "/Volumes/LeanKeys")
    private let app = URL(fileURLWithPath: "/Volumes/LeanKeys/LeanKeys.app")
    private let bundleID = "io.github.anlvdt.leankeys"

    private func checks(exists: Bool = true, id: String? = "io.github.anlvdt.leankeys", codesign: Bool = true,
                        sameIdentity: Bool = true) -> SafeInstaller.Checks
    {
        SafeInstaller.Checks(
            appExists: { _ in exists },
            bundleIdentifier: { _ in id },
            codesignValid: { _ in codesign },
            sameIdentity: { _ in sameIdentity }
        )
    }

    private func verify(_ checks: SafeInstaller.Checks, expected: String? = "io.github.anlvdt.leankeys",
                        requireSameIdentity: Bool = false) -> SafeInstaller.Verdict
    {
        SafeInstaller.verify(mountPoint: mount, appName: "LeanKeys", expectedBundleID: expected, checks: checks,
                             requireSameIdentity: requireSameIdentity)
    }

    func testAcceptsValidUpdate() {
        XCTAssertEqual(verify(checks()), .valid(app))
    }

    func testRejectsMissingApp() {
        XCTAssertEqual(verify(checks(exists: false)), .missingApp)
    }

    func testRejectsWrongBundleID() {
        XCTAssertEqual(verify(checks(id: "org.gonhanh.GoNhanh")), .wrongBundleID(found: "org.gonhanh.GoNhanh"))
        XCTAssertEqual(verify(checks(id: nil)), .wrongBundleID(found: nil))
        XCTAssertEqual(verify(checks(), expected: nil), .wrongBundleID(found: bundleID),
                       "no running bundle ID to compare against is a rejection")
    }

    func testRejectsFailedCodesign() {
        XCTAssertEqual(verify(checks(codesign: false)), .codesignFailed)
    }

    func testChecksRunInOrderAndStopAtFirstFailure() {
        var codesignCalls = 0
        let c = SafeInstaller.Checks(appExists: { _ in true }, bundleIdentifier: { _ in "other" },
                                     codesignValid: { _ in codesignCalls += 1; return true },
                                     sameIdentity: { _ in true })
        XCTAssertEqual(verify(c), .wrongBundleID(found: "other"))
        XCTAssertEqual(codesignCalls, 0)
    }

    // Silent install only: the candidate must satisfy the running app's designated requirement.
    func testSilentInstallRejectsDifferentIdentity() {
        XCTAssertEqual(verify(checks(sameIdentity: false), requireSameIdentity: true), .differentIdentity)
    }

    func testSilentInstallAcceptsSameIdentity() {
        XCTAssertEqual(verify(checks(sameIdentity: true), requireSameIdentity: true), .valid(app))
    }

    // The one-click path (restartToUpdate) does not require the identity: the user chose to install.
    func testOneClickInstallDoesNotCheckIdentity() {
        XCTAssertEqual(verify(checks(sameIdentity: false)), .valid(app))
    }

    func testIdentityIsCheckedAfterCodesign() {
        XCTAssertEqual(verify(checks(codesign: false, sameIdentity: false), requireSameIdentity: true), .codesignFailed)
    }

    func testOnlySuccessfulHTTPDownloadsAreKept() {
        let url = URL(string: "https://example.com/LeanKeys.dmg")!
        func response(_ code: Int) -> URLResponse {
            HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
        }
        XCTAssertTrue(SafeInstaller.isSuccessfulDownload(response(200)))
        XCTAssertTrue(SafeInstaller.isSuccessfulDownload(response(204)))
        XCTAssertFalse(SafeInstaller.isSuccessfulDownload(response(404)))
        XCTAssertFalse(SafeInstaller.isSuccessfulDownload(response(500)))
        XCTAssertFalse(SafeInstaller.isSuccessfulDownload(response(302)))
        XCTAssertFalse(SafeInstaller.isSuccessfulDownload(nil))
        XCTAssertTrue(SafeInstaller.isSuccessfulDownload(URLResponse(url: url, mimeType: nil, expectedContentLength: 0,
                                                                     textEncodingName: nil)),
                      "a non-HTTP response (file URL) has no status to reject")
    }

    func testSwapScriptShipsWithTheKit() throws {
        let url = try XCTUnwrap(SafeInstaller.swapScriptURL)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("trap"), "the relaunch must run on every exit")
    }
}
