import XCTest
@testable import LeanKeysKit

final class OnboardingCopyTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingCopyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFirstRunGetsTheWelcome() {
        let copy = LeanOnboardingView.Strings.copy(wasTrusted: false)
        XCTAssertEqual(copy.title, "Chào mừng đến với LeanKeys")
        XCTAssertEqual(copy.message, LeanOnboardingView.Strings.message)
        // Copy audit F1: says what to do once System Settings opens.
        XCTAssertEqual(copy.message, "Bấm nút bên dưới, rồi bật công tắc cạnh LeanKeys trong Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Trợ năng. Sau đó cứ thế gõ — LeanKeys tự chuyển Việt/Anh cho bạn.")
    }

    /// Ruling R24's steps, worded per copy audit F2 (only names a control that exists: the button); the minus is U+2212.
    func testReturningUserGetsTheRegrantSteps() {
        let copy = LeanOnboardingView.Strings.copy(wasTrusted: true)
        XCTAssertEqual(copy.title, "LeanKeys vừa được cập nhật")
        XCTAssertEqual(copy.message,
                       "macOS cần bạn cấp lại quyền Trợ năng. Bấm nút bên dưới, chọn LeanKeys trong danh sách, bấm − để xoá, rồi bấm + và chọn lại LeanKeys trong thư mục Ứng dụng.")
        XCTAssertTrue(copy.message.unicodeScalars.contains("\u{2212}"))
        XCTAssertEqual(LeanOnboardingView.Strings.openSettings, "Cấp quyền Trợ năng")
    }

    /// The reset worked: the copy tells the user to press the button, then re-enable LeanKeys.
    func testCopyWhenResetDone() {
        let copy = LeanOnboardingView.Strings.copy(wasTrusted: true, resetDone: true)
        XCTAssertEqual(copy.title, "LeanKeys vừa được cập nhật")
        XCTAssertEqual(copy.message, "Bấm nút bên dưới, rồi bật lại công tắc cạnh LeanKeys trong danh sách Trợ năng.")
    }

    /// The reset failed: the existing −/+ instructions remain.
    func testCopyFallsBackWhenResetFailed() {
        let copy = LeanOnboardingView.Strings.copy(wasTrusted: true, resetDone: false)
        XCTAssertEqual(copy.message,
                       "macOS cần bạn cấp lại quyền Trợ năng. Bấm nút bên dưới, chọn LeanKeys trong danh sách, bấm \u{2212} để xoá, rồi bấm + và chọn lại LeanKeys trong thư mục Ứng dụng.")
    }

    func testWasTrustedIsRecordedOnlyWhenTrustedAndNeverCleared() {
        XCTAssertFalse(ReturningUser.wasTrusted(defaults: defaults))
        ReturningUser.record(isTrusted: false, defaults: defaults)
        XCTAssertFalse(ReturningUser.wasTrusted(defaults: defaults))
        ReturningUser.record(isTrusted: true, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: "LeanKeys.wasTrusted"))
        ReturningUser.record(isTrusted: false, defaults: defaults)
        XCTAssertTrue(ReturningUser.wasTrusted(defaults: defaults))
    }
}
