import XCTest
@testable import LeanKeysKit

final class SettingsLayoutTests: XCTestCase {
    func testGoNhanhOnlyRowsFollowActiveEngine() {
        XCTAssertTrue(SettingsLayout.showsGoNhanhOnlySettings(active: .gonhanh))
        XCTAssertFalse(SettingsLayout.showsGoNhanhOnlySettings(active: .vikey))
    }

    func testAdvancedModeToggleHidden() {
        XCTAssertFalse(SettingsLayout.showsAdvancedModeToggle)
    }
}
