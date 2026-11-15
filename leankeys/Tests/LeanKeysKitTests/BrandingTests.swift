import Foundation
import XCTest
@testable import LeanKeysKit

final class BrandingTests: XCTestCase {
    /// Repo root, found from this file: leankeys/Tests/LeanKeysKitTests/BrandingTests.swift.
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func json(_ path: String) throws -> [String: String] {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    func testVersionsLoad() throws {
        let file = try json("leankeys/LeanKeysKit/Resources/Versions.json")
        let loaded = LeanVersions.load()
        XCTAssertEqual(loaded.leankeys, file["leankeys"])
        XCTAssertEqual(loaded.gonhanh, file["gonhanh"])
        XCTAssertEqual(loaded.vikey, file["vikey"])
        XCTAssertEqual(loaded.leankeys, "1.0")
    }

    /// The About screen's engine versions must name the upstream tags the fork is built from.
    func testVersionsMatchUpstreamTags() throws {
        let upstream = try json("sync/upstream.json")
        let loaded = LeanVersions.load()
        XCTAssertEqual(loaded.gonhanh, upstream["gonhanh"])
        XCTAssertEqual(loaded.vikey, upstream["vikey"])
        XCTAssertEqual(LeanVersions.engineLine, "Gõ Nhanh \(loaded.gonhanh) · Vikey \(loaded.vikey)")
    }

    func testAcknowledgementsMentionAllSources() {
        let text = LeanAcknowledgements.text
        for needle in ["Gõ Nhanh", "khaphanspace", "BSD-3-Clause", "Vikey", "Tony Dinh", "OpenKey", "Mai Vũ Tuyên", "GPL-3.0"] {
            XCTAssertTrue(text.contains(needle), "acknowledgements lack \(needle)")
        }
        for credit in LeanAcknowledgements.credits {
            XCTAssertNotNil(URL(string: credit.repository), credit.name)
            XCTAssertTrue(credit.repository.hasPrefix("https://github.com/"), credit.name)
        }
    }

    func testBrandingValues() {
        XCTAssertEqual(LeanBranding.name, "LeanKeys")
        XCTAssertEqual(LeanBranding.repository, "https://github.com/anlvdt/LeanKeys")
        XCTAssertEqual(LeanBranding.releasesAPI, "https://api.github.com/repos/anlvdt/LeanKeys/releases")
        XCTAssertEqual(LeanBranding.issuesURL, "https://github.com/anlvdt/LeanKeys/issues")
    }
}
