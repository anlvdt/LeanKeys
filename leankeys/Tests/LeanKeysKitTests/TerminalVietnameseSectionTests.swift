import XCTest
@testable import LeanKeysKit

final class TerminalVietnameseSectionTests: XCTestCase {
    /// Only terminals installed on this Mac are listed, by display name.
    func testListsOnlyInstalledTerminals() {
        let installed = ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app"),
                         "com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")]
        let rows = TerminalVietnameseSection.installedTerminals(appURL: { installed[$0] })
        XCTAssertEqual(Set(rows.map(\.bundleID)), Set(installed.keys))
        XCTAssertEqual(rows.map(\.name), rows.map(\.name).sorted(), "sorted by name")
        XCTAssertTrue(rows.allSatisfy { !$0.name.isEmpty })
    }

    func testNoTerminalInstalledListsNothing() {
        XCTAssertTrue(TerminalVietnameseSection.installedTerminals(appURL: { _ in nil }).isEmpty)
    }

    func testCopy() {
        XCTAssertEqual(TerminalVietnameseSection.title, "Gõ tiếng Việt trong terminal")
        XCTAssertEqual(TerminalVietnameseSection.note,
                       "Chuyển sang English trước khi gõ mật khẩu (sudo, ssh): LeanKeys không biết lúc nào terminal hỏi mật khẩu. Thứ gõ trong terminal không bao giờ được học.")
    }
}
