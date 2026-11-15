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
    }

    /// Ruling R24, exact wording; the minus is U+2212.
    func testReturningUserGetsTheRegrantSteps() {
        let copy = LeanOnboardingView.Strings.copy(wasTrusted: true)
        XCTAssertEqual(copy.title, "LeanKeys vừa được cập nhật")
        XCTAssertEqual(copy.message,
                       "macOS cần bạn cấp lại quyền Trợ năng: mở Cài đặt Trợ năng, chọn LeanKeys, bấm nút − để xoá, rồi bấm + và thêm lại LeanKeys.")
        XCTAssertTrue(copy.message.unicodeScalars.contains("\u{2212}"))
        XCTAssertEqual(LeanOnboardingView.Strings.openSettings, "Cấp quyền Trợ năng")
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
