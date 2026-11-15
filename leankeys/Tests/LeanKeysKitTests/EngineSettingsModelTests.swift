import Combine
import XCTest
@testable import LeanKeysKit

private final class StubEngine: TypingEngine {
    var isVietnamese = true
    func process(keyCode: UInt16, caps: Bool, shift: Bool) -> EngineEdit? { nil }
    func resetContext() {}
    func setVietnamese(_ on: Bool) { isVietnamese = on }
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

    private func makeRouter(failingVikey: Bool = false) -> EngineRouter {
        EngineRouter(defaults: defaults, makeVikey: { failingVikey ? nil : StubEngine() })
    }

    func testModelReflectsRouter() {
        let router = makeRouter()
        let model = EngineSettingsModel(router: router)
        XCTAssertEqual(model.selected, .gonhanh)

        model.selected = .vikey
        XCTAssertEqual(router.selected, .vikey)
        XCTAssertEqual(router.active, .vikey)

        model.selected = .gonhanh
        XCTAssertEqual(router.selected, .gonhanh)
    }

    func testModelStartsFromStoredEngine() {
        let router = makeRouter()
        router.selected = .vikey
        XCTAssertEqual(EngineSettingsModel(router: router).selected, .vikey)
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
        let router = makeRouter()
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
        XCTAssertEqual(model.vikeyDisabledReason, "Không khởi động được engine Vikey — đang dùng Gõ Nhanh")
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
        let router = makeRouter()
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
}
