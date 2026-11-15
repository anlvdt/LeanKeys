import XCTest
@testable import LeanKeysKit

/// Records every call. Models a word buffer: once a key went in since the last reset, the next edit deletes one
/// character (a stale buffer shows up as deleteCount > 0).
private final class FakeEngine: TypingEngine {
    var processCalls = 0
    var resetCalls = 0
    var setVietnameseCalls: [Bool] = []
    var isVietnamese = true
    var buffered = 0
    /// When set, returned as is instead of the buffer model.
    var scripted: EngineEdit??

    func process(keyCode: UInt16, caps: Bool, shift: Bool) -> EngineEdit? {
        processCalls += 1
        if let scripted { return scripted }
        let edit = EngineEdit(deleteCount: buffered > 0 ? 1 : 0, text: ["x"], languageChanged: false)
        buffered += 1
        return edit
    }

    func resetContext() {
        resetCalls += 1
        buffered = 0
    }

    func setVietnamese(_ on: Bool) {
        setVietnameseCalls.append(on)
        isVietnamese = on
    }
}

private func isPass(_ result: InterceptResult) -> Bool {
    if case .passToGoNhanh = result { return true }
    return false
}

private func handled(_ result: InterceptResult) -> (Int, [Character], Bool)?? {
    if case .handled(let r) = result { return .some(r) }
    return .none
}

final class EngineRouterTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var fake: FakeEngine!
    private var factoryCalls = 0

    override func setUp() {
        super.setUp()
        suiteName = "EngineRouterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        fake = FakeEngine()
        factoryCalls = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeRouter(failingVikey: Bool = false) -> EngineRouter {
        EngineRouter(defaults: defaults, makeVikey: { [unowned self] in
            self.factoryCalls += 1
            return failingVikey ? nil : self.fake
        })
    }

    private func press(_ router: EngineRouter, ctrl: Bool = false) -> InterceptResult {
        router.intercept(keyCode: 0, caps: false, ctrl: ctrl, shift: false)
    }

    func testDefaultIsGoNhanh() {
        let router = makeRouter()
        XCTAssertEqual(router.selected, .gonhanh)
        XCTAssertEqual(router.active, .gonhanh)
        XCTAssertNil(router.fallbackReason)
        XCTAssertTrue(isPass(press(router)))
        XCTAssertTrue(isPass(press(router, ctrl: true)), "Gõ Nhanh handles its own shortcuts")
        XCTAssertEqual(factoryCalls, 0, "Vikey is built only when first needed")
    }

    func testSelectedPersistsUnderLeanKeysEngineKey() {
        let router = makeRouter()
        router.selected = .vikey
        XCTAssertEqual(defaults.string(forKey: "LeanKeys.engine"), "vikey")
        XCTAssertEqual(makeRouter().selected, .vikey)
    }

    func testVikeySelectedHandles() {
        let router = makeRouter()
        router.selected = .vikey
        XCTAssertEqual(router.active, .vikey)

        fake.scripted = .some(EngineEdit(deleteCount: 2, text: ["á", "b"], languageChanged: false))
        guard let some = handled(press(router)), let r = some else { return XCTFail("expected .handled(edit)") }
        XCTAssertEqual(r.0, 2)
        XCTAssertEqual(r.1, ["á", "b"])
        XCTAssertTrue(r.2)

        fake.scripted = .some(nil)
        guard let none = handled(press(router)) else { return XCTFail("expected .handled(nil)") }
        XCTAssertNil(none)
    }

    func testVNIForcesGoNhanh() {
        let router = makeRouter()
        router.selected = .vikey
        router.setMethod(1)
        XCTAssertEqual(router.active, .gonhanh)
        XCTAssertEqual(router.fallbackReason, "vni")
        XCTAssertTrue(isPass(press(router)))

        router.setMethod(0)
        XCTAssertEqual(router.active, .vikey)
        XCTAssertNil(router.fallbackReason)
    }

    func testVNIBeforeSelectingVikeyNeverBuildsIt() {
        let router = makeRouter()
        router.setMethod(1)
        router.selected = .vikey
        XCTAssertEqual(router.fallbackReason, "vni")
        XCTAssertTrue(isPass(press(router)))
        XCTAssertEqual(factoryCalls, 0)
    }

    func testVikeyInitFailureFallsBack() {
        let router = makeRouter(failingVikey: true)
        router.selected = .vikey
        XCTAssertEqual(router.active, .gonhanh)
        XCTAssertEqual(router.fallbackReason, "vikey-init-failed")
        XCTAssertTrue(isPass(press(router)))
        router.selected = .gonhanh
        XCTAssertNil(router.fallbackReason)
        router.selected = .vikey
        _ = press(router)
        XCTAssertEqual(router.fallbackReason, "vikey-init-failed")
        XCTAssertEqual(factoryCalls, 1, "a failed init is not retried")
    }

    func testVikeyBuiltOnceAcrossSwitches() {
        let router = makeRouter()
        for _ in 0..<3 {
            router.selected = .vikey
            _ = press(router)
            router.selected = .gonhanh
        }
        XCTAssertEqual(factoryCalls, 1)
    }

    func testBypassResetsAndPassesThrough() {
        let router = makeRouter()
        router.selected = .vikey
        let resets = fake.resetCalls
        let result = press(router, ctrl: true)
        guard let r = handled(result) else { return XCTFail("expected .handled(nil)") }
        XCTAssertNil(r)
        XCTAssertEqual(fake.resetCalls, resets + 1)
        XCTAssertEqual(fake.processCalls, 0, "a Ctrl chord never reaches Vikey")
    }

    func testSwitchEngineMidWordClearsState() {
        let router = makeRouter()
        router.selected = .vikey
        _ = press(router)
        _ = press(router)
        XCTAssertGreaterThan(fake.buffered, 0)

        var resets = fake.resetCalls
        router.selected = .gonhanh
        XCTAssertGreaterThan(fake.resetCalls, resets, "old engine reset")

        resets = fake.resetCalls
        router.selected = .vikey
        XCTAssertGreaterThan(fake.resetCalls, resets, "new engine reset")
        guard let some = handled(press(router)), let r = some else { return XCTFail("expected .handled(edit)") }
        XCTAssertEqual(r.0, 0, "no stale buffer after the switch")
    }

    func testLeavingVikeyForVNIClearsState() {
        let router = makeRouter()
        router.selected = .vikey
        _ = press(router)
        let resets = fake.resetCalls
        router.setMethod(1)
        XCTAssertGreaterThan(fake.resetCalls, resets)
    }

    func testLanguageChangeNotification() {
        let router = makeRouter()
        router.selected = .vikey
        fake.isVietnamese = false
        fake.scripted = .some(EngineEdit(deleteCount: 0, text: [], languageChanged: true))
        let expected = fake.isVietnamese
        let posted = expectation(forNotification: .leanKeysLanguageChanged, object: nil) { note in
            note.userInfo?["vietnamese"] as? Bool == expected
        }
        guard let some = handled(press(router)), let r = some else { return XCTFail("expected .handled(edit)") }
        XCTAssertEqual(r.0, 0)
        XCTAssertTrue(r.1.isEmpty)
        wait(for: [posted], timeout: 2)
    }

    func testSetEnabledForwardsToVikey() {
        let router = makeRouter()
        router.selected = .vikey
        router.setEnabled(false)
        XCTAssertEqual(fake.setVietnameseCalls.last, false)
    }

    func testSetEnabledBeforeVikeyExistsAppliesOnCreation() {
        let router = makeRouter()
        router.setEnabled(false)
        XCTAssertEqual(factoryCalls, 0)
        router.selected = .vikey
        XCTAssertEqual(fake.setVietnameseCalls.last, false)
        XCTAssertFalse(fake.isVietnamese)
    }

    func testClearResetsVikey() {
        let router = makeRouter()
        router.selected = .vikey
        _ = press(router)
        let resets = fake.resetCalls
        router.clear()
        XCTAssertEqual(fake.resetCalls, resets + 1)
    }

    func testKeyPassesThroughIsNotConsumed() {
        // Ruling R12: an edit whose key must still be typed reports keyConsumed == false.
        let router = makeRouter()
        router.selected = .vikey
        fake.scripted = .some(EngineEdit(deleteCount: 4, text: Array("test"), languageChanged: false, keyPassesThrough: true))
        let r = handled(press(router))
        XCTAssertEqual(r??.0, 4)
        XCTAssertEqual(r??.1, Array("test"))
        XCTAssertEqual(r??.2, false)

        fake.scripted = .some(EngineEdit(deleteCount: 1, text: ["x"], languageChanged: false))
        XCTAssertEqual(handled(press(router))??.2, true, "an ordinary edit stays consumed")
    }
}
