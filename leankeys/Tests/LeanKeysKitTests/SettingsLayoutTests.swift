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

    func testAdvancedSettingsApplyWithoutTheHiddenAdvancedSwitch() {
        // Copy audit I2: the Nâng cao page is always shown, so its settings must work with advancedMode off (default).
        XCTAssertFalse(SettingsLayout.showsAdvancedModeToggle)
        XCTAssertTrue(SettingsLayout.advancedSettingsApply(advancedMode: false))
        XCTAssertTrue(SettingsLayout.advancedSettingsApply(advancedMode: true))
    }
}
