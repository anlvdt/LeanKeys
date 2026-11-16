import XCTest
@testable import LeanKeysKit

final class StatusCardTests: XCTestCase {
    func testLanguageTitle() {
        XCTAssertEqual(StatusSnapshot(vietnamese: true, autoSwitchApplies: false, autoSwitchOn: false, blocked: false, blockingApp: nil).languageTitle, "Tiếng Việt")
        XCTAssertEqual(StatusSnapshot(vietnamese: false, autoSwitchApplies: false, autoSwitchOn: false, blocked: false, blockingApp: nil).languageTitle, "English")
    }

    func testAutoSwitchLine() {
        XCTAssertEqual(StatusSnapshot(vietnamese: true, autoSwitchApplies: true, autoSwitchOn: true, blocked: false, blockingApp: nil).autoSwitchLine, "Tự chuyển Việt/Anh: Bật")
        XCTAssertEqual(StatusSnapshot(vietnamese: true, autoSwitchApplies: true, autoSwitchOn: false, blocked: false, blockingApp: nil).autoSwitchLine, "Tự chuyển Việt/Anh: Tạm dừng")
        XCTAssertNil(StatusSnapshot(vietnamese: true, autoSwitchApplies: false, autoSwitchOn: true, blocked: false, blockingApp: nil).autoSwitchLine)
    }

    func testWarningLine() {
        XCTAssertEqual(StatusSnapshot(vietnamese: true, autoSwitchApplies: false, autoSwitchOn: false, blocked: true, blockingApp: "1Password").warningLine, "⚠︎ 1Password đang chặn gõ tiếng Việt")
        XCTAssertEqual(StatusSnapshot(vietnamese: true, autoSwitchApplies: false, autoSwitchOn: false, blocked: true, blockingApp: nil).warningLine, "⚠︎ Một ứng dụng đang chặn gõ tiếng Việt")
        XCTAssertNil(StatusSnapshot(vietnamese: true, autoSwitchApplies: false, autoSwitchOn: false, blocked: false, blockingApp: "1Password").warningLine)
    }

    func testWarningLineDisplayDropsGlyphOnlyForRender() {
        // The copy keeps the glyph; the orange triangle symbol replaces it on screen.
        XCTAssertEqual(WarningLine.displayText(for: "⚠︎ 1Password đang chặn gõ tiếng Việt"), "1Password đang chặn gõ tiếng Việt")
        XCTAssertEqual(WarningLine.displayText(for: "Vikey không hỗ trợ VNI — đang dùng Gõ Nhanh"), "Vikey không hỗ trợ VNI — đang dùng Gõ Nhanh")
    }

    func testWarningIsReadAsAWarningWithANextStep() {
        // Copy audit D3/D5: the triangle is hidden from VoiceOver, so the label says "Cảnh báo"; the tooltip says what to do.
        XCTAssertEqual(WarningLine.accessibilityText(for: "⚠︎ 1Password đang chặn gõ tiếng Việt"),
                       "Cảnh báo: 1Password đang chặn gõ tiếng Việt")
        XCTAssertTrue(StatusSnapshot.warningHelp.contains("Rời ô đó"))
    }

    func testAutoSwitchHelpSaysHowToResume() {
        let on = StatusSnapshot(vietnamese: true, autoSwitchApplies: true, autoSwitchOn: true, blocked: false, blockingApp: nil)
        let paused = StatusSnapshot(vietnamese: false, autoSwitchApplies: true, autoSwitchOn: false, blocked: false, blockingApp: nil)
        XCTAssertEqual(on.autoSwitchHelp, "LeanKeys tự chuyển Việt/Anh theo từ bạn gõ.")
        XCTAssertTrue(paused.autoSwitchHelp.contains("Chọn Tiếng Việt để bật lại"))
    }

    func testPopoverControlNames() {
        // D1/D2: the hidden picker labels are what VoiceOver reads; the quit button names the app.
        XCTAssertEqual(StatusPopoverView.languagePickerTitle, "Ngôn ngữ gõ")
        XCTAssertEqual(StatusPopoverView.methodPickerTitle, "Kiểu gõ")
        XCTAssertEqual(StatusPopoverView.quitLabel, "Thoát LeanKeys")
    }
}
