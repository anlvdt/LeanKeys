import XCTest
@testable import LeanKeysKit

/// The release gate (spec 2026-11-28-privacy-opt-in §5): `sync/release.sh` refuses to publish unless these pass.
/// With nothing stored, nothing that writes down what the user types may be on, and switching it on needs consent.
final class PrivacyDefaultsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PrivacyDefaultsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeLearning(_ book: UndoRuleBook = UndoRuleBook(store: nil)) -> UndoLearning {
        UndoLearning(book: book, defaults: defaults, probe: {
            LearnContextProbe(bundleID: "com.apple.TextEdit", pid: nil, secureInput: false, now: Date())
        }, secureField: { _ in false }, onRecordQueue: { $0() })
    }

    // MARK: Release gate

    func testFreshInstallLearnsNothing() {
        let learning = makeLearning()
        XCTAssertFalse(learning.learning, "Nhớ từ bạn sửa is off until the user agrees")
        XCTAssertFalse(learning.privacyNoticePending, "a fresh install has nothing to tell")
        XCTAssertFalse(defaults.bool(forKey: ShortcutSuggestionsModel.enabledKey), "Gợi ý gõ tắt is off")
        XCTAssertFalse(defaults.bool(forKey: ShortcutSuggestionsModel.consentKey))
    }

    func testDebugLogKeepFileIsNotShipped() {
        // The app never creates `debug.keep`; the build must not carry one either.
        let resources = Bundle(for: UndoLearning.self).bundleURL
        let found = FileManager.default.enumerator(at: resources, includingPropertiesForKeys: nil)?
            .contains { ($0 as? URL)?.lastPathComponent == "debug.keep" } ?? false
        XCTAssertFalse(found)
        XCTAssertFalse(DebugLog.settingsSubtitle.isEmpty)
        XCTAssertTrue(DebugLog.settingsSubtitle.contains("không gửi đi đâu"))
    }

    func testConsentCopySaysDataStaysOnTheMac() {
        XCTAssertTrue(UndoLearningSection.consentText.contains("Dữ liệu chỉ nằm trên máy này"))
        XCTAssertTrue(UndoLearningSection.consentText.contains("không bao giờ gửi đi đâu"))
        XCTAssertTrue(LearnSettingsSection.consentText.contains("không bao giờ gửi đi đâu"))
        XCTAssertEqual(UndoLearningSection.consentTitle, "Cho LeanKeys nhớ từ bạn sửa?")
        XCTAssertEqual(UndoLearningSection.consentConfirm, "Cho phép")
        XCTAssertEqual(UndoLearningSection.consentCancel, "Không")
    }

    // MARK: Consent

    func testTurningOnNeedsConsent() {
        let learning = makeLearning()
        XCTAssertEqual(learning.setLearning(true), .needsConsent)
        XCTAssertFalse(learning.learning)
        XCTAssertTrue(learning.learningConsentPending)
        learning.cancelLearningConsent()
        XCTAssertFalse(learning.learning)
        XCTAssertFalse(defaults.bool(forKey: UndoLearning.learningConsentKey))

        _ = learning.setLearning(true)
        learning.confirmLearningConsent()
        XCTAssertTrue(learning.learning)
        XCTAssertTrue(defaults.bool(forKey: UndoLearning.learningConsentKey))
        XCTAssertEqual(learning.setLearning(false), .disabled)
        XCTAssertEqual(learning.setLearning(true), .enabled, "asked once")
    }

    func testNoNameLearnedWithoutConsent() {
        let learning = makeLearning()
        learning.userCapitalized("Orca", previous: "con")
        learning.userCapitalized("Orca", previous: "con")
        XCTAssertTrue(learning.learnedNames.names.isEmpty, "learning names needs Nhớ từ bạn sửa")
    }

    func testAskFromPopoverCard() {
        let learning = makeLearning()
        learning.askConsentAndEnable { _, _, _, _ in false }
        XCTAssertFalse(learning.learning)
        learning.askConsentAndEnable { title, _, _, _ in title == UndoLearningSection.consentTitle }
        XCTAssertTrue(learning.learning)
    }

    // MARK: Existing users (phương án A)

    func testUserWhoNeverSetTheSwitchIsTurnedOffAndTold() {
        let book = UndoRuleBook(store: nil)
        book.record(before: "cos", previous: "thich", reverse: false)
        let learning = makeLearning(book)
        XCTAssertFalse(learning.learning)
        XCTAssertTrue(learning.privacyNoticePending, "learned data exists: the popover card shows once")
        learning.dismissPrivacyNotice()
        XCTAssertFalse(makeLearning(book).privacyNoticePending, "answered once, never again")
        XCTAssertFalse(book.rules.isEmpty, "learned data is kept")
    }

    func testUserWhoTurnedItOnKeepsIt() {
        defaults.set(true, forKey: UndoLearning.learningKey)
        let learning = makeLearning()
        XCTAssertTrue(learning.learning)
        XCTAssertTrue(defaults.bool(forKey: UndoLearning.learningConsentKey))
        XCTAssertFalse(learning.privacyNoticePending)
    }

    func testUserWhoTurnedItOffKeepsItOff() {
        defaults.set(false, forKey: UndoLearning.learningKey)
        let learning = makeLearning()
        XCTAssertFalse(learning.learning)
        XCTAssertFalse(learning.privacyNoticePending)
    }
}
