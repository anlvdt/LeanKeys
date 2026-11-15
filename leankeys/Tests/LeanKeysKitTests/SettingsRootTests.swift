import XCTest
@testable import LeanKeysKit

final class SettingsRootTests: XCTestCase {
    func testPagesInOrder() {
        XCTAssertEqual(SettingsPage.allCases.map(\.title), ["Chung", "Phím tắt", "Nâng cao", "Giới thiệu"])
    }

    func testSymbols() {
        XCTAssertEqual(SettingsPage.allCases.map(\.symbol),
                       ["gearshape", "keyboard", "wrench.and.screwdriver", "info.circle"])
    }

    func testLegacyMapping() {
        XCTAssertEqual(SettingsPage(legacyRawValue: "Cài đặt"), .general)
        XCTAssertEqual(SettingsPage(legacyRawValue: "Nâng cao"), .advanced)
        XCTAssertEqual(SettingsPage(legacyRawValue: "Giới thiệu"), .about)
        XCTAssertNil(SettingsPage(legacyRawValue: "x"))
    }

    func testOnlyAdvancedManagesItsOwnScrolling() {
        XCTAssertEqual(SettingsPage.allCases.filter { !$0.scrollsContent }, [.advanced])
    }
}
