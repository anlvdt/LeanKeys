import XCTest
@testable import LeanKeysKit

final class LearnSettingsSectionTests: XCTestCase {
    func testOneNameForTheFeature() {
        // Copy audit B1: the switch, the Nâng cao card and the popover line all say "Gợi ý gõ tắt".
        XCTAssertEqual(LearnSettingsSection.toggleTitle, "Gợi ý gõ tắt")
        XCTAssertEqual(LearnSettingsSection.advancedTitle, "Gợi ý gõ tắt")
        XCTAssertFalse(LearnSettingsSection.toggleSubtitle.contains(LearnSettingsSection.toggleTitle))
    }

    func testEraseNamesWhatItErases() {
        // B2: the 4C/4D lists ("Từ giữ nguyên", "Tên đã học") sit right below; this button erases 4B data only.
        XCTAssertEqual(LearnSettingsSection.eraseLabel, "Xoá dữ liệu gợi ý gõ tắt")
        XCTAssertEqual(LearnSettingsSection.eraseConfirmTitle, "Xoá dữ liệu gợi ý gõ tắt?")
        XCTAssertTrue(LearnSettingsSection.eraseConfirmMessage.contains("Bảng gõ tắt vẫn giữ nguyên"))
    }

    func testExclusionListSaysItCoversEveryLearner() {
        XCTAssertEqual(LearnSettingsSection.excludedTitle, "Không học khi gõ trong")
        XCTAssertTrue(LearnSettingsSection.excludedHelp.contains("từ giữ nguyên"))
        XCTAssertTrue(LearnSettingsSection.excludedHelp.contains("tên đã học"))
        XCTAssertEqual(LearnSettingsSection.addAppLabel, "Thêm ứng dụng…")
    }

    func testEveryDefaultExclusionHasADistinctName() {
        // B5: without a name, an uninstalled default showed as the last bundle-ID part ("hyper", "Warp-Stable").
        for id in Exclusions.defaultBundleIDs {
            XCTAssertNotNil(LearnSettingsSection.knownNames[id], id)
        }
        let names = Exclusions.defaultBundleIDs.compactMap { LearnSettingsSection.knownNames[$0] }
        XCTAssertEqual(Set(names).count, names.count, "two defaults share a name")
    }

    func testDefaultsSortByShownName() {
        let ids: Set<String> = ["b.zeta", "a.Alpha", "c.beta", "d.beta"]
        let names = ["b.zeta": "zeta", "a.Alpha": "Alpha", "c.beta": "beta", "d.beta": "beta"]
        XCTAssertEqual(LearnSettingsSection.sortedByName(ids) { names[$0]! }, ["a.Alpha", "c.beta", "d.beta", "b.zeta"])
    }
}
