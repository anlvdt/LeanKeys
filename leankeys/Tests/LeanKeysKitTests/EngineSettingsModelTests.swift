import Combine
import XCTest
@testable import LeanKeysKit

private final class StubEngine: TypingEngine {
    var isVietnamese = true
    func process(keyCode: UInt16, caps: Bool, shift: Bool) -> EngineEdit? { nil }
    func resetContext() {}
    func setVietnamese(_ on: Bool) { isVietnamese = on }
    func setAutoSwitch(_ on: Bool) {}
    func setModernTone(_ on: Bool) {}
}

final class EngineSettingsModelTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "EngineSettingsModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// `stored` writes "LeanKeys.engine" first, as if the user had picked that engine earlier.
    private func makeRouter(failingVikey: Bool = false, stored: EngineKind? = nil) -> EngineRouter {
        if let stored { defaults.set(stored.rawValue, forKey: "LeanKeys.engine") }
        return EngineRouter(defaults: defaults, makeVikey: { failingVikey ? nil : StubEngine() })
    }

    func testModelReflectsRouter() {
        let router = makeRouter()
        let model = EngineSettingsModel(router: router)
        XCTAssertEqual(model.selected, .vikey, "Vikey is the default")

        model.selected = .gonhanh
        XCTAssertEqual(router.selected, .gonhanh)
        XCTAssertEqual(router.active, .gonhanh)

        model.selected = .vikey
        XCTAssertEqual(router.selected, .vikey)
        XCTAssertEqual(router.active, .vikey)
    }

    func testModelStartsFromStoredEngine() {
        XCTAssertEqual(EngineSettingsModel(router: makeRouter(stored: .gonhanh)).selected, .gonhanh)
    }

    func testVNIReasonShown() {
        let router = makeRouter()
        let model = EngineSettingsModel(router: router)
        model.selected = .vikey
        XCTAssertNil(model.vikeyDisabledReason)

        router.setMethod(1)
        XCTAssertEqual(model.vikeyDisabledReason, "Vikey không hỗ trợ VNI — đang dùng Gõ Nhanh")

        router.setMethod(0)
        XCTAssertNil(model.vikeyDisabledReason)
    }

    func testVNIReasonHiddenWhileGoNhanhSelected() {
        let router = makeRouter(stored: .gonhanh)
        router.setMethod(1)
        let model = EngineSettingsModel(router: router)
        XCTAssertNil(model.vikeyDisabledReason)

        model.selected = .vikey
        XCTAssertEqual(model.vikeyDisabledReason, "Vikey không hỗ trợ VNI — đang dùng Gõ Nhanh")
    }

    func testInitFailureReasonShown() {
        let router = makeRouter(failingVikey: true)
        let model = EngineSettingsModel(router: router)
        model.selected = .vikey
        XCTAssertEqual(model.vikeyDisabledReason, "Không khởi động được lõi gõ Vikey — đang dùng Gõ Nhanh")
    }

    func testDefaultsChangeAsksViewToRerender() {
        let model = EngineSettingsModel(router: makeRouter())
        var changes = 0
        let sub = model.objectWillChange.sink { changes += 1 }
        defer { sub.cancel() }

        // Gõ Nhanh's method picker calls RustBridge.setMethod, then writes UserDefaults.standard.
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
        XCTAssertEqual(changes, 1)
    }

    func testEngineChangedFiresOncePerChange() {
        let router = makeRouter(stored: .gonhanh)
        var calls = 0
        let model = EngineSettingsModel(router: router, onEngineChanged: { calls += 1 })
        XCTAssertEqual(calls, 0, "building the model is not a change")

        model.selected = .vikey
        XCTAssertEqual(calls, 1)
        model.selected = .vikey
        XCTAssertEqual(calls, 1, "re-selecting the same engine is not a change")
        model.selected = .gonhanh
        XCTAssertEqual(calls, 2)
    }

    func testPickerCopy() {
        XCTAssertEqual(EngineSettingsSection.title, "Lõi gõ")
        XCTAssertEqual(EngineSettingsSection.automaticLabel, "Tự động (khuyên dùng)")
        XCTAssertEqual(EngineSettingsSection.goNhanhOnlyLabel, "Chỉ dùng Gõ Nhanh")
    }

    func testVikeyNoteOnlyUnderAutomatic() {
        let model = EngineSettingsModel(router: makeRouter())
        XCTAssertTrue(model.showsVikeyNote, "Tự động (Vikey) is the default and shows the note")
        model.selected = .gonhanh
        XCTAssertFalse(model.showsVikeyNote)
        model.selected = .vikey
        XCTAssertTrue(model.showsVikeyNote)
    }

    func testAutomaticKeepsFallbackReasons() {
        // "Tự động" is .vikey: with VNI or a failed Vikey it still types with Gõ Nhanh and says why.
        let router = makeRouter(failingVikey: true)
        let model = EngineSettingsModel(router: router)
        XCTAssertEqual(model.selected, .vikey)
        XCTAssertEqual(router.active, .gonhanh)
        XCTAssertTrue(model.showsVikeyNote)
        XCTAssertEqual(model.vikeyDisabledReason, "Không khởi động được lõi gõ Vikey — đang dùng Gõ Nhanh")
    }

    func testVikeyNoteIsOneLineWithDetailInTooltip() {
        let note = "Ở chế độ Tự động, các mục chỉ dành cho Gõ Nhanh được ẩn."
        let detail = "Ẩn ở chế độ Tự động vì chỉ Gõ Nhanh có: Gõ W thành Ư, Gõ [ ] thành Ơ Ư, Tự khôi phục tiếng Anh, Tự viết hoa đầu câu, Trả từ đang gõ về phím gốc. Chọn kiểu gõ VNI thì LeanKeys tự dùng Gõ Nhanh."
        XCTAssertEqual(EngineSettingsSection.vikeyNote, note)
        XCTAssertFalse(EngineSettingsSection.vikeyNote.contains("\n"))
        XCTAssertEqual(EngineSettingsSection.vikeyNoteDetail, detail)
        for text in [EngineSettingsSection.vikeyNote, EngineSettingsSection.vikeyNoteDetail] {
            XCTAssertFalse(text.contains("giai đoạn"))
        }
    }
}
