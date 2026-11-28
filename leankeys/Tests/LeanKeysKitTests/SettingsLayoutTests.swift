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

    func testRestoreRowCopyPerEngine() {
        XCTAssertTrue(SettingsLayout.showsRestoreShortcut(active: .vikey))
        XCTAssertTrue(SettingsLayout.showsRestoreShortcut(active: .gonhanh))
        XCTAssertEqual(SettingsLayout.restoreRowTitle(active: .vikey), "Đổi từ vừa gõ Việt ⇄ Anh")
        XCTAssertEqual(SettingsLayout.restoreRowSubtitle(active: .vikey), "Bấm ngay sau một từ: cos → có, bể → beer")
        XCTAssertEqual(SettingsLayout.restoreRowTitle(active: .gonhanh), "Trả từ đang gõ về phím gốc")
        XCTAssertEqual(SettingsLayout.restoreRowSubtitle(active: .gonhanh),
                       "Ví dụ: việt → vieejt · Bấm để đổi phím tắt")
    }
}
